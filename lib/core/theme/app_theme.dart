import 'package:flutter/material.dart';

import 'srood_colors.dart';

class AppTheme {
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SroodColors.abyss,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: SroodColors.gold,
          brightness: Brightness.dark,
        ).copyWith(
          primary: SroodColors.gold,
          secondary: SroodColors.goldLight,
          surface: SroodColors.card,
          error: SroodColors.danger,
          onPrimary: SroodColors.abyss,
          onSecondary: SroodColors.abyss,
          onSurface: SroodColors.text,
          onError: SroodColors.text,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SroodColors.abyss,
      foregroundColor: SroodColors.text,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: SroodColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: SroodColors.cardSoft,
      contentTextStyle: const TextStyle(
        color: SroodColors.text,
        fontWeight: FontWeight.w700,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: SroodColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SroodColors.cardSoft,
      hintStyle: const TextStyle(color: SroodColors.dimText),
      labelStyle: const TextStyle(color: SroodColors.mutedText),
      prefixIconColor: SroodColors.gold,
      suffixIconColor: SroodColors.gold,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: SroodColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: SroodColors.gold, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: SroodColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: SroodColors.danger, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SroodColors.gold,
        foregroundColor: SroodColors.abyss,
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SroodColors.gold,
        foregroundColor: SroodColors.abyss,
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SroodColors.gold,
        side: const BorderSide(color: SroodColors.border),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SroodColors.goldLight,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );
}
