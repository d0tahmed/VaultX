import 'package:flutter/material.dart';

class VaultTheme {
  static const Color bg = Color(0xFF121212);
  static ThemeData get dark => ThemeData(
    scaffoldBackgroundColor: bg,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Colors.blueAccent,
      surface: bg, // <--- This is the magic fix!
    ),
  );
}