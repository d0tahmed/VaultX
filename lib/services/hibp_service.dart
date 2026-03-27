import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class HIBPService {
  static Future<int> checkPassword(String password) async {
    try {
      final bytes = utf8.encode(password);
      final hash = sha1.convert(bytes).toString().toUpperCase();
      final prefix = hash.substring(0, 5);
      final suffix = hash.substring(5);

      final url = Uri.parse('https://api.pwnedpasswords.com/range/$prefix');

      // Fix: 8-second timeout prevents indefinite hang on slow/captive networks
      final response = await http
          .get(url, headers: {'User-Agent': 'VaultX-Security-App'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final lines = LineSplitter.split(response.body);
        for (var line in lines) {
          final parts = line.split(':');
          if (parts.length == 2 && parts[0] == suffix) {
            return int.tryParse(parts[1].trim()) ?? 0;
          }
        }
      }
      return 0;
    } on TimeoutException {
      // Fix: timeout logged with debugPrint (stripped in release) — not print()
      debugPrint('HIBP: Request timed out.');
      return 0;
    } catch (e) {
      // Fix: print() → debugPrint() — print() outputs to logcat in release builds
      // The error message could contain the URL with the 5-char hash prefix
      debugPrint('HIBP: Check failed.');
      return 0;
    }
  }
}