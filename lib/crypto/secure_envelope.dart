import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'crypto_errors.dart';
import 'kdf_profile.dart';
import 'sodium_context.dart';

/// Authenticated container used for every secret VaultX writes to disk.
///
/// Layout (little-endian, 56-byte header followed by the AEAD output):
///
/// ```text
///   0   4   magic 'VXE1'
///   4   1   format version
///   5   1   cipher suite  (1 = XChaCha20-Poly1305-IETF)
///   6   1   kdf algorithm (0 = caller-supplied key, 1 = Argon2id13)
///   7   1   flags (reserved, must be 0)
///   8   4   Argon2id opsLimit
///  12   4   Argon2id memLimit (bytes)
///  16  16   Argon2id salt
///  32  24   AEAD nonce
///  56   n   ciphertext || Poly1305 tag
/// ```
///
/// The whole header is passed as additional authenticated data. That is what
/// makes the KDF parameters tamper-evident: an attacker who rewrites opsLimit
/// or memLimit to something cheap invalidates the tag, so the downgraded file
/// simply refuses to open rather than opening faster.
///
/// XChaCha20-Poly1305 is used rather than AES-GCM because its 192-bit nonce is
/// large enough that random nonces never collide in practice. AES-GCM's 96-bit
/// nonce would require a counter and careful state tracking to stay safe, and
/// that state is exactly the kind of thing that breaks during a restore.
final class SecureEnvelope {
  SecureEnvelope._();

  static const int _magic0 = 0x56; // V
  static const int _magic1 = 0x58; // X
  static const int _magic2 = 0x45; // E
  static const int _magic3 = 0x31; // 1

  static const int formatVersion = 1;
  static const int suiteXChaCha20Poly1305 = 1;

  static const int kdfNone = 0;
  static const int kdfArgon2id13 = 1;

  static const int headerLength = 56;
  static const int _saltOffset = 16;
  static const int _saltLength = 16;
  static const int _nonceOffset = 32;
  static const int _nonceLength = 24;

  static SodiumSumo get _sodium => SodiumContext.instance.sodium;

  static Aead get _aead => _sodium.crypto.aeadXChaCha20Poly1305IETF;

  /// Encrypts [plaintext] under a key derived from [password] with Argon2id.
  ///
  /// A fresh random salt and nonce are generated for every call, so encrypting
  /// the same content twice under the same password yields unrelated bytes.
  static Uint8List sealWithPassword({
    required Uint8List password,
    required Uint8List plaintext,
    KdfProfile profile = KdfProfile.balanced,
  }) {
    _assertPrimitiveSizes();
    final salt = _sodium.randombytes.buf(_saltLength);
    final header = _buildHeader(
      kdfAlg: kdfArgon2id13,
      opsLimit: profile.opsLimit,
      memLimit: profile.memLimitBytes,
      salt: salt,
      nonce: _sodium.randombytes.buf(_nonceLength),
    );
    final key = _deriveKey(password: password, salt: salt, profile: profile);
    try {
      return _seal(header: header, plaintext: plaintext, key: key);
    } finally {
      key.dispose();
    }
  }

  /// Decrypts an Argon2id-protected envelope.
  ///
  /// Throws [AuthenticationFailure] when the password is wrong *or* the bytes
  /// were altered — the two are indistinguishable by design.
  static Uint8List openWithPassword({
    required Uint8List password,
    required Uint8List envelope,
  }) {
    _assertPrimitiveSizes();
    final header = _parseHeader(envelope, expectKdf: kdfArgon2id13);
    final profile = KdfProfile.fromStored(
      opsLimit: header.opsLimit,
      memLimitBytes: header.memLimit,
    );
    if (!profile.isAcceptable(_sodium)) {
      throw UnsupportedEnvelope(
        'Refusing to derive a key with weakened parameters ($profile).',
      );
    }
    final key = _deriveKey(
      password: password,
      salt: header.salt,
      profile: profile,
    );
    try {
      return _open(envelope: envelope, key: key);
    } finally {
      key.dispose();
    }
  }

  /// Encrypts [plaintext] under a caller-supplied 32-byte key.
  ///
  /// Used for wrapping the master data key under a key held by the platform
  /// keystore, and for the vault and media subkeys — none of which come from a
  /// password, so no KDF work is recorded in the header.
  static Uint8List sealWithKey({
    required SecureKey key,
    required Uint8List plaintext,
  }) {
    _assertPrimitiveSizes();
    final header = _buildHeader(
      kdfAlg: kdfNone,
      opsLimit: 0,
      memLimit: 0,
      salt: Uint8List(_saltLength),
      nonce: _sodium.randombytes.buf(_nonceLength),
    );
    return _seal(header: header, plaintext: plaintext, key: key);
  }

  /// Decrypts an envelope sealed by [sealWithKey].
  static Uint8List openWithKey({
    required SecureKey key,
    required Uint8List envelope,
  }) {
    _assertPrimitiveSizes();
    _parseHeader(envelope, expectKdf: kdfNone);
    return _open(envelope: envelope, key: key);
  }

