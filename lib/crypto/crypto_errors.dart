/// Typed failures raised by the VaultX cryptography layer.
///
/// These deliberately do NOT distinguish "wrong secret" from "corrupted
/// ciphertext": both surface as [AuthenticationFailure]. An AEAD tag check
/// cannot tell the two apart, and pretending otherwise would either leak
/// information to an attacker or lie to the user.
sealed class CryptoFailure implements Exception {
  const CryptoFailure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The authentication tag did not verify.
///
/// Either the supplied secret was wrong, or the ciphertext was altered.
/// Callers must treat both cases identically.
final class AuthenticationFailure extends CryptoFailure {
  const AuthenticationFailure([
    super.message = 'Authentication failed: wrong secret or altered data.',
  ]);
}

/// The stored blob is not a VaultX envelope, or is truncated.
final class MalformedEnvelope extends CryptoFailure {
  const MalformedEnvelope(super.message);
}

/// The envelope was written by a newer/unknown format or cipher suite.
final class UnsupportedEnvelope extends CryptoFailure {
  const UnsupportedEnvelope(super.message);
}

/// A key needed for this operation is not currently held in memory.
final class KeyUnavailable extends CryptoFailure {
  const KeyUnavailable([super.message = 'Vault is locked.']);
}
