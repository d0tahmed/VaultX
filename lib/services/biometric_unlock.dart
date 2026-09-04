import 'device_key_store.dart';
import 'secure_store.dart';
import 'vault_crypto_service.dart';

/// Ties the hardware-backed device key to the vault's keyring.
///
/// Enrolling stores only the wrapped key. Unlocking recovers it behind a
/// biometric prompt and hands it to the keyring, which unwraps the master key.
/// At no point is the user's PIN written anywhere — the flaw this replaces.
final class BiometricUnlock {
  const BiometricUnlock({
    required this.service,
    required this.store,
    this.deviceKeys = const DeviceKeyStore(),
  });

  final VaultCryptoService service;
  final SecureStore store;
  final DeviceKeyStore deviceKeys;

  static const _wrappedKey = 'vaultx.device.wrapped';
  static const _ivKey = 'vaultx.device.iv';

  Future<bool> isAvailable() async =>
      await deviceKeys.isSupported() && await _hasStoredBlob();

  Future<bool> canEnrol() => deviceKeys.isSupported();

  /// Enables biometric unlock for an already-unlocked vault.
  Future<void> enrol(VaultSession session) async {
    final enrolment = await deviceKeys.enrol();
    try {
      await service.enrolDeviceKey(
        session: session,
        deviceKey: enrolment.deviceKey,
      );
      await store.write(_wrappedKey, enrolment.wrapped);
      await store.write(_ivKey, enrolment.iv);
    } finally {
      enrolment.deviceKey.dispose();
    }
  }

  /// Unlocks the vault using biometrics.
  ///
  /// Throws [BiometricEnrolmentChanged] if fingerprints changed since enrolment
  /// — callers should fall back to the PIN and offer to re-enrol.
  Future<VaultSession> unlock() async {
    final wrapped = await store.read(_wrappedKey);
    final iv = await store.read(_ivKey);
    if (wrapped == null || iv == null) {
      throw const BiometricUnavailable('Biometric unlock is not set up.');
    }
    final deviceKey = await deviceKeys.unwrap(wrapped: wrapped, iv: iv);
    try {
      return await service.unlockWithDeviceKey(deviceKey);
    } finally {
      deviceKey.dispose();
    }
  }

  /// Turns biometric unlock off and removes every trace of it.
  Future<void> revoke() async {
    await service.revokeDeviceKey();
    await deviceKeys.destroy();
    await store.delete(_wrappedKey);
    await store.delete(_ivKey);
  }

  Future<bool> _hasStoredBlob() async =>
      await store.read(_wrappedKey) != null && await store.read(_ivKey) != null;
}
