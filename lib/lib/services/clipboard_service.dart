import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardService {
  static Timer? _wipeTimer;

  static Future<void> secureCopy(String text) async {
    _wipeTimer?.cancel(); // Stop any existing timers
    
    // Copy the text to the OS
    await Clipboard.setData(ClipboardData(text: text));
    
    // 15-Second Silent Assassination
    _wipeTimer = Timer(const Duration(seconds: 15), () async {
      ClipboardData? currentData = await Clipboard.getData(Clipboard.kTextPlain);
      // Only wipe if the user hasn't copied something else in the meantime
      if (currentData?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }
}