import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:vaultx/crypto/crypto_errors.dart';
import 'package:vaultx/crypto/media_cipher.dart';
import 'package:vaultx/crypto/sodium_context.dart';

import '_support.dart';

void main() {
  setUpAll(initCrypto);

  late Directory work;
  late SecureKey key;

  setUp(() {
    work = Directory.systemTemp.createTempSync('vaultx_media_test');
    key = SodiumContext.instance.sodium.crypto.secretStream.keygen();
  });

  tearDown(() {
    key.dispose();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  File plainFile(String name, Uint8List bytes) =>
      File('${work.path}/$name')..writeAsBytesSync(bytes);

  Future<Uint8List> roundTrip(Uint8List input, {int? chunkSize}) async {
    final source = plainFile('in.bin', input);
    final encrypted = File('${work.path}/out.vxm');
    await MediaCipher.encryptFile(
      source: source,
      destination: encrypted,
      fileKey: key,
      chunkSize: chunkSize ?? MediaCipher.defaultChunkSize,
    );
    return MediaCipher.decryptToMemory(source: encrypted, fileKey: key);
  }

  test('round-trips a small file', () async {
    final input = filledBytes(1234);
    expect(await roundTrip(input), input);
  });

  test('round-trips an empty file', () async {
    expect(await roundTrip(Uint8List(0)), isEmpty);
  });

  test('round-trips a file spanning many chunks', () async {
    final input = filledBytes(5000);
    expect(await roundTrip(input, chunkSize: 1024), input);
  });

  test('round-trips a file that is an exact multiple of the chunk size',
      () async {
    final input = filledBytes(4096);
    expect(await roundTrip(input, chunkSize: 1024), input);
  });

  test('the ciphertext does not contain the plaintext', () async {
    final input = bytesOf('SUPER SECRET MARKER STRING');
    final source = plainFile('in.bin', input);
    final encrypted = File('${work.path}/out.vxm');
    await MediaCipher.encryptFile(
      source: source,
      destination: encrypted,
      fileKey: key,
    );
    final onDisk = encrypted.readAsBytesSync();
    expect(
      String.fromCharCodes(onDisk).contains('SUPER SECRET MARKER'),
      isFalse,
    );
  });

  test('rejects a wrong key', () async {
    final source = plainFile('in.bin', filledBytes(2000));
    final encrypted = File('${work.path}/out.vxm');
    await MediaCipher.encryptFile(
      source: source,
      destination: encrypted,
      fileKey: key,
    );
    final other = SodiumContext.instance.sodium.crypto.secretStream.keygen();
    addTearDown(other.dispose);
    await expectLater(
      MediaCipher.decryptToMemory(source: encrypted, fileKey: other),
      throwsA(anything),
    );
  });

  test('detects a flipped bit', () async {
    final source = plainFile('in.bin', filledBytes(2000));
    final encrypted = File('${work.path}/out.vxm');
    await MediaCipher.encryptFile(
      source: source,
      destination: encrypted,
      fileKey: key,
    );
    final bytes = encrypted.readAsBytesSync();
    bytes[MediaCipher.headerLength + 40] ^= 0x01;
    encrypted.writeAsBytesSync(bytes);
    await expectLater(
      MediaCipher.decryptToMemory(source: encrypted, fileKey: key),
      throwsA(anything),
    );
  });

  test('detects truncation', () async {
    final source = plainFile('in.bin', filledBytes(5000));
    final encrypted = File('${work.path}/out.vxm');
    await MediaCipher.encryptFile(
      source: source,
      destination: encrypted,
      fileKey: key,
      chunkSize: 1024,
    );
    final bytes = encrypted.readAsBytesSync();
    final aBytes = SodiumContext.instance.sodium.crypto.secretStream.aBytes;
    encrypted.writeAsBytesSync(
      Uint8List.sublistView(bytes, 0, bytes.length - (1024 + aBytes)),
    );
    await expectLater(
      MediaCipher.decryptToMemory(source: encrypted, fileKey: key),
      throwsA(anything),
    );
  });

  test('rejects a file that is not VaultX media', () async {
    final foreign = plainFile('foreign.vxm', filledBytes(500));
    await expectLater(
      MediaCipher.decryptToMemory(source: foreign, fileKey: key),
      throwsA(isA<MalformedEnvelope>()),
    );
  });

  test('rejects an unknown media format version', () async {
    final source = plainFile('in.bin', filledBytes(100));
    final encrypted = File('${work.path}/out.vxm');
    await MediaCipher.encryptFile(
      source: source,
      destination: encrypted,
      fileKey: key,
    );
    final bytes = encrypted.readAsBytesSync();
    bytes[4] = 99;
    encrypted.writeAsBytesSync(bytes);
    await expectLater(
      MediaCipher.decryptToMemory(source: encrypted, fileKey: key),
      throwsA(isA<UnsupportedEnvelope>()),
    );
  });

  test('rejects an out-of-range chunk size in the header', () async {
    final source = plainFile('in.bin', filledBytes(100));
    final encrypted = File('${work.path}/out.vxm');
    await MediaCipher.encryptFile(
      source: source,
      destination: encrypted,
      fileKey: key,
    );
    final bytes = encrypted.readAsBytesSync();
    ByteData.sublistView(bytes).setUint32(8, 0xFFFFFFF, Endian.little);
    encrypted.writeAsBytesSync(bytes);
    await expectLater(
      MediaCipher.decryptToMemory(source: encrypted, fileKey: key),
      throwsA(isA<UnsupportedEnvelope>()),
    );
  });

  test('leaves no partial file behind when the source disappears', () async {
    final missing = File('${work.path}/nope.bin');
    final encrypted = File('${work.path}/out.vxm');
    await expectLater(
      MediaCipher.encryptFile(
        source: missing,
        destination: encrypted,
        fileKey: key,
      ),
      throwsA(anything),
    );
    expect(encrypted.existsSync(), isFalse);
  });
}
