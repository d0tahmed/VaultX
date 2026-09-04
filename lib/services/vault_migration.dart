import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import '../crypto/crypto_errors.dart';
import '../crypto/kdf_profile.dart';
import '../crypto/shredder.dart';
import 'vault_crypto_service.dart';

/// What a migration moved across.
@immutable
final class MigrationReport {
  const MigrationReport({
    required this.categories,
    required this.entries,
    required this.mediaMigrated,
    required this.mediaMissing,
  });

  final int categories;
  final int entries;
  final int mediaMigrated;

  /// Media the old vault referenced but whose files were already gone.
  final int mediaMissing;

  @override
  String toString() =>
      'MigrationReport(categories: $categories, entries: $entries, '
      'media: $mediaMigrated migrated, $mediaMissing missing)';
}

/// One-way upgrade from the VaultX v3 on-disk format to v4.
///
/// Without this, installing v4 would silently orphan every existing vault, so
/// it reads the old format exactly as v3 wrote it — including v3's own
/// weaknesses, because that is what is on disk:
///
///  * the key is 100,000 iterations of raw SHA-256 over `salt || pin` — not
///    PBKDF2 despite what the old README claimed, and not memory-hard;
///  * the payload is AES-256-CBC with **no** authentication tag, so a wrong
///    PIN and a tampered file are only distinguishable by whether the result
///    happens to parse;
///  * media files were never encrypted at all, only renamed.
///
/// Everything read here is immediately re-protected under v4's Argon2id +
/// XChaCha20-Poly1305 scheme, and the legacy files are then shredded.
final class LegacyVaultMigration {
  const LegacyVaultMigration({required this.root, required this.service});

  final Directory root;
  final VaultCryptoService service;

  static const int _legacyIterations = 100000;

  File get legacyDocument => File('${root.path}/vaultx_core.enc');
  File get legacySalt => File('${root.path}/vaultx_install.salt');
  Directory get legacyMedia => Directory('${root.path}/vaultx_media');

  /// True when a v3 vault is present and no v4 vault has been created yet.
  Future<bool> isPending() async =>
      await legacyDocument.exists() && !await service.vaultExists();

  /// Migrates the vault, re-encrypting everything under the same [secret].
  ///
  /// The v4 vault is fully written before any legacy file is destroyed, so an
  /// interruption leaves the old vault intact and the migration simply retries.
  Future<MigrationReport> migrate({
    required Uint8List secret,
    KdfProfile profile = KdfProfile.balanced,
  }) async {
    await service.initialiseCrypto();
    if (!await legacyDocument.exists()) {
      throw const KeyUnavailable('No legacy vault to migrate.');
    }
    if (await service.vaultExists()) {
      throw StateError('A v4 vault already exists; refusing to migrate over it.');
    }

    final document = await _readLegacyDocument(secret);

    final session = await service.createVault(secret: secret, profile: profile);
    try {
      final categories = _asList(document['categories']);
      final folders = _asList(document['mediaFolders']);

      var entries = 0;
      for (final category in categories) {
        entries += _asList(category['entries']).length;
      }

      var migrated = 0;
      var missing = 0;
      for (final folder in folders) {
        // _asList copies each map, so the mutated items must be written back
        // onto the folder — otherwise the saved document keeps the originals
        // and every migrated file loses its fileId.
        final items = _asList(folder['items']);
        folder['items'] = items;
        for (final item in items) {
          final id = item['id']?.toString();
          if (id == null || id.isEmpty) {
            missing++;
            continue;
          }
          final moved = await _migrateOne(
            session: session,
            item: item,
            sourceKey: 'path',
            targetKey: 'fileId',
            fileId: id,
          );
          if (moved) {
            migrated++;
          } else {
            missing++;
          }
          await _migrateOne(
            session: session,
            item: item,
            sourceKey: 'thumbnailPath',
            targetKey: 'thumbFileId',
            fileId: '${id}_thumb',
          );
        }
      }

      await service.saveDocument(session, {
        'version': 4,
        'categories': categories,
        'mediaFolders': folders,
      });

      // Only now that v4 holds everything is the old vault destroyed.
      await Shredder.shredFile(legacyDocument);
      await Shredder.shredFile(legacySalt);
      await Shredder.shredDirectory(legacyMedia);

      return MigrationReport(
        categories: categories.length,
        entries: entries,
        mediaMigrated: migrated,
        mediaMissing: missing,
      );
    } catch (_) {
      // Roll back the half-built v4 vault so `isPending()` stays true and the
      // user can retry against their untouched legacy files.
      session.dispose();
      await service.destroyVault();
      rethrow;
    } finally {
      session.dispose();
    }
  }

