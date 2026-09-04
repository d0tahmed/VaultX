import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/crypto_errors.dart';
import '../crypto/kdf_profile.dart';
import '../crypto/key_hierarchy.dart';
import '../crypto/media_cipher.dart';
import '../crypto/secure_envelope.dart';
import '../crypto/shredder.dart';
import '../crypto/sodium_context.dart';
import '../crypto/vault_keyring.dart';
import 'secure_store.dart';

/// Raised when the poison pill has fired and the vault no longer exists.
final class VaultDestroyed implements Exception {
  const VaultDestroyed();
  @override
  String toString() => 'VaultDestroyed: the vault was cryptographically shredded.';
}

/// Raised when too many failed attempts have triggered a cooldown.
final class VaultLockedOut implements Exception {
  const VaultLockedOut(this.remaining);
  final Duration remaining;
  @override
  String toString() => 'VaultLockedOut: retry in ${remaining.inSeconds}s.';
}

/// Raised when the on-disk keyring is older than the one this device last saw.
final class VaultRolledBack implements Exception {
  const VaultRolledBack(this.seen, this.expected);
  final int seen;
  final int expected;
  @override
  String toString() =>
      'VaultRolledBack: keyring generation $seen is older than $expected.';
}

/// An unlocked vault. Holds live key material and must be disposed.
final class VaultSession {
  VaultSession._(this._unlocked);

  final KeyringUnlock _unlocked;
  bool _disposed = false;

  KeyHierarchy get hierarchy {
    if (_disposed) throw const KeyUnavailable();
    return _unlocked.hierarchy;
  }

  int get generation => _unlocked.generation;

  Uint8List get keyringId => _unlocked.keyringId;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unlocked.dispose();
  }
}

/// Owns the vault's files and the key lifecycle around them.
///
/// The expensive Argon2id derivation happens exactly once, at unlock, to
/// unwrap the master key. Reads and writes afterwards use a fast symmetric
/// subkey. v3 re-ran its whole key derivation on every single load *and* save,
/// which is both slow and needless.
final class VaultCryptoService {
  VaultCryptoService({
    required this.root,
    required this.store,
    this.attemptsBeforeDestruction = 8,
    this.attemptsBeforeCooldown = 5,
  });

  final Directory root;
  final SecureStore store;

  /// Failed attempts before the keyring is shredded. App-layer only: an
  /// attacker who copies the files off the device bypasses this entirely, so
  /// the real defence remains Argon2id's cost.
  final int attemptsBeforeDestruction;

  /// Failed attempts before a growing cooldown kicks in.
  final int attemptsBeforeCooldown;

  static const _generationKey = 'vaultx.keyring.generation';
  static const _keyringIdKey = 'vaultx.keyring.id';
  static const _failCountKey = 'vaultx.auth.failures';
  static const _lockoutKey = 'vaultx.auth.lockout';

  File get keyringFile => File('${root.path}/vaultx_keyring.json');
  File get documentFile => File('${root.path}/vaultx_vault.dat');
  /// Deliberately not `vaultx_media`: that is where v3 kept its *plaintext*
  /// media, and migration needs to read the old directory while writing this
  /// one. Sharing the path would mean overwriting sources mid-migration.
  Directory get mediaDirectory => Directory('${root.path}/vaultx_media_v4');

  Future<void> initialiseCrypto() => SodiumContext.ensureInitialised();

  Future<bool> vaultExists() => keyringFile.exists();

  // ------------------------------------------------------------------ create

  /// Creates a new vault. Refuses to clobber an existing one.
  Future<VaultSession> createVault({
    required Uint8List secret,
    KdfProfile profile = KdfProfile.balanced,
  }) async {
    await initialiseCrypto();
    if (await vaultExists()) {
      throw StateError('A vault already exists at ${root.path}.');
    }
    await root.create(recursive: true);

    final created = VaultKeyring.create(secret: secret, profile: profile);
    final unlocked = created.keyring.unlockWithSecret(secret);
    await _writeKeyring(created.keyring);
    await _recordGeneration(unlocked);
    await _clearFailures();
    created.hierarchy.dispose();

    final session = VaultSession._(unlocked);
    await saveDocument(session, const <String, Object?>{});
    return session;
  }

  // ------------------------------------------------------------------ unlock

