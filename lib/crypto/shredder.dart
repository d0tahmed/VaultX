import 'dart:io';
import 'dart:typed_data';

import 'sodium_context.dart';

/// Best-effort destruction of files on disk.
///
/// An honest caveat, because this is widely overstated: on the flash storage
/// every Android phone uses, overwriting a file does **not** reliably erase the
/// underlying blocks. Wear levelling means the controller usually writes the
/// new bytes somewhere else entirely and leaves the originals readable to
/// anyone who can address the raw NAND.
///
/// So overwriting is defence in depth, not the guarantee. The real guarantee is
/// cryptographic: destroy the keyring and every remaining byte of vault and
/// media data is unopenable ciphertext. Callers must therefore shred the
/// keyring FIRST, so that a wipe interrupted half-way still leaves nothing
/// recoverable.
final class Shredder {
  Shredder._();

  static const int _overwriteBlock = 64 * 1024;

  /// Overwrites [file] with random bytes, truncates it, then unlinks it.
  ///
  /// Missing files are not an error: the goal state is "gone".
  static Future<void> shredFile(File file, {int passes = 1}) async {
    if (!await file.exists()) return;
    try {
      final length = await file.length();
      if (length > 0) {
        final handle = await file.open(mode: FileMode.writeOnlyAppend);
        try {
          for (var pass = 0; pass < passes; pass++) {
            await handle.setPosition(0);
            var written = 0;
            while (written < length) {
              final size = (length - written) < _overwriteBlock
                  ? length - written
                  : _overwriteBlock;
              await handle.writeFrom(_randomBlock(size));
              written += size;
            }
            await handle.flush();
          }
          await handle.truncate(0);
          await handle.flush();
        } finally {
          await handle.close();
        }
      }
    } on FileSystemException {
      // Overwriting is opportunistic. Deletion below is the part that must
      // still happen, so a read-only or vanished file is not fatal here.
    }
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone, or removed underneath us.
    }
  }

  /// Shreds every file beneath [directory], then removes the directory.
  static Future<void> shredDirectory(Directory directory) async {
    if (!await directory.exists()) return;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          await shredFile(entity);
        }
      }
    } on FileSystemException {
      // Fall through to the recursive delete.
    }
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Nothing more we can do from inside the app sandbox.
    }
  }

  static Uint8List _randomBlock(int size) =>
      SodiumContext.instance.sodium.randombytes.buf(size);
}