  /// Moves one legacy plaintext file into the encrypted store.
  Future<bool> _migrateOne({
    required VaultSession session,
    required Map<String, Object?> item,
    required String sourceKey,
    required String targetKey,
    required String fileId,
  }) async {
    final path = item[sourceKey]?.toString();
    if (path == null || path.isEmpty) return false;
    final source = File(path);
    if (!await source.exists()) {
      item.remove(sourceKey);
      return false;
    }
    await service.importMedia(
      session: session,
      source: source,
      fileId: fileId,
    );
    item.remove(sourceKey);
    item[targetKey] = fileId;
    return true;
  }

  Future<Map<String, Object?>> _readLegacyDocument(Uint8List secret) async {
    final stored = await legacyDocument.readAsString();
    if (stored.isEmpty) {
      throw const MalformedEnvelope('Legacy vault file is empty.');
    }
    final key = enc.Key(await _deriveLegacyKey(secret));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final String plaintext;
    try {
      final separator = stored.indexOf(':');
      if (separator != -1) {
        plaintext = encrypter.decrypt(
          enc.Encrypted.fromBase64(stored.substring(separator + 1)),
          iv: enc.IV(base64.decode(stored.substring(0, separator))),
        );
      } else {
        // v3's oldest format used an all-zero IV. Supported here purely so the
        // data can be rescued; nothing is ever written back in this shape.
        //
        // NOTE: this must be `enc.IV(Uint8List(16))`, not `enc.IV.fromLength(16)`.
        // Despite the name, `fromLength` is `SecureRandom(n).bytes` — it returns
        // RANDOM bytes. v3's own fallback used `fromLength`, so it generated a
        // fresh IV on every call and could never actually decrypt a zero-IV
        // vault. That made genuinely old data unrecoverable; this recovers it.
        plaintext = encrypter.decrypt(
          enc.Encrypted.fromBase64(stored),
          iv: enc.IV(Uint8List(16)),
        );
      }
    } catch (_) {
      // CBC has no authentication tag, so a wrong PIN and a corrupted file are
      // genuinely indistinguishable here. Report the honest, merged outcome.
      throw const AuthenticationFailure(
        'Could not decrypt the legacy vault: wrong PIN or damaged file.',
      );
    }

    final Object? decoded;
    try {
      decoded = json.decode(plaintext);
    } on FormatException {
      throw const AuthenticationFailure(
        'Legacy vault did not decrypt to valid data: wrong PIN or damaged file.',
      );
    }
    if (decoded is! Map) {
      throw const MalformedEnvelope('Legacy vault is not an object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  /// Reproduces v3's key derivation bit-for-bit.
  ///
  /// Runs on a background isolate: 100,000 sequential SHA-256 rounds would
  /// otherwise stall the UI thread for the whole migration.
  Future<Uint8List> _deriveLegacyKey(Uint8List secret) async {
    if (!await legacySalt.exists()) {
      throw const MalformedEnvelope('Legacy salt file is missing.');
    }
    return compute(
      _legacyKdf,
      (salt: await legacySalt.readAsBytes(), secret: secret),
    );
  }

  static Uint8List _legacyKdf(({Uint8List salt, Uint8List secret}) input) {
    List<int> key = [...input.salt, ...input.secret];
    for (var i = 0; i < _legacyIterations; i++) {
      key = sha256.convert(key).bytes;
    }
    return Uint8List.fromList(key);
  }

  static List<Map<String, Object?>> _asList(Object? value) {
    if (value is! List) return <Map<String, Object?>>[];
    return value
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList();
  }
}
