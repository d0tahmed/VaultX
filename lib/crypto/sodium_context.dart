import 'package:sodium/sodium_sumo.dart';

/// Process-wide libsodium handle.
///
/// The sumo variant is required: `crypto_pwhash` (Argon2id) is not present in
/// libsodium's minimal build. [ensureInitialised] is idempotent and cheap after
/// the first call, so call sites need not coordinate.
final class SodiumContext {
  SodiumContext._(this.sodium);

  static SodiumContext? _instance;

  final SodiumSumo sodium;

  static bool get isInitialised => _instance != null;

  /// Initialises libsodium if needed and returns the shared context.
  ///
  /// Safe to call concurrently: the in-flight future is cached, so racing
  /// callers share one initialisation rather than each building their own.
  static Future<SodiumContext> ensureInitialised() async {
    final held = _instance;
    if (held != null) return held;
    return _pending ??= _initialise();
  }

  static Future<SodiumContext>? _pending;

  static Future<SodiumContext> _initialise() async {
    try {
      final sodium = await SodiumSumoInit.init();
      return _instance = SodiumContext._(sodium);
    } finally {
      _pending = null;
    }
  }

  static SodiumContext get instance {
    final held = _instance;
    if (held == null) {
      throw StateError(
        'SodiumContext.ensureInitialised() must run before any crypto call.',
      );
    }
    return held;
  }
}
