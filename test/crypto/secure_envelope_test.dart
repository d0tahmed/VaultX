import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultx/crypto/crypto_errors.dart';
import 'package:vaultx/crypto/kdf_profile.dart';
import 'package:vaultx/crypto/secure_envelope.dart';
import 'package:vaultx/crypto/sodium_context.dart';

import '_support.dart';

void main() {
  setUpAll(initCrypto);

  const profile = KdfProfile.interactive;

  group('password envelopes', () {
    test('round-trips the plaintext', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('open sesame'),
        plaintext: bytesOf('the vault document'),
        profile: profile,
      );
      final opened = SecureEnvelope.openWithPassword(
        password: secretOf('open sesame'),
        envelope: sealed,
      );
      expect(opened, bytesOf('the vault document'));
    });

    test('rejects the wrong password', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('123456'),
        plaintext: bytesOf('secret'),
        profile: profile,
      );
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('123457'),
          envelope: sealed,
        ),
        throwsA(isA<AuthenticationFailure>()),
      );
    });

    test('sealing the same input twice produces unrelated bytes', () {
      final a = SecureEnvelope.sealWithPassword(
        password: secretOf('same'),
        plaintext: bytesOf('same'),
        profile: profile,
      );
      final b = SecureEnvelope.sealWithPassword(
        password: secretOf('same'),
        plaintext: bytesOf('same'),
        profile: profile,
      );
      expect(a, isNot(equals(b)));
    });

    test('detects a flipped bit in the ciphertext', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('payload'),
        profile: profile,
      );
      sealed[SecureEnvelope.headerLength] ^= 0x01;
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: sealed,
        ),
        throwsA(isA<AuthenticationFailure>()),
      );
    });

    test('detects a flipped bit in the nonce', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('payload'),
        profile: profile,
      );
      sealed[32] ^= 0x01;
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: sealed,
        ),
        throwsA(isA<AuthenticationFailure>()),
      );
    });
  });

  group('KDF downgrade resistance', () {
    test('rewriting cost down to another valid profile breaks the tag', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('payload'),
        profile: KdfProfile.balanced,
      );
      // Rewrite ops/mem to the cheaper-but-still-permitted profile.
      final view = ByteData.sublistView(sealed);
      view.setUint32(8, KdfProfile.interactive.opsLimit, Endian.little);
      view.setUint32(12, KdfProfile.interactive.memLimitBytes, Endian.little);
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: sealed,
        ),
        throwsA(isA<AuthenticationFailure>()),
      );
    });

    test('rewriting cost below the floor is refused outright', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('payload'),
        profile: profile,
      );
      final view = ByteData.sublistView(sealed);
      view.setUint32(8, 1, Endian.little);
      view.setUint32(12, 8192, Endian.little);
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: sealed,
        ),
        throwsA(isA<UnsupportedEnvelope>()),
      );
    });

    test('the recorded profile is readable without deriving a key', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('x'),
        profile: KdfProfile.interactive,
      );
      final recorded = SecureEnvelope.profileOf(sealed);
      expect(recorded.opsLimit, KdfProfile.interactive.opsLimit);
      expect(recorded.memLimitBytes, KdfProfile.interactive.memLimitBytes);
    });
  });

  group('raw-key envelopes', () {
    test('round-trip', () {
      final key = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(key.dispose);
      final sealed = SecureEnvelope.sealWithKey(
        key: key,
        plaintext: bytesOf('wrapped key material'),
      );
      expect(
        SecureEnvelope.openWithKey(key: key, envelope: sealed),
        bytesOf('wrapped key material'),
      );
    });

    test('a password envelope cannot be opened as a raw-key envelope', () {
      final key = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(key.dispose);
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('x'),
        profile: profile,
      );
      expect(
        () => SecureEnvelope.openWithKey(key: key, envelope: sealed),
        throwsA(isA<UnsupportedEnvelope>()),
      );
    });
  });

  group('malformed input', () {
    test('rejects a truncated envelope', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('payload'),
        profile: profile,
      );
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: Uint8List.sublistView(sealed, 0, 40),
        ),
        throwsA(isA<MalformedEnvelope>()),
      );
    });

    test('rejects foreign bytes', () {
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: filledBytes(200),
        ),
        throwsA(isA<MalformedEnvelope>()),
      );
    });

    test('rejects an unknown format version', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('x'),
        profile: profile,
      );
      sealed[4] = 99;
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: sealed,
        ),
        throwsA(isA<UnsupportedEnvelope>()),
      );
    });

    test('rejects unknown flag bits', () {
      final sealed = SecureEnvelope.sealWithPassword(
        password: secretOf('pw'),
        plaintext: bytesOf('x'),
        profile: profile,
      );
      sealed[7] = 1;
      expect(
        () => SecureEnvelope.openWithPassword(
          password: secretOf('pw'),
          envelope: sealed,
        ),
        throwsA(isA<UnsupportedEnvelope>()),
      );
    });
  });
}