  /// Reports the Argon2id profile recorded in a password envelope, without
  /// doing any key derivation. Used to decide whether to re-wrap on unlock.
  static KdfProfile profileOf(Uint8List envelope) {
    final header = _parseHeader(envelope, expectKdf: kdfArgon2id13);
    return KdfProfile.fromStored(
      opsLimit: header.opsLimit,
      memLimitBytes: header.memLimit,
    );
  }

  // ---------------------------------------------------------------- internals

  static Uint8List _seal({
    required Uint8List header,
    required Uint8List plaintext,
    required SecureKey key,
  }) {
    final nonce = Uint8List.sublistView(
      header,
      _nonceOffset,
      _nonceOffset + _nonceLength,
    );
    final cipherText = _aead.encrypt(
      message: plaintext,
      nonce: nonce,
      key: key,
      additionalData: header,
    );
    final out = Uint8List(header.length + cipherText.length);
    out.setRange(0, header.length, header);
    out.setRange(header.length, out.length, cipherText);
    return out;
  }

  static Uint8List _open({
    required Uint8List envelope,
    required SecureKey key,
  }) {
    final header = Uint8List.sublistView(envelope, 0, headerLength);
    final nonce = Uint8List.sublistView(
      envelope,
      _nonceOffset,
      _nonceOffset + _nonceLength,
    );
    final cipherText = Uint8List.sublistView(envelope, headerLength);
    try {
      return _aead.decrypt(
        cipherText: cipherText,
        nonce: nonce,
        key: key,
        additionalData: header,
      );
    } on SodiumException {
      throw const AuthenticationFailure();
    }
  }

  static SecureKey _deriveKey({
    required Uint8List password,
    required Uint8List salt,
    required KdfProfile profile,
  }) {
    // Views the caller's buffer rather than copying, so the secret is not
    // duplicated into another heap allocation we would then have to scrub.
    final signed = Int8List.view(
      password.buffer,
      password.offsetInBytes,
      password.length,
    );
    return _sodium.crypto.pwhash.callRaw(
      outLen: _aead.keyBytes,
      password: signed,
      salt: salt,
      opsLimit: profile.opsLimit,
      memLimit: profile.memLimitBytes,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  }

  static Uint8List _buildHeader({
    required int kdfAlg,
    required int opsLimit,
    required int memLimit,
    required Uint8List salt,
    required Uint8List nonce,
  }) {
    final header = Uint8List(headerLength);
    header[0] = _magic0;
    header[1] = _magic1;
    header[2] = _magic2;
    header[3] = _magic3;
    header[4] = formatVersion;
    header[5] = suiteXChaCha20Poly1305;
    header[6] = kdfAlg;
    header[7] = 0; // flags
    final view = ByteData.sublistView(header);
    view.setUint32(8, opsLimit, Endian.little);
    view.setUint32(12, memLimit, Endian.little);
    header.setRange(_saltOffset, _saltOffset + _saltLength, salt);
    header.setRange(_nonceOffset, _nonceOffset + _nonceLength, nonce);
    return header;
  }

  static _Header _parseHeader(Uint8List envelope, {required int expectKdf}) {
    if (envelope.length < headerLength + _aead.aBytes) {
      throw const MalformedEnvelope('Envelope is truncated.');
    }
    if (envelope[0] != _magic0 ||
        envelope[1] != _magic1 ||
        envelope[2] != _magic2 ||
        envelope[3] != _magic3) {
      throw const MalformedEnvelope('Not a VaultX envelope.');
    }
    if (envelope[4] != formatVersion) {
      throw UnsupportedEnvelope('Envelope format v${envelope[4]} is unknown.');
    }
    if (envelope[5] != suiteXChaCha20Poly1305) {
      throw UnsupportedEnvelope('Cipher suite ${envelope[5]} is unknown.');
    }
    if (envelope[6] != expectKdf) {
      throw UnsupportedEnvelope(
        'Envelope uses key-derivation mode ${envelope[6]}, expected $expectKdf.',
      );
    }
    if (envelope[7] != 0) {
      throw const UnsupportedEnvelope('Unknown envelope flags set.');
    }
    final view = ByteData.sublistView(envelope);
    return _Header(
      opsLimit: view.getUint32(8, Endian.little),
      memLimit: view.getUint32(12, Endian.little),
      salt: Uint8List.sublistView(
        envelope,
        _saltOffset,
        _saltOffset + _saltLength,
      ),
    );
  }

  /// Guards against a libsodium build whose constants differ from the ones this
  /// layout hard-codes. Cheap, and turns a silent corruption into a loud error.
  static void _assertPrimitiveSizes() {
    if (_aead.nonceBytes != _nonceLength ||
        _aead.keyBytes != 32 ||
        _sodium.crypto.pwhash.saltBytes != _saltLength) {
      throw const UnsupportedEnvelope(
        'libsodium primitive sizes do not match the envelope layout.',
      );
    }
  }
}

final class _Header {
  const _Header({
    required this.opsLimit,
    required this.memLimit,
    required this.salt,
  });

  final int opsLimit;
  final int memLimit;
  final Uint8List salt;
}