  /// Unlocks with the user's PIN or passphrase.
  ///
  /// Wrong secrets are counted; the count drives cooldowns and, eventually,
  /// destruction. A successful unlock clears the counter.
  Future<VaultSession> unlockWithSecret(Uint8List secret) async {
    await initialiseCrypto();
    await _assertNotLockedOut();
    final keyring = await _readKeyring();
    final KeyringUnlock unlocked;
    try {
      unlocked = keyring.unlockWithSecret(secret);
    } on AuthenticationFailure {
      await _recordFailure();
      rethrow;
    }
    await _assertNotRolledBack(unlocked);
    await _clearFailures();
    return VaultSession._(unlocked);
  }

  /// Unlocks with the biometric-bound key held by the platform keystore.
  ///
  /// The PIN is never involved and is never stored. This is the replacement
  /// for v3, which kept the raw PIN so biometrics could re-derive the key.
  Future<VaultSession> unlockWithDeviceKey(SecureKey deviceKey) async {
    await initialiseCrypto();
    await _assertNotLockedOut();
    final keyring = await _readKeyring();
    final unlocked = keyring.unlockWithDeviceKey(deviceKey);
    await _assertNotRolledBack(unlocked);
    await _clearFailures();
    return VaultSession._(unlocked);
  }

  // ------------------------------------------------------------- credentials

  /// Enrols a device key so biometric unlock can work.
  Future<void> enrolDeviceKey({
    required VaultSession session,
    required SecureKey deviceKey,
  }) async {
    final keyring = await _readKeyring();
    await _writeKeyring(
      keyring.withDeviceSlot(unlocked: session._unlocked, deviceKey: deviceKey),
    );
  }

  /// Revokes biometric unlock, leaving the PIN as the only way in.
  Future<void> revokeDeviceKey() async {
    final keyring = await _readKeyring();
    await _writeKeyring(keyring.withoutDeviceSlot());
  }

  /// Changes the PIN or passphrase.
  ///
  /// Only the keyring is rewritten — the vault document and every media file
  /// keep their existing keys, so this is instant no matter how large the
  /// vault is. The device slot is dropped and must be re-enrolled.
  Future<void> changeSecret({
    required VaultSession session,
    required Uint8List newSecret,
    KdfProfile profile = KdfProfile.balanced,
  }) async {
    final keyring = await _readKeyring();
    final rotated = keyring.withChangedSecret(
      unlocked: session._unlocked,
      newSecret: newSecret,
      profile: profile,
    );
    await _writeKeyring(rotated);
    await store.write(_generationKey, '${session.generation + 1}');
  }

  // ------------------------------------------------------------------ document

