import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultx/crypto/sodium_context.dart';

/// Cheapest profile the envelope will accept, so the suite stays fast while
/// still exercising the real Argon2id path.
Future<void> initCrypto() => SodiumContext.ensureInitialised();

Uint8List secretOf(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List filledBytes(int length) =>
    Uint8List.fromList(List.generate(length, (i) => i % 256));
