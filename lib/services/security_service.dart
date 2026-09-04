import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SUPERSEDED IN v4 — DO NOT WIRE NEW CODE TO THIS FILE.
//
// Replaced by lib/services/vault_crypto_service.dart, lib/crypto/vault_keyring.dart
// and lib/services/device_key_store.dart. It remains only because the v3 screens
// still import it, and is deleted once those screens are rebuilt.
//
// Known flaws, all fixed in the v4 replacements:
//   * _hashPin is ONE round of SHA-256 over a salt hard-coded in public source,
//     so the 10^6 possible 6-digit PINs are exhaustible in milliseconds.
//     v4 stores no PIN verifier at all — the AEAD tag is the check.
//   * _sessionPinKey stores the RAW PIN so biometrics can re-derive the key,
//     which made "the key is never persisted" untrue. v4 wraps the master key
//     under a keystore key that requires a live biometric and never sees the PIN.
//   * The 8-failure poison pill calls _storage.deleteAll(), which drops the
//     keystore entries but leaves the encrypted vault and the unencrypted media
//     on disk. v4 shreds the keyring first, then every artefact.
// ─────────────────────────────────────────────────────────────────────────────

class VaultDestroyedException implements Exception {}

class SecurityService {
  // `encryptedSharedPreferences` was removed in flutter_secure_storage v11 and
  // is ignored when passed; existing data migrates to the package's own ciphers.
  final _storage = const FlutterSecureStorage();

  static const _pinKey         = 'user_master_pin';
  static const _mediaPinKey    = 'user_media_pin'; 
  static const _failCountKey   = 'auth_fail_count';
  static const _lockoutTimeKey = 'auth_lockout_timestamp';
  // NOTE: sessionPin stores the raw PIN in Android Keystore (hardware-backed).
  // This is intentional — biometric auth has no way to return the PIN, so we
  // store it here to derive the AES vault key after biometric succeeds.
  // The Keystore protects it at hardware level. NEVER log or print this value.
  static const _sessionPinKey  = 'vault_session_pin';

  String _hashPin(String pin) {
    final bytes = utf8.encode('vaultx_salt_2024_$pin');
    return sha256.convert(bytes).toString();
  }

  Future<void> savePin(String pin) async {
    final hash = _hashPin(pin);
    await _storage.write(key: _pinKey,        value: hash); 
    await _storage.write(key: _sessionPinKey, value: pin);  
    await _storage.write(key: _failCountKey,  value: '0');
    await _storage.delete(key: _lockoutTimeKey);
  }

  Future<String?> getSessionPin() async {
    return await _storage.read(key: _sessionPinKey);
  }

  Future<bool> hasPinSet() async {
    final pin = await _storage.read(key: _pinKey);
    return pin != null;
  }

  Future<int> getRemainingLockoutSeconds() async {
    final lockoutStr = await _storage.read(key: _lockoutTimeKey);
    if (lockoutStr == null) return 0;
    final lockoutTime = DateTime.tryParse(lockoutStr);
    if (lockoutTime == null) return 0;
    final remaining = lockoutTime.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  Future<void> _handleFailedAttempt() async {
    final currentFailsStr = await _storage.read(key: _failCountKey);
    // Use tryParse — int.parse throws FormatException on corrupted Keystore values
    final currentFails = (int.tryParse(currentFailsStr ?? '0') ?? 0) + 1;

    if (currentFails >= 8) {
      await _storage.deleteAll();
      throw VaultDestroyedException();
    }

    await _storage.write(key: _failCountKey, value: currentFails.toString());

    if (currentFails >= 5) {
      final waitTime = 30 * (currentFails - 4);
      final unlockAt = DateTime.now().add(Duration(seconds: waitTime));
      await _storage.write(key: _lockoutTimeKey, value: unlockAt.toIso8601String());
    }
  }

  Future<bool> verifyPin(String inputPin) async {
    if (await getRemainingLockoutSeconds() > 0) return false;
    final storedHash = await _storage.read(key: _pinKey);
    if (storedHash == null) return false;

    if (storedHash == _hashPin(inputPin)) {
      await _storage.write(key: _failCountKey, value: '0');
      await _storage.delete(key: _lockoutTimeKey);
      return true;
    } else {
      await _handleFailedAttempt();
      return false;
    }
  }

  Future<void> saveMediaPin(String pin) async {
    await _storage.write(key: _mediaPinKey, value: _hashPin(pin));
  }

  Future<bool> hasMediaPinSet() async {
    final pin = await _storage.read(key: _mediaPinKey);
    return pin != null;
  }

  Future<bool> verifyMediaPin(String inputPin) async {
    if (await getRemainingLockoutSeconds() > 0) return false;
    final storedHash = await _storage.read(key: _mediaPinKey);
    if (storedHash == null) return false;

    if (storedHash == _hashPin(inputPin)) {
      await _storage.write(key: _failCountKey, value: '0');
      await _storage.delete(key: _lockoutTimeKey);
      return true;
    } else {
      await _handleFailedAttempt();
      return false;
    }
  }

  Future<void> clearMediaPin() async {
    await _storage.delete(key: _mediaPinKey);
  }

  Future<void> resetAll() async {
    await _storage.deleteAll();
  }
}