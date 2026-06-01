import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF08080B),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFD6A84F),
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF08080B),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    useMaterial3: true,
  );
}
