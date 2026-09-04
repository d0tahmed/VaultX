import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small key/value abstraction over the platform keystore.
///
/// Exists so the vault service can be unit-tested without a device, and so the
/// storage backend can be swapped without touching security logic.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Backed by the Android Keystore via `flutter_secure_storage`.
final class PlatformSecureStore implements SecureStore {
  // `encryptedSharedPreferences` was removed in flutter_secure_storage v11:
  // Jetpack Security is deprecated upstream and existing data migrates to the
  // package's own ciphers on first access. Passing it now is a no-op.
  const PlatformSecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory implementation for tests.
final class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}
