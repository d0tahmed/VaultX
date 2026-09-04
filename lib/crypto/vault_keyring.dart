import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'crypto_errors.dart';
import 'kdf_profile.dart';
import 'key_hierarchy.dart';
import 'secure_envelope.dart';
import 'sodium_context.dart';

/// The set of wrapped copies of the master data key.
///
/// Each *slot* is an independent [SecureEnvelope] holding the same master key
/// under a different unlocking secret:
///
///  * `pin`    — wrapped by an Argon2id key derived from the user's PIN or
///               passphrase. This is the only slot that can exist alone.
///  * `device` — wrapped by a random key held in the platform keystore behind
///               biometric authentication. Adding this slot is what lets
///               fingerprint unlock work *without* storing the PIN anywhere,
///               which is the flaw it exists to replace.
///
/// Every slot's plaintext is a small record rather than a bare key:
///
/// ```text
///   0  16  keyring id  (random, stable for the life of the vault)
///  16   4  generation  (incremented on every credential change)
///  20  32  master data key
/// ```
///
/// The generation counter provides rollback protection. An attacker with write
/// access to app storage could otherwise restore a previously captured keyring
/// to reinstate a PIN the user has since changed. Callers pin the highest
/// generation they have seen in keystore-backed storage and refuse anything
/// older — see [KeyringPayload.generation].
final class VaultKeyring {
  const VaultKeyring._(this._slots);

  static const int formatVersion = 1;

  /// Slot unlocked by the user's PIN or passphrase.
  static const String pinSlot = 'pin';

  /// Slot unlocked by a biometric-bound key from the platform keystore.
  static const String deviceSlot = 'device';

  static const int _keyringIdLength = 16;
  static const int _generationOffset = 16;
  static const int _masterKeyOffset = 20;
  static const int _masterKeyLength = 32;
  static const int _payloadLength = _masterKeyOffset + _masterKeyLength;

  final Map<String, Uint8List> _slots;

  static SodiumSumo get _sodium => SodiumContext.instance.sodium;

  bool get hasDeviceSlot => _slots.containsKey(deviceSlot);

  Iterable<String> get slotNames => _slots.keys;

  /// The Argon2id cost currently protecting the PIN slot.
  KdfProfile get pinProfile => SecureEnvelope.profileOf(_requireSlot(pinSlot));

  // ------------------------------------------------------------------ create

  /// Builds a brand-new keyring around a freshly generated master key.
  static ({VaultKeyring keyring, KeyHierarchy hierarchy}) create({
    required Uint8List secret,
    KdfProfile profile = KdfProfile.balanced,
  }) {
    final masterKey = KeyHierarchy.generateMasterKey();
    final payload = _buildPayload(
      keyringId: _sodium.randombytes.buf(_keyringIdLength),
      generation: 1,
      masterKey: masterKey,
    );
    try {
      final wrapped = SecureEnvelope.sealWithPassword(
        password: secret,
        plaintext: payload,
        profile: profile,
      );
      return (
        keyring: VaultKeyring._({pinSlot: wrapped}),
        hierarchy: KeyHierarchy(masterKey),
      );
    } finally {
      payload.fillRange(0, payload.length, 0);
    }
  }

  // ------------------------------------------------------------------ unlock

  /// Unwraps the master key using the user's PIN or passphrase.
  ///
  /// Throws [AuthenticationFailure] if the secret is wrong. There is no stored
  /// hash of the secret to check against — the AEAD tag *is* the check, which
  /// is why an attacker who copies the vault gains no fast offline oracle.
  KeyringUnlock unlockWithSecret(Uint8List secret) => _unlock(
    SecureEnvelope.openWithPassword(
      password: secret,
      envelope: _requireSlot(pinSlot),
    ),
  );

  /// Unwraps the master key using the keystore-held device key.
  KeyringUnlock unlockWithDeviceKey(SecureKey deviceKey) => _unlock(
    SecureEnvelope.openWithKey(
      key: deviceKey,
      envelope: _requireSlot(deviceSlot),
    ),
  );

  // ------------------------------------------------------------------ mutate

  /// Re-wraps the master key under a new secret and bumps the generation.
  ///
  /// The vault document itself is untouched: only this small record changes,
  /// so a PIN change is instant regardless of vault size.
  VaultKeyring withChangedSecret({
    required KeyringUnlock unlocked,
    required Uint8List newSecret,
    KdfProfile profile = KdfProfile.balanced,
  }) {
    final next = unlocked.generation + 1;
    final payload = _buildPayload(
      keyringId: unlocked.keyringId,
      generation: next,
      masterKey: unlocked.hierarchy.masterKey,
    );
    try {
      // Re-wrapping under a new secret invalidates the device slot too: the
      // old wrapped copy still holds the previous generation, so it would be
      // rejected as a rollback. Drop it and let the caller re-enrol.
      return VaultKeyring._({
        pinSlot: SecureEnvelope.sealWithPassword(
          password: newSecret,
          plaintext: payload,
          profile: profile,
        ),
      });
    } finally {
      payload.fillRange(0, payload.length, 0);
    }
  }

