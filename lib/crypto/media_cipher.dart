import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'crypto_errors.dart';
import 'sodium_context.dart';

/// Encrypts media files with libsodium's `secretstream` construction.
///
/// This replaces v3's approach of copying the original file into a private
/// directory under a random name. A random filename plus `.nomedia` is
/// obscurity, not encryption: anything with read access to app storage — a
/// root shell, an ADB backup, a forensic image — recovered the originals
/// intact. These files are ciphertext.
///
/// `secretstream` is used rather than a single AEAD call because media files
/// are large. It encrypts a sequence of chunks under one key while binding
/// them into an ordered stream, so the file never has to be held in memory in
/// full, and reordering, splicing or truncating chunks is detected. A plain
/// per-chunk AEAD would authenticate each chunk individually but happily
/// accept them shuffled.
///
/// File layout:
///
/// ```text
///   0   4  magic 'VXM1'
///   4   1  format version
///   5   3  reserved (must be 0)
///   8   4  plaintext chunk size, uint32 little-endian
///  12   n  secretstream header followed by the encrypted chunks
/// ```
///
/// The chunk size is recorded so files stay readable if the default changes.
/// It sits outside the authenticated stream, but altering it makes the stream
/// fail to parse rather than decrypt wrongly.
final class MediaCipher {
  MediaCipher._();

  static const int _magic0 = 0x56; // V
  static const int _magic1 = 0x58; // X
  static const int _magic2 = 0x4D; // M
  static const int _magic3 = 0x31; // 1

  static const int formatVersion = 1;
  static const int headerLength = 12;

  /// 64 KiB of plaintext per chunk: large enough that per-chunk overhead is
  /// negligible, small enough to stream comfortably on a phone.
  static const int defaultChunkSize = 64 * 1024;

  static SodiumSumo get _sodium => SodiumContext.instance.sodium;

  /// Encrypts [source] into [destination].
  ///
  /// On any failure the partial destination file is removed, so a interrupted
  /// import cannot leave a half-written file that later fails to open.
  static Future<void> encryptFile({
    required File source,
    required File destination,
    required SecureKey fileKey,
    int chunkSize = defaultChunkSize,
  }) async {
    final sink = destination.openWrite();
    try {
      sink.add(_buildHeader(chunkSize));
      await sink.addStream(
        _sodium.crypto.secretStream.pushChunked(
          messageStream: source.openRead(),
          key: fileKey,
          chunkSize: chunkSize,
        ),
      );
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // Already failing; the close error is not the interesting one.
      }
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  /// Streams the decrypted contents of [source].
  ///
  /// The stream fails rather than yielding partial output if the file has been
  /// altered or truncated.
  static Stream<List<int>> openRead({
    required File source,
    required SecureKey fileKey,
  }) async* {
    final chunkSize = await _readChunkSize(source);
    yield* _sodium.crypto.secretStream.pullChunked(
      cipherStream: source.openRead(headerLength),
      key: fileKey,
      chunkSize: chunkSize,
    );
  }

  /// Decrypts [source] fully into memory.
  ///
  /// Intended for images and thumbnails shown in-app. Large videos should be
  /// streamed with [openRead] instead of buffered.
  static Future<Uint8List> decryptToMemory({
    required File source,
    required SecureKey fileKey,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in openRead(source: source, fileKey: fileKey)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Future<int> _readChunkSize(File source) async {
    final header = await _readExactly(source, headerLength);
    if (header.length < headerLength) {
      throw const MalformedEnvelope('Media file is truncated.');
    }
    if (header[0] != _magic0 ||
        header[1] != _magic1 ||
        header[2] != _magic2 ||
        header[3] != _magic3) {
      throw const MalformedEnvelope('Not a VaultX media file.');
    }
    if (header[4] != formatVersion) {
      throw UnsupportedEnvelope('Media format v${header[4]} is unknown.');
    }
    if (header[5] != 0 || header[6] != 0 || header[7] != 0) {
      throw const UnsupportedEnvelope('Unknown media header flags set.');
    }
    final chunkSize = ByteData.sublistView(header).getUint32(8, Endian.little);
    // A hostile or corrupt header must not be able to drive a huge allocation.
    if (chunkSize < 1024 || chunkSize > 8 * 1024 * 1024) {
      throw const UnsupportedEnvelope('Media chunk size is out of range.');
    }
    return chunkSize;
  }

  static Future<Uint8List> _readExactly(File source, int count) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.openRead(0, count)) {
      builder.add(chunk);
      if (builder.length >= count) break;
    }
    return builder.takeBytes();
  }

  static Uint8List _buildHeader(int chunkSize) {
    final header = Uint8List(headerLength);
    header[0] = _magic0;
    header[1] = _magic1;
    header[2] = _magic2;
    header[3] = _magic3;
    header[4] = formatVersion;
    ByteData.sublistView(header).setUint32(8, chunkSize, Endian.little);
    return header;
  }
}
