import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultx/crypto/crypto_errors.dart';
import 'package:vaultx/crypto/kdf_profile.dart';
import 'package:vaultx/crypto/sodium_context.dart';
import 'package:vaultx/services/secure_store.dart';
import 'package:vaultx/services/vault_crypto_service.dart';

import '../crypto/_support.dart';

void main() {
  setUpAll(initCrypto);

  const profile = KdfProfile.interactive;

  late Directory root;
  late InMemorySecureStore store;
  late VaultCryptoService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vaultx_service_test');
    store = InMemorySecureStore();
    service = VaultCryptoService(
      root: root,
      store: store,
      attemptsBeforeDestruction: 3,
      attemptsBeforeCooldown: 99, // disabled unless a test opts in
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<VaultSession> create([String pin = '123456']) =>
      service.createVault(secret: secretOf(pin), profile: profile);

  group('lifecycle', () {
    test('creates and unlocks a vault', () async {
      (await create()).dispose();
      expect(await service.vaultExists(), isTrue);
      final session = await service.unlockWithSecret(secretOf('123456'));
      addTearDown(session.dispose);
      expect(session.generation, 1);
    });

    test('rejects the wrong secret', () async {
      (await create()).dispose();
      await expectLater(
        service.unlockWithSecret(secretOf('999999')),
        throwsA(isA<AuthenticationFailure>()),
      );
    });

    test('refuses to overwrite an existing vault', () async {
      (await create()).dispose();
      await expectLater(create(), throwsA(isA<StateError>()));
    });

    test('unlocking before creation is a typed failure', () async {
      await expectLater(
        service.unlockWithSecret(secretOf('123456')),
        throwsA(isA<KeyUnavailable>()),
      );
    });
  });

  group('vault document', () {
    test('round-trips through disk', () async {
      final session = await create();
      addTearDown(session.dispose);
      await service.saveDocument(session, {
        'categories': [
          {'id': 'c1', 'name': 'Social'},
        ],
      });
      final loaded = await service.loadDocument(session);
      expect((loaded['categories'] as List).first, {'id': 'c1', 'name': 'Social'});
    });

    test('is ciphertext on disk', () async {
      final session = await create();
      addTearDown(session.dispose);
      await service.saveDocument(session, {'note': 'PLAINTEXT_CANARY_VALUE'});
      final raw = await service.documentFile.readAsBytes();
      expect(
        String.fromCharCodes(raw).contains('PLAINTEXT_CANARY_VALUE'),
        isFalse,
        reason: 'vault document must not contain readable plaintext',
      );
    });

    test('a tampered document fails to load', () async {
      final session = await create();
      addTearDown(session.dispose);
      await service.saveDocument(session, {'note': 'x'});
      final raw = await service.documentFile.readAsBytes();
      raw[raw.length - 1] ^= 0x01;
      await service.documentFile.writeAsBytes(raw);
      await expectLater(
        service.loadDocument(session),
        throwsA(isA<AuthenticationFailure>()),
      );
    });

    test('leaves no temporary file behind', () async {
      final session = await create();
      addTearDown(session.dispose);
      await service.saveDocument(session, {'note': 'x'});
      expect(File('${service.documentFile.path}.tmp').existsSync(), isFalse);
    });
  });

  group('media', () {
    test('imports and reads back a file', () async {
      final session = await create();
      addTearDown(session.dispose);
      final source = File('${root.path}/photo.jpg')
        ..writeAsBytesSync(filledBytes(9000));
      await service.importMedia(
        session: session,
        source: source,
        fileId: 'media-1',
      );
      final back = await service.readMedia(session: session, fileId: 'media-1');
      expect(back, filledBytes(9000));
    });

    test('stores media as ciphertext, not a renamed copy', () async {
      final session = await create();
      addTearDown(session.dispose);
      final original = bytesOf('MEDIA_CANARY_CONTENT_MARKER');
      final source = File('${root.path}/photo.jpg')
        ..writeAsBytesSync(original);
      await service.importMedia(
        session: session,
        source: source,
        fileId: 'media-2',
      );
      final stored = await service.mediaFileFor('media-2').readAsBytes();
      expect(
        String.fromCharCodes(stored).contains('MEDIA_CANARY_CONTENT_MARKER'),
        isFalse,
        reason: 'v3 stored media as plain copies; v4 must not',
      );
      expect(stored, isNot(equals(original)));
    });

    test('deleting shreds the stored file', () async {
      final session = await create();
      addTearDown(session.dispose);
      final source = File('${root.path}/photo.jpg')
        ..writeAsBytesSync(filledBytes(2048));
      await service.importMedia(
        session: session,
        source: source,
        fileId: 'media-3',
      );
      await service.deleteMedia('media-3');
      expect(service.mediaFileFor('media-3').existsSync(), isFalse);
    });
  });

  group('changing the secret', () {
    test('old PIN stops working, new one works, data survives', () async {
      final session = await create('111111');
      await service.saveDocument(session, {'note': 'kept'});
      await service.changeSecret(
        session: session,
        newSecret: secretOf('222222'),
        profile: profile,
      );
      session.dispose();

      await expectLater(
        service.unlockWithSecret(secretOf('111111')),
        throwsA(isA<AuthenticationFailure>()),
      );

      final reopened = await service.unlockWithSecret(secretOf('222222'));
      addTearDown(reopened.dispose);
      expect((await service.loadDocument(reopened))['note'], 'kept');
    });

    test('media stays readable after a PIN change', () async {
      final session = await create('111111');
      final source = File('${root.path}/photo.jpg')
        ..writeAsBytesSync(filledBytes(4096));
      await service.importMedia(
        session: session,
        source: source,
        fileId: 'm1',
      );
      await service.changeSecret(
        session: session,
        newSecret: secretOf('222222'),
        profile: profile,
      );
      session.dispose();

      final reopened = await service.unlockWithSecret(secretOf('222222'));
      addTearDown(reopened.dispose);
      expect(
        await service.readMedia(session: reopened, fileId: 'm1'),
        filledBytes(4096),
      );
    });
  });

  group('biometric slot', () {
    test('enrols a device key and unlocks with it', () async {
      final session = await create();
      final deviceKey = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(deviceKey.dispose);

      await service.enrolDeviceKey(session: session, deviceKey: deviceKey);
      await service.saveDocument(session, {'note': 'bio'});
      session.dispose();

      final viaBio = await service.unlockWithDeviceKey(deviceKey);
      addTearDown(viaBio.dispose);
      expect((await service.loadDocument(viaBio))['note'], 'bio');
    });

    test('revoking the device key blocks biometric unlock', () async {
      final session = await create();
      final deviceKey = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(deviceKey.dispose);
      await service.enrolDeviceKey(session: session, deviceKey: deviceKey);
      session.dispose();

      await service.revokeDeviceKey();
      await expectLater(
        service.unlockWithDeviceKey(deviceKey),
        throwsA(isA<KeyUnavailable>()),
      );
    });
  });

  group('rollback protection', () {
    test('restoring a pre-rotation keyring is rejected', () async {
      final session = await create('111111');
      // An attacker snapshots the keyring before the user changes their PIN.
      final captured = await service.keyringFile.readAsBytes();

      await service.changeSecret(
        session: session,
        newSecret: secretOf('222222'),
        profile: profile,
      );
      session.dispose();

      // ...then restores it, hoping the revoked PIN works again.
      await service.keyringFile.writeAsBytes(captured);

      await expectLater(
        service.unlockWithSecret(secretOf('111111')),
        throwsA(isA<VaultRolledBack>()),
      );
    });

    test('a keyring from a different vault is treated as new, not a rollback',
        () async {
      (await create('111111')).dispose();
      final other = Directory.systemTemp.createTempSync('vaultx_other');
      addTearDown(() => other.deleteSync(recursive: true));
      final otherService = VaultCryptoService(
        root: other,
        store: InMemorySecureStore(),
      );
      (await otherService.createVault(
        secret: secretOf('333333'),
        profile: profile,
      )).dispose();

      await service.keyringFile.writeAsBytes(
        await otherService.keyringFile.readAsBytes(),
      );
      final session = await service.unlockWithSecret(secretOf('333333'));
      addTearDown(session.dispose);
      expect(session.generation, 1);
    });
  });

  group('brute-force response', () {
    test('destroys the vault after the configured number of failures',
        () async {
      (await create()).dispose();
      final source = File('${root.path}/photo.jpg')
        ..writeAsBytesSync(filledBytes(1024));
      final session = await service.unlockWithSecret(secretOf('123456'));
      await service.importMedia(
        session: session,
        source: source,
        fileId: 'doomed',
      );
      session.dispose();

      for (var i = 0; i < 2; i++) {
        await expectLater(
          service.unlockWithSecret(secretOf('000000')),
          throwsA(isA<AuthenticationFailure>()),
        );
      }
      await expectLater(
        service.unlockWithSecret(secretOf('000000')),
        throwsA(isA<VaultDestroyed>()),
      );

      // v3 deleted only the keystore entries. Everything must be gone.
      expect(service.keyringFile.existsSync(), isFalse);
      expect(service.documentFile.existsSync(), isFalse);
      expect(service.mediaDirectory.existsSync(), isFalse);
    });

    test('a successful unlock clears the failure counter', () async {
      (await create()).dispose();
      await expectLater(
        service.unlockWithSecret(secretOf('000000')),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(await service.failureCount(), 1);
      (await service.unlockWithSecret(secretOf('123456'))).dispose();
      expect(await service.failureCount(), 0);
    });

    test('applies a cooldown before destruction', () async {
      final cooled = VaultCryptoService(
        root: root,
        store: store,
        attemptsBeforeDestruction: 8,
        attemptsBeforeCooldown: 2,
      );
      (await cooled.createVault(secret: secretOf('123456'), profile: profile))
          .dispose();

      for (var i = 0; i < 2; i++) {
        await expectLater(
          cooled.unlockWithSecret(secretOf('000000')),
          throwsA(isA<AuthenticationFailure>()),
        );
      }
      expect(await cooled.remainingLockout(), greaterThan(Duration.zero));
      await expectLater(
        cooled.unlockWithSecret(secretOf('123456')),
        throwsA(isA<VaultLockedOut>()),
      );
    });

    test('a corrupted failure counter does not crash unlock', () async {
      (await create()).dispose();
      await store.write('vaultx.auth.failures', 'not-a-number');
      await expectLater(
        service.unlockWithSecret(secretOf('000000')),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(await service.failureCount(), 1);
    });
  });

  group('destroyVault', () {
    test('removes every artefact', () async {
      final session = await create();
      final source = File('${root.path}/photo.jpg')
        ..writeAsBytesSync(filledBytes(1024));
      await service.importMedia(session: session, source: source, fileId: 'm');
      await service.saveDocument(session, {'note': 'x'});
      session.dispose();

      await service.destroyVault();
      expect(service.keyringFile.existsSync(), isFalse);
      expect(service.documentFile.existsSync(), isFalse);
      expect(service.mediaDirectory.existsSync(), isFalse);
      expect(await service.vaultExists(), isFalse);
    });
  });
}
