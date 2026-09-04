import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultx/crypto/crypto_errors.dart';
import 'package:vaultx/crypto/kdf_profile.dart';
import 'package:vaultx/services/secure_store.dart';
import 'package:vaultx/services/vault_crypto_service.dart';
import 'package:vaultx/services/vault_migration.dart';

import '../crypto/_support.dart';

/// Writes a vault in exactly the format VaultX v3 produced, so the migration
/// is tested against the real legacy layout rather than an idealised one.
Future<void> writeLegacyVault({
  required Directory root,
  required String pin,
  required Map<String, Object?> document,
  bool zeroIvLegacyFormat = false,
}) async {
  final salt = Uint8List.fromList(List.generate(32, (i) => (i * 7) % 256));
  await File('${root.path}/vaultx_install.salt').writeAsBytes(salt);

  List<int> key = [...salt, ...utf8.encode(pin)];
  for (var i = 0; i < 100000; i++) {
    key = sha256.convert(key).bytes;
  }

  final encrypter = enc.Encrypter(
    enc.AES(enc.Key(Uint8List.fromList(key)), mode: enc.AESMode.cbc),
  );
  // `IV.fromLength` is random in the encrypt package; a true zero IV needs
  // an explicit zero-filled buffer.
  final iv = zeroIvLegacyFormat
      ? enc.IV(Uint8List(16))
      : enc.IV.fromSecureRandom(16);
  final cipher = encrypter.encrypt(json.encode(document), iv: iv);

  await File('${root.path}/vaultx_core.enc').writeAsString(
    zeroIvLegacyFormat ? cipher.base64 : '${base64.encode(iv.bytes)}:${cipher.base64}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCrypto);

  const profile = KdfProfile.interactive;

  late Directory root;
  late VaultCryptoService service;
  late LegacyVaultMigration migration;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vaultx_migration_test');
    service = VaultCryptoService(root: root, store: InMemorySecureStore());
    migration = LegacyVaultMigration(root: root, service: service);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Map<String, Object?> sampleDocument() => {
        'categories': [
          {
            'id': 'c1',
            'name': 'Social',
            'entries': [
              {'id': 'e1', 'title': 'Netflix', 'email': 'a@b.c', 'password': 'hunter2'},
              {'id': 'e2', 'title': 'Reddit', 'email': 'a@b.c', 'password': 'swordfish'},
            ],
          },
          {
            'id': 'c2',
            'name': 'Work',
            'entries': [
              {'id': 'e3', 'title': 'VPN', 'email': 'a@b.c', 'password': 'correct-horse'},
            ],
          },
        ],
        'mediaFolders': <Map<String, Object?>>[],
      };

  test('detects a pending legacy vault', () async {
    expect(await migration.isPending(), isFalse);
    await writeLegacyVault(root: root, pin: '123456', document: sampleDocument());
    expect(await migration.isPending(), isTrue);
  });

  test('migrates passwords and re-encrypts them under v4', () async {
    await writeLegacyVault(root: root, pin: '123456', document: sampleDocument());

    final report = await migration.migrate(
      secret: secretOf('123456'),
      profile: profile,
    );
    expect(report.categories, 2);
    expect(report.entries, 3);

    final session = await service.unlockWithSecret(secretOf('123456'));
    addTearDown(session.dispose);
    final loaded = await service.loadDocument(session);
    expect(loaded['version'], 4);
    final categories = loaded['categories'] as List;
    expect(categories, hasLength(2));
    expect((categories.first as Map)['name'], 'Social');
  });

  test('the migrated vault contains no readable plaintext', () async {
    await writeLegacyVault(root: root, pin: '123456', document: sampleDocument());
    await migration.migrate(secret: secretOf('123456'), profile: profile);
    final raw = await service.documentFile.readAsBytes();
    expect(String.fromCharCodes(raw).contains('hunter2'), isFalse);
  });

  test('reads v3 oldest zero-IV format so that data is not stranded', () async {
    await writeLegacyVault(
      root: root,
      pin: '123456',
      document: sampleDocument(),
      zeroIvLegacyFormat: true,
    );
    final report = await migration.migrate(
      secret: secretOf('123456'),
      profile: profile,
    );
    expect(report.entries, 3);
  });

  test('encrypts previously-plaintext media', () async {
    final mediaDir = Directory('${root.path}/vaultx_media')..createSync();
    final photo = File('${mediaDir.path}/abc.jpg')
      ..writeAsBytesSync(bytesOf('RAW_PHOTO_BYTES_MARKER'));

    await writeLegacyVault(
      root: root,
      pin: '123456',
      document: {
        'categories': <Map<String, Object?>>[],
        'mediaFolders': [
          {
            'id': 'f1',
            'name': 'Photos',
            'type': 'photo',
            'items': [
              {'id': 'm1', 'path': photo.path, 'thumbnailPath': null},
            ],
          },
        ],
      },
    );

    final report = await migration.migrate(
      secret: secretOf('123456'),
      profile: profile,
    );
    expect(report.mediaMigrated, 1);
    expect(report.mediaMissing, 0);

    final session = await service.unlockWithSecret(secretOf('123456'));
    addTearDown(session.dispose);

    // The bytes come back intact...
    expect(
      await service.readMedia(session: session, fileId: 'm1'),
      bytesOf('RAW_PHOTO_BYTES_MARKER'),
    );
    // ...but are no longer readable on disk, which was the v3 flaw.
    final stored = await service.mediaFileFor('m1').readAsBytes();
    expect(
      String.fromCharCodes(stored).contains('RAW_PHOTO_BYTES_MARKER'),
      isFalse,
    );
    // And the old plaintext copy is gone.
    expect(photo.existsSync(), isFalse);

    final document = await service.loadDocument(session);
    final item = ((document['mediaFolders'] as List).first
        as Map)['items'] as List;
    expect((item.first as Map)['fileId'], 'm1');
    expect((item.first as Map).containsKey('path'), isFalse);
  });

  test('counts media whose files have already vanished', () async {
    await writeLegacyVault(
      root: root,
      pin: '123456',
      document: {
        'categories': <Map<String, Object?>>[],
        'mediaFolders': [
          {
            'id': 'f1',
            'name': 'Photos',
            'type': 'photo',
            'items': [
              {'id': 'm1', 'path': '${root.path}/vaultx_media/gone.jpg'},
            ],
          },
        ],
      },
    );
    final report = await migration.migrate(
      secret: secretOf('123456'),
      profile: profile,
    );
    expect(report.mediaMigrated, 0);
    expect(report.mediaMissing, 1);
  });

  test('shreds the legacy files once migration succeeds', () async {
    await writeLegacyVault(root: root, pin: '123456', document: sampleDocument());
    await migration.migrate(secret: secretOf('123456'), profile: profile);
    expect(migration.legacyDocument.existsSync(), isFalse);
    expect(migration.legacySalt.existsSync(), isFalse);
    expect(await migration.isPending(), isFalse);
  });

  test('a wrong PIN fails and leaves the legacy vault untouched', () async {
    await writeLegacyVault(root: root, pin: '123456', document: sampleDocument());
    await expectLater(
      migration.migrate(secret: secretOf('999999'), profile: profile),
      throwsA(isA<AuthenticationFailure>()),
    );
    // Nothing destroyed, nothing half-created: the user can simply retry.
    expect(migration.legacyDocument.existsSync(), isTrue);
    expect(migration.legacySalt.existsSync(), isTrue);
    expect(await service.vaultExists(), isFalse);
    expect(await migration.isPending(), isTrue);
  });

  test('refuses to run over an existing v4 vault', () async {
    await writeLegacyVault(root: root, pin: '123456', document: sampleDocument());
    (await service.createVault(secret: secretOf('abcdef'), profile: profile))
        .dispose();
    await expectLater(
      migration.migrate(secret: secretOf('123456'), profile: profile),
      throwsA(isA<StateError>()),
    );
  });

  test('migrating with no legacy vault is a typed failure', () async {
    await expectLater(
      migration.migrate(secret: secretOf('123456'), profile: profile),
      throwsA(isA<KeyUnavailable>()),
    );
  });
}
