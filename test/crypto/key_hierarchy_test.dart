import 'package:flutter_test/flutter_test.dart';
import 'package:vaultx/crypto/key_hierarchy.dart';

import '_support.dart';

void main() {
  setUpAll(initCrypto);

  test('every subkey is distinct', () {
    final hierarchy = KeyHierarchy(KeyHierarchy.generateMasterKey());
    addTearDown(hierarchy.dispose);

    final keys = [
      hierarchy.deriveVaultDataKey(),
      hierarchy.deriveMediaMasterKey(),
      hierarchy.deriveAuditKey(),
      hierarchy.deriveSearchIndexKey(),
    ];
    for (final key in keys) {
      addTearDown(key.dispose);
    }
    final materials = keys.map((k) => k.extractBytes().join(',')).toSet();
    expect(materials, hasLength(keys.length));
  });

  test('no subkey equals the master key', () {
    final master = KeyHierarchy.generateMasterKey();
    final hierarchy = KeyHierarchy(master);
    addTearDown(hierarchy.dispose);
    final vaultKey = hierarchy.deriveVaultDataKey();
    addTearDown(vaultKey.dispose);
    expect(vaultKey.extractBytes(), isNot(equals(master.extractBytes())));
  });

  test('derivation is deterministic for one master key', () {
    final hierarchy = KeyHierarchy(KeyHierarchy.generateMasterKey());
    addTearDown(hierarchy.dispose);
    final a = hierarchy.deriveVaultDataKey();
    final b = hierarchy.deriveVaultDataKey();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(a.extractBytes(), b.extractBytes());
  });

  test('different master keys give different subkeys', () {
    final first = KeyHierarchy(KeyHierarchy.generateMasterKey());
    final second = KeyHierarchy(KeyHierarchy.generateMasterKey());
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final a = first.deriveVaultDataKey();
    final b = second.deriveVaultDataKey();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(a.extractBytes(), isNot(equals(b.extractBytes())));
  });

  group('per-file media keys', () {
    test('are deterministic for the same file id', () {
      final hierarchy = KeyHierarchy(KeyHierarchy.generateMasterKey());
      addTearDown(hierarchy.dispose);
      final a = hierarchy.deriveMediaFileKey('file-a');
      final b = hierarchy.deriveMediaFileKey('file-a');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(a.extractBytes(), b.extractBytes());
    });

    test('differ per file, so one leaked key exposes only one file', () {
      final hierarchy = KeyHierarchy(KeyHierarchy.generateMasterKey());
      addTearDown(hierarchy.dispose);
      final a = hierarchy.deriveMediaFileKey('file-a');
      final b = hierarchy.deriveMediaFileKey('file-b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(a.extractBytes(), isNot(equals(b.extractBytes())));
    });

    test('do not equal the media master key', () {
      final hierarchy = KeyHierarchy(KeyHierarchy.generateMasterKey());
      addTearDown(hierarchy.dispose);
      final master = hierarchy.deriveMediaMasterKey();
      final file = hierarchy.deriveMediaFileKey('file-a');
      addTearDown(master.dispose);
      addTearDown(file.dispose);
      expect(file.extractBytes(), isNot(equals(master.extractBytes())));
    });
  });
}
