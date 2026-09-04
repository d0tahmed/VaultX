import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultx/crypto/shredder.dart';

import '_support.dart';

void main() {
  setUpAll(initCrypto);

  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('vaultx_shred_test'));
  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  test('removes the file', () async {
    final file = File('${work.path}/secret.bin')
      ..writeAsBytesSync(filledBytes(4096));
    await Shredder.shredFile(file);
    expect(file.existsSync(), isFalse);
  });

  test('a missing file is not an error', () async {
    await Shredder.shredFile(File('${work.path}/absent.bin'));
  });

  test('handles an empty file', () async {
    final file = File('${work.path}/empty.bin')..writeAsBytesSync([]);
    await Shredder.shredFile(file);
    expect(file.existsSync(), isFalse);
  });

  test('removes a directory tree', () async {
    Directory('${work.path}/media/nested').createSync(recursive: true);
    File('${work.path}/media/a.vxm').writeAsBytesSync(filledBytes(2048));
    File('${work.path}/media/nested/b.vxm').writeAsBytesSync(filledBytes(512));
    await Shredder.shredDirectory(Directory('${work.path}/media'));
    expect(Directory('${work.path}/media').existsSync(), isFalse);
  });

  test('a missing directory is not an error', () async {
    await Shredder.shredDirectory(Directory('${work.path}/absent'));
  });
}
