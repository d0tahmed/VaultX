import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/sodium_context.dart';

/// Something went wrong reaching the hardware-backed key.
sealed class DeviceKeyFailure implements Exception {
  const DeviceKeyFailure(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

/// The user dismissed the biometric prompt.
final class BiometricCancelled extends DeviceKeyFailure {
  const BiometricCancelled([super.message = 'Authentication was cancelled.']);
}

/// Too many failed biometric attempts; the sensor is temporarily disabled.
final class BiometricLockedOut extends DeviceKeyFailure {
  const BiometricLockedOut([super.message = 'Biometrics are locked out.']);
}

/// Fingerprints were added or removed, so the keystore key was destroyed.
///
/// The wrapped device key is permanently unrecoverable. The app must fall back
/// to the PIN and re-enrol. This is a security property, not a bug: it stops
/// someone who enrols their own fingerprint from inheriting vault access.
final class BiometricEnrolmentChanged extends DeviceKeyFailure {
  const BiometricEnrolmentChanged([
    super.message = 'Biometric enrolment changed; unlock with your PIN.',
  ]);
}

/// No usable biometric hardware, or nothing enrolled yet.
final class BiometricUnavailable extends DeviceKeyFailure {
  const BiometricUnavailable([super.message = 'Biometric unlock is unavailable.']);
}

/// The freshly generated device key plus the blob to persist.
final class DeviceEnrolment {
  const DeviceEnrolment({
    required this.deviceKey,
    required this.wrapped,
    required this.iv,
  });

  /// Raw key material. Add it to the vault keyring, then dispose it.
  final SecureKey deviceKey;

  /// Keystore-encrypted copy, safe to store. Useless without a live biometric.
  final String wrapped;
  final String iv;
}

/// Dart side of [DeviceKeyChannel].
///
/// Every operation here goes through a `BiometricPrompt` bound to the keystore
/// cipher, so authentication is enforced by the platform rather than by a
/// boolean this code could be patched to ignore.
final class DeviceKeyStore {
  const DeviceKeyStore([
    this._channel = const MethodChannel('vaultx/device_key'),
  ]);

  final MethodChannel _channel;

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> hasEnrolledKey() async {
    try {
      return await _channel.invokeMethod<bool>('hasKey') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Prompts for biometrics, then creates and wraps a new device key.
  Future<DeviceEnrolment> enrol() async {
    final result = await _invoke('enrol');
    return DeviceEnrolment(
      deviceKey: _toSecureKey(result['deviceKey']! as String),
      wrapped: result['wrapped']! as String,
      iv: result['iv']! as String,
    );
  }

  /// Prompts for biometrics, then recovers the device key.
  Future<SecureKey> unwrap({
    required String wrapped,
    required String iv,
  }) async {
    final result = await _invoke('unwrap', {'wrapped': wrapped, 'iv': iv});
    return _toSecureKey(result['deviceKey']! as String);
  }

  /// Destroys the keystore key, permanently disabling biometric unlock.
  Future<void> destroy() async {
    try {
      await _channel.invokeMethod<bool>('destroy');
    } on PlatformException {
      // Already gone, which is the intended end state.
    } on MissingPluginException {
      // Nothing to destroy off-device.
    }
  }

  Future<Map<String, Object?>> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result =
          await _channel.invokeMapMethod<String, Object?>(method, arguments);
      if (result == null) {
        throw const BiometricUnavailable('The platform returned no result.');
      }
      return result;
    } on MissingPluginException {
      throw const BiometricUnavailable(
        'Biometric unlock is not available on this platform.',
      );
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'cancelled' => const BiometricCancelled(),
        'lockout' => const BiometricLockedOut(),
        'key_invalidated' => const BiometricEnrolmentChanged(),
        'unsupported' || 'no_key' => const BiometricUnavailable(),
        _ => BiometricUnavailable(e.message ?? e.code),
      };
    }
  }

  static SecureKey _toSecureKey(String encoded) {
    final bytes = base64.decode(encoded);
    try {
      return SecureKey.fromList(SodiumContext.instance.sodium, bytes);
    } finally {
      // Scrub the transient plain copy once SecureKey holds locked memory.
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Exposed for tests that need to build a key from known bytes.
  static SecureKey secureKeyOf(Uint8List bytes) =>
      SecureKey.fromList(SodiumContext.instance.sodium, bytes);
}
