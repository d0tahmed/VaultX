import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'sodium_context.dart';

/// Derives every working key from a single master data key (MDK).
///
/// The MDK is random, 256-bit, and generated once when the vault is created.
/// It is never derived from the user's secret — the secret only ever unwraps
/// it. That indirection is what makes changing a PIN a single re-wrap instead
/// of a full re-encryption of the vault, and it lets biometric unlock hold its
/// own wrapped copy without ever learning the PIN.
///
/// Subkeys come from `crypto_kdf` (keyed BLAKE2b). Compromise of one subkey
/// does not expose its siblings or the MDK.
final class KeyHierarchy {
  KeyHierarchy(this._masterKey);

  /// libsodium requires exactly 8 bytes of context.
  static const String _context = 'VaultX_1';

  static const int _vaultDataSubkey = 1;
  static const int _mediaMasterSubkey = 2;
  static const int _auditSubkey = 3;
  static const int _searchIndexSubkey = 4;

  final SecureKey _masterKey;

  static SodiumSumo get _sodium => SodiumContext.instance.sodium;

  /// The raw master key. Callers must not persist this unwrapped.
  SecureKey get masterKey => _masterKey;

  /// Protects the encrypted password/vault document.
  SecureKey deriveVaultDataKey() => _derive(_vaultDataSubkey);

  /// Root for per-file media keys. Prefer [deriveMediaFileKey].
  SecureKey deriveMediaMasterKey() => _derive(_mediaMasterSubkey);

  /// Protects the tamper-evident audit log.
  SecureKey deriveAuditKey() => _derive(_auditSubkey);

  /// Protects the search index, which leaks structure if stored in the clear.
  SecureKey deriveSearchIndexKey() => _derive(_searchIndexSubkey);

  /// Returns a key unique to one media file.
  ///
  /// Computed as a keyed BLAKE2b of the file's identifier under the media
  /// master key, so every file gets an independent key with nothing extra to
  /// store, and recovering one file's key reveals nothing about any other.
  SecureKey deriveMediaFileKey(String fileId) {
    final mediaMaster = deriveMediaMasterKey();
    Uint8List? digest;
    try {
      digest = _sodium.crypto.genericHash(
        message: Uint8List.fromList(utf8.encode(fileId)),
        key: mediaMaster,
        outLen: _sodium.crypto.secretStream.keyBytes,
      );
      return SecureKey.fromList(_sodium, digest);
    } finally {
      // The digest is key material sitting in an ordinary heap buffer; scrub it
      // once SecureKey holds its own locked copy.
      if (digest != null) digest.fillRange(0, digest.length, 0);
      mediaMaster.dispose();
    }
  }

  SecureKey _derive(int subkeyId) => _sodium.crypto.kdf.deriveFromKey(
    masterKey: _masterKey,
    context: _context,
    subkeyId: BigInt.from(subkeyId),
    subkeyLen: _sodium.crypto.kdf.bytesMax >= 32 ? 32 : _sodium.crypto.kdf.bytesMax,
  );

  /// Generates a fresh random master key for a brand-new vault.
  static SecureKey generateMasterKey() => _sodium.crypto.kdf.keygen();

  /// Wipes the master key from locked memory.
  void dispose() => _masterKey.dispose();
}
