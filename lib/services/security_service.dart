import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

class SecurityService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _pinKey         = 'user_master_pin';
  static const _failCountKey   = 'auth_fail_count';
  static const _lockoutTimeKey = 'auth_lockout_timestamp';
  static const _sessionPinKey  = 'vault_session_pin'; // plain PIN for AES key derivation

  // ── Private helper: hash a PIN the same way every time ───────────────────
  String _hashPin(String pin) {
    final bytes = utf8.encode('vaultx_salt_2024_$pin');
    return sha256.convert(bytes).toString();
  }

  // ── Save PIN ──────────────────────────────────────────────────────────────
  // Stores the HASH for verification + the plain PIN for AES key derivation.
  // Both live in Android Keystore — hardware-backed, same security level.
  Future<void> savePin(String pin) async {
    final hash = _hashPin(pin);
    await _storage.write(key: _pinKey,        value: hash); // hash for verify
    await _storage.write(key: _sessionPinKey, value: pin);  // plain for AES key
    await _storage.write(key: _failCountKey,  value: '0');
    await _storage.delete(key: _lockoutTimeKey);
  }

  // ── Session PIN: returned to VaultProvider to derive the AES vault key ────
  // Called by lock_screen.dart after biometric succeeds (biometric has no PIN)
  Future<String?> getSessionPin() async {
    return await _storage.read(key: _sessionPinKey);
  }

  // ── Check if PIN has been set ─────────────────────────────────────────────
  Future<bool> hasPinSet() async {
    final pin = await _storage.read(key: _pinKey);
    return pin != null;
  }

  // ── Lockout: how many seconds remain ─────────────────────────────────────
  Future<int> getRemainingLockoutSeconds() async {
    final lockoutStr = await _storage.read(key: _lockoutTimeKey);
    if (lockoutStr == null) return 0;
    final lockoutTime = DateTime.tryParse(lockoutStr);
    if (lockoutTime == null) return 0;
    final remaining = lockoutTime.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  // ── Verify PIN ────────────────────────────────────────────────────────────
  Future<bool> verifyPin(String inputPin) async {
    if (await getRemainingLockoutSeconds() > 0) return false;

    final storedHash = await _storage.read(key: _pinKey);
    if (storedHash == null) return false;

    final inputHash = _hashPin(inputPin);

    if (storedHash == inputHash) {
      await _storage.write(key: _failCountKey, value: '0');
      await _storage.delete(key: _lockoutTimeKey);
      return true;
    } else {
      final currentFailsStr = await _storage.read(key: _failCountKey);
      final currentFails = int.parse(currentFailsStr ?? '0') + 1;
      await _storage.write(key: _failCountKey, value: currentFails.toString());

      if (currentFails >= 5) {
        final waitTime = 30 * (currentFails - 4);
        final unlockAt = DateTime.now().add(Duration(seconds: waitTime));
        await _storage.write(key: _lockoutTimeKey, value: unlockAt.toIso8601String());
      }
      return false;
    }
  }
}