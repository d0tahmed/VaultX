import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardService {
  static Timer? _wipeTimer;

  static Future<void> secureCopy(String text) async {
    _wipeTimer?.cancel(); 
    
    await Clipboard.setData(ClipboardData(text: text));
    
    _wipeTimer = Timer(const Duration(seconds: 15), () async {
      // 🔴 RED TEAM PATCH: Unconditional wipe. OEM skins modify clipboard strings, 
      // causing equality checks to fail. We wipe it blindly to guarantee security.
      await Clipboard.setData(const ClipboardData(text: ''));
    });
  }
}