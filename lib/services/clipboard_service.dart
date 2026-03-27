import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardService {
  static Timer? _wipeTimer;

  static Future<void> secureCopy(String text) async {
    _wipeTimer?.cancel(); 
    await Clipboard.setData(ClipboardData(text: text));
    _wipeTimer = Timer(const Duration(seconds: 15), () async {
      await Clipboard.setData(const ClipboardData(text: ''));
    });
  }
}