  /// Reads and decrypts the vault document.
  Future<Map<String, Object?>> loadDocument(VaultSession session) async {
    if (!await documentFile.exists()) return <String, Object?>{};
    final key = session.hierarchy.deriveVaultDataKey();
    try {
      final plaintext = SecureEnvelope.openWithKey(
        key: key,
        envelope: await documentFile.readAsBytes(),
      );
      final decoded = json.decode(utf8.decode(plaintext));
      if (decoded is! Map) {
        throw const MalformedEnvelope('Vault document is not an object.');
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      key.dispose();
    }
  }

  /// Encrypts and writes the vault document.
  ///
  /// Written to a temporary file and then renamed, so a crash or a full disk
  /// cannot leave a half-written vault. v3 wrote in place, where an
  /// interrupted save destroyed the entire vault.
  Future<void> saveDocument(
    VaultSession session,
    Map<String, Object?> document,
  ) async {
    final key = session.hierarchy.deriveVaultDataKey();
    try {
      final sealed = SecureEnvelope.sealWithKey(
        key: key,
        plaintext: Uint8List.fromList(utf8.encode(json.encode(document))),
      );
      final temp = File('${documentFile.path}.tmp');
      await temp.writeAsBytes(sealed, flush: true);
      await temp.rename(documentFile.path);
    } finally {
      key.dispose();
    }
  }

  // --------------------------------------------------------------------- media

  /// Encrypts [source] into the media directory under [fileId].
  Future<File> importMedia({
    required VaultSession session,
    required File source,
    required String fileId,
  }) async {
    await mediaDirectory.create(recursive: true);
    final destination = mediaFileFor(fileId);
    final fileKey = session.hierarchy.deriveMediaFileKey(fileId);
    try {
      await MediaCipher.encryptFile(
        source: source,
        destination: destination,
        fileKey: fileKey,
      );
      return destination;
    } finally {
      fileKey.dispose();
    }
  }

  /// Decrypts a stored media file into memory.
  Future<Uint8List> readMedia({
    required VaultSession session,
    required String fileId,
  }) async {
    final fileKey = session.hierarchy.deriveMediaFileKey(fileId);
    try {
      return await MediaCipher.decryptToMemory(
        source: mediaFileFor(fileId),
        fileKey: fileKey,
      );
    } finally {
      fileKey.dispose();
    }
  }

  File mediaFileFor(String fileId) =>
      File('${mediaDirectory.path}/$fileId.vxm');

  Future<void> deleteMedia(String fileId) =>
      Shredder.shredFile(mediaFileFor(fileId));

  // ---------------------------------------------------------------------- wipe

  /// Destroys the vault.
  ///
  /// Order matters: the keyring goes first. Once it is gone every remaining
  /// byte is unopenable ciphertext, so a wipe interrupted part-way still
  /// leaves nothing recoverable. v3 deleted only the keystore entries and left
  /// the encrypted vault and the (unencrypted) media files sitting on disk.
  Future<void> destroyVault() async {
    await Shredder.shredFile(keyringFile);
    await store.deleteAll();
    await Shredder.shredFile(documentFile);
    await Shredder.shredFile(File('${documentFile.path}.tmp'));
    await Shredder.shredDirectory(mediaDirectory);
  }

  // ----------------------------------------------------------------- internals

  Future<VaultKeyring> _readKeyring() async {
    if (!await keyringFile.exists()) {
      throw const KeyUnavailable('No vault has been created on this device.');
    }
    return VaultKeyring.decode(await keyringFile.readAsBytes());
  }

  Future<void> _writeKeyring(VaultKeyring keyring) async {
    final temp = File('${keyringFile.path}.tmp');
    await temp.writeAsBytes(keyring.encode(), flush: true);
    await temp.rename(keyringFile.path);
  }

  Future<void> _recordGeneration(KeyringUnlock unlocked) async {
    await store.write(_generationKey, '${unlocked.generation}');
    await store.write(_keyringIdKey, base64.encode(unlocked.keyringId));
  }

  /// Rejects a keyring that has been swapped for an older copy.
  ///
  /// Without this, an attacker who captured the keyring before a PIN change
  /// could restore it and unlock with the revoked PIN. The highest generation
  /// seen lives in keystore-backed storage, which the vault files cannot
  /// rewrite on their own.
  Future<void> _assertNotRolledBack(KeyringUnlock unlocked) async {
    final recordedId = await store.read(_keyringIdKey);
    final currentId = base64.encode(unlocked.keyringId);
    if (recordedId != null && recordedId != currentId) {
      // A different vault entirely — treat it as fresh rather than as a
      // rollback, and adopt its identity.
      await _recordGeneration(unlocked);
      return;
    }
    final recorded = int.tryParse(await store.read(_generationKey) ?? '');
    if (recorded != null && unlocked.generation < recorded) {
      throw VaultRolledBack(unlocked.generation, recorded);
    }
    await _recordGeneration(unlocked);
  }

  Future<void> _assertNotLockedOut() async {
    final remaining = await remainingLockout();
    if (remaining > Duration.zero) throw VaultLockedOut(remaining);
  }

  /// How long until another attempt is allowed.
  Future<Duration> remainingLockout() async {
    final raw = await store.read(_lockoutKey);
    if (raw == null) return Duration.zero;
    final until = DateTime.tryParse(raw);
    if (until == null) return Duration.zero;
    final remaining = until.difference(DateTime.now());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  Future<int> failureCount() async =>
      int.tryParse(await store.read(_failCountKey) ?? '') ?? 0;

  Future<void> _clearFailures() async {
    await store.delete(_failCountKey);
    await store.delete(_lockoutKey);
  }

  Future<void> _recordFailure() async {
    // tryParse, not parse: a corrupted or attacker-written counter must not
    // crash the unlock path with a FormatException.
    final failures = (int.tryParse(await store.read(_failCountKey) ?? '') ?? 0) + 1;

    if (failures >= attemptsBeforeDestruction) {
      await destroyVault();
      throw const VaultDestroyed();
    }

    await store.write(_failCountKey, '$failures');

    if (failures >= attemptsBeforeCooldown) {
      final wait = Duration(seconds: 30 * (failures - attemptsBeforeCooldown + 1));
      await store.write(
        _lockoutKey,
        DateTime.now().add(wait).toIso8601String(),
      );
    }
  }
}
