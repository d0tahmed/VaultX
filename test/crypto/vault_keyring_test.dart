import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultx/crypto/crypto_errors.dart';
import 'package:vaultx/crypto/kdf_profile.dart';
import 'package:vaultx/crypto/sodium_context.dart';
import 'package:vaultx/crypto/vault_keyring.dart';

import '_support.dart';

void main() {
  setUpAll(initCrypto);

  const profile = KdfProfile.interactive;

  ({VaultKeyring keyring, dynamic hierarchy}) freshVault(String pin) {
    final created = VaultKeyring.create(
      secret: secretOf(pin),
      profile: profile,
    );
    created.hierarchy.dispose();
    return (keyring: created.keyring, hierarchy: null);
  }

  group('creation and unlock', () {
    test('unlocks with the correct secret', () {
      final vault = freshVault('123456');
      final unlocked = vault.keyring.unlockWithSecret(secretOf('123456'));
      addTearDown(unlocked.dispose);
      expect(unlocked.generation, 1);
      expect(unlocked.keyringId, hasLength(16));
    });

    test('rejects the wrong secret', () {
      final vault = freshVault('123456');
      expect(
        () => vault.keyring.unlockWithSecret(secretOf('654321')),
        throwsA(isA<AuthenticationFailure>()),
      );
    });

    test('two vaults with the same PIN share no bytes', () {
      final a = freshVault('123456').keyring.encode();
      final b = freshVault('123456').keyring.encode();
      expect(a, isNot(equals(b)));
    });

    test('stores no verifier derived from the PIN', () {
      // The only defence against offline PIN guessing is Argon2id. If a fast
      // hash of the PIN were stored anywhere, an attacker would skip the KDF
      // entirely — which is exactly the v3 flaw this design removes.
      final encoded = utf8.decode(freshVault('123456').keyring.encode());
      final parsed = json.decode(encoded) as Map<String, dynamic>;
      expect(parsed.keys, unorderedEquals(<String>['v', 'slots']));
      expect((parsed['slots'] as Map).keys, <String>['pin']);
    });

    test('the master key is stable across unlocks', () {
      final vault = freshVault('123456');
      final first = vault.keyring.unlockWithSecret(secretOf('123456'));
      final second = vault.keyring.unlockWithSecret(secretOf('123456'));
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final a = first.hierarchy.deriveVaultDataKey();
      final b = second.hierarchy.deriveVaultDataKey();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(a.extractBytes(), b.extractBytes());
      expect(first.keyringId, second.keyringId);
    });
  });

  group('device (biometric) slot', () {
    test('unlocks with the device key without knowing the PIN', () {
      final vault = freshVault('123456');
      final unlocked = vault.keyring.unlockWithSecret(secretOf('123456'));
      addTearDown(unlocked.dispose);

      final deviceKey = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(deviceKey.dispose);

      final withDevice = vault.keyring.withDeviceSlot(
        unlocked: unlocked,
        deviceKey: deviceKey,
      );
      expect(withDevice.hasDeviceSlot, isTrue);

      final viaDevice = withDevice.unlockWithDeviceKey(deviceKey);
      addTearDown(viaDevice.dispose);

      final fromPin = unlocked.hierarchy.deriveVaultDataKey();
      final fromDevice = viaDevice.hierarchy.deriveVaultDataKey();
      addTearDown(fromPin.dispose);
      addTearDown(fromDevice.dispose);
      expect(fromDevice.extractBytes(), fromPin.extractBytes());
    });

    test('rejects the wrong device key', () {
      final vault = freshVault('123456');
      final unlocked = vault.keyring.unlockWithSecret(secretOf('123456'));
      addTearDown(unlocked.dispose);

      final aead =
          SodiumContext.instance.sodium.crypto.aeadXChaCha20Poly1305IETF;
      final good = aead.keygen();
      final bad = aead.keygen();
      addTearDown(good.dispose);
      addTearDown(bad.dispose);

      final withDevice = vault.keyring.withDeviceSlot(
        unlocked: unlocked,
        deviceKey: good,
      );
      expect(
        () => withDevice.unlockWithDeviceKey(bad),
        throwsA(isA<AuthenticationFailure>()),
      );
    });

    test('unlocking a device slot that does not exist is a typed failure', () {
      final vault = freshVault('123456');
      final key = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(key.dispose);
      expect(
        () => vault.keyring.unlockWithDeviceKey(key),
        throwsA(isA<KeyUnavailable>()),
      );
    });

    test('removing the slot revokes biometric unlock', () {
      final vault = freshVault('123456');
      final unlocked = vault.keyring.unlockWithSecret(secretOf('123456'));
      addTearDown(unlocked.dispose);
      final key = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(key.dispose);

      final revoked = vault.keyring
          .withDeviceSlot(unlocked: unlocked, deviceKey: key)
          .withoutDeviceSlot();
      expect(revoked.hasDeviceSlot, isFalse);
      expect(
        () => revoked.unlockWithDeviceKey(key),
        throwsA(isA<KeyUnavailable>()),
      );
    });
  });

  group('changing the secret', () {
    test('the old secret stops working and the new one starts', () {
      final vault = freshVault('111111');
      final unlocked = vault.keyring.unlockWithSecret(secretOf('111111'));
      addTearDown(unlocked.dispose);

      final rotated = vault.keyring.withChangedSecret(
        unlocked: unlocked,
        newSecret: secretOf('222222'),
        profile: profile,
      );

      expect(
        () => rotated.unlockWithSecret(secretOf('111111')),
        throwsA(isA<AuthenticationFailure>()),
      );
      final reopened = rotated.unlockWithSecret(secretOf('222222'));
      addTearDown(reopened.dispose);
      expect(reopened.generation, 2);
    });

    test('the vault contents key is unchanged, so no re-encryption is needed', () {
      final vault = freshVault('111111');
      final before = vault.keyring.unlockWithSecret(secretOf('111111'));
      addTearDown(before.dispose);
      final beforeKey = before.hierarchy.deriveVaultDataKey();
      addTearDown(beforeKey.dispose);

      final rotated = vault.keyring.withChangedSecret(
        unlocked: before,
        newSecret: secretOf('222222'),
        profile: profile,
      );
      final after = rotated.unlockWithSecret(secretOf('222222'));
      addTearDown(after.dispose);
      final afterKey = after.hierarchy.deriveVaultDataKey();
      addTearDown(afterKey.dispose);

      expect(afterKey.extractBytes(), beforeKey.extractBytes());
      expect(after.keyringId, before.keyringId);
    });

    test('rotation drops the device slot so a stale wrap cannot be replayed', () {
      final vault = freshVault('111111');
      final unlocked = vault.keyring.unlockWithSecret(secretOf('111111'));
      addTearDown(unlocked.dispose);
      final key = SodiumContext.instance.sodium.crypto
          .aeadXChaCha20Poly1305IETF
          .keygen();
      addTearDown(key.dispose);

      final rotated = vault.keyring
          .withDeviceSlot(unlocked: unlocked, deviceKey: key)
          .withChangedSecret(
            unlocked: unlocked,
            newSecret: secretOf('222222'),
            profile: profile,
          );
      expect(rotated.hasDeviceSlot, isFalse);
    });

    test('generation increases so a restored older keyring is detectable', () {
      final vault = freshVault('111111');
      final first = vault.keyring.unlockWithSecret(secretOf('111111'));
      addTearDown(first.dispose);
      final rotated = vault.keyring.withChangedSecret(
        unlocked: first,
        newSecret: secretOf('222222'),
        profile: profile,
      );
      final second = rotated.unlockWithSecret(secretOf('222222'));
      addTearDown(second.dispose);

      expect(second.generation, greaterThan(first.generation));
      // The rollback check the service layer performs: an attacker restoring
      // the original keyring yields generation 1 against a recorded 2.
      expect(first.generation, lessThan(second.generation));
    });
  });

  group('encoding', () {
    test('survives a round trip through bytes', () {
      final vault = freshVault('123456');
      final restored = VaultKeyring.decode(vault.keyring.encode());
      final unlocked = restored.unlockWithSecret(secretOf('123456'));
      addTearDown(unlocked.dispose);
      expect(unlocked.generation, 1);
    });

    test('rejects a keyring with no PIN slot', () {
      final bytes = Uint8List.fromList(
        utf8.encode(json.encode({'v': 1, 'slots': <String, String>{}})),
      );
      expect(
        () => VaultKeyring.decode(bytes),
        throwsA(isA<MalformedEnvelope>()),
      );
    });

    test('rejects an unknown keyring version', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          json.encode({
            'v': 42,
            'slots': {'pin': 'AA=='},
          }),
        ),
      );
      expect(
        () => VaultKeyring.decode(bytes),
        throwsA(isA<UnsupportedEnvelope>()),
      );
    });

    test('rejects non-JSON bytes', () {
      expect(
        () => VaultKeyring.decode(filledBytes(64)),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('rejects a slot that is not base64', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          json.encode({
            'v': 1,
            'slots': {'pin': 'not base64 !!!'},
          }),
        ),
      );
      expect(
        () => VaultKeyring.decode(bytes),
        throwsA(isA<MalformedEnvelope>()),
      );
    });
  });
}