  /// Adds or replaces the biometric slot without changing the generation.
  VaultKeyring withDeviceSlot({
    required KeyringUnlock unlocked,
    required SecureKey deviceKey,
  }) {
    final payload = _buildPayload(
      keyringId: unlocked.keyringId,
      generation: unlocked.generation,
      masterKey: unlocked.hierarchy.masterKey,
    );
    try {
      return VaultKeyring._({
        ..._slots,
        deviceSlot: SecureEnvelope.sealWithKey(
          key: deviceKey,
          plaintext: payload,
        ),
      });
    } finally {
      payload.fillRange(0, payload.length, 0);
    }
  }

  /// Removes the biometric slot, leaving PIN unlock as the only path.
  VaultKeyring withoutDeviceSlot() =>
      VaultKeyring._({..._slots}..remove(deviceSlot));

  // ------------------------------------------------------------------ codec

  Uint8List encode() {
    final slots = <String, String>{
      for (final entry in _slots.entries) entry.key: base64.encode(entry.value),
    };
    return Uint8List.fromList(
      utf8.encode(json.encode({'v': formatVersion, 'slots': slots})),
    );
  }

  static VaultKeyring decode(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw MalformedEnvelope('Keyring is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const MalformedEnvelope('Keyring root is not an object.');
    }
    if (decoded['v'] != formatVersion) {
      throw UnsupportedEnvelope('Keyring version ${decoded['v']} is unknown.');
    }
    final rawSlots = decoded['slots'];
    if (rawSlots is! Map) {
      throw const MalformedEnvelope('Keyring has no slot table.');
    }
    final slots = <String, Uint8List>{};
    for (final entry in rawSlots.entries) {
      final value = entry.value;
      if (value is! String) {
        throw const MalformedEnvelope('Keyring slot is not a string.');
      }
      try {
        slots[entry.key.toString()] = base64.decode(value);
      } on FormatException {
        throw const MalformedEnvelope('Keyring slot is not valid base64.');
      }
    }
    if (!slots.containsKey(pinSlot)) {
      throw const MalformedEnvelope('Keyring is missing its PIN slot.');
    }
    return VaultKeyring._(slots);
  }

  // --------------------------------------------------------------- internals

  Uint8List _requireSlot(String name) {
    final slot = _slots[name];
    if (slot == null) {
      throw KeyUnavailable('Keyring has no "$name" slot.');
    }
    return slot;
  }

  static KeyringUnlock _unlock(Uint8List payload) {
    try {
      if (payload.length != _payloadLength) {
        throw const MalformedEnvelope('Keyring payload has the wrong size.');
      }
      final masterKey = SecureKey.fromList(
        _sodium,
        Uint8List.sublistView(
          payload,
          _masterKeyOffset,
          _masterKeyOffset + _masterKeyLength,
        ),
      );
      return KeyringUnlock._(
        hierarchy: KeyHierarchy(masterKey),
        keyringId: Uint8List.fromList(
          Uint8List.sublistView(payload, 0, _keyringIdLength),
        ),
        generation: ByteData.sublistView(
          payload,
        ).getUint32(_generationOffset, Endian.little),
      );
    } finally {
      payload.fillRange(0, payload.length, 0);
    }
  }

  static Uint8List _buildPayload({
    required Uint8List keyringId,
    required int generation,
    required SecureKey masterKey,
  }) {
    final payload = Uint8List(_payloadLength);
    payload.setRange(0, _keyringIdLength, keyringId);
    ByteData.sublistView(
      payload,
    ).setUint32(_generationOffset, generation, Endian.little);
    masterKey.runUnlockedSync((bytes) {
      if (bytes.length != _masterKeyLength) {
        throw const MalformedEnvelope('Master key has the wrong size.');
      }
      payload.setRange(_masterKeyOffset, _payloadLength, bytes);
    });
    return payload;
  }
}

/// The result of opening a keyring slot.
final class KeyringUnlock {
  const KeyringUnlock._({
    required this.hierarchy,
    required this.keyringId,
    required this.generation,
  });

  final KeyHierarchy hierarchy;

  /// Stable identifier for this vault, so a keyring from a *different* vault
  /// is recognisable rather than silently accepted.
  final Uint8List keyringId;

  /// Monotonic counter. Callers must reject an unlock whose generation is
  /// lower than the highest they have recorded in keystore-backed storage.
  final int generation;

  void dispose() => hierarchy.dispose();
}
