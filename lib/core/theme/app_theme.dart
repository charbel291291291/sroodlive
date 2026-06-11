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
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return SroodColors.gold.withValues(alpha: 0.38);
          }
          return SroodColors.gold;
        }),
        foregroundColor: WidgetStateProperty.all(SroodColors.abyss),
        overlayColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.12),
        ),
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return 0;
          return 6;
        }),
        shadowColor: WidgetStateProperty.all(
          SroodColors.gold.withValues(alpha: 0.55),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        side: WidgetStateProperty.all(
          BorderSide(
            color: Colors.white.withValues(alpha: 0.20),
            width: 0.8,
          ),
        ),
        animationDuration: const Duration(milliseconds: 120),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return SroodColors.gold.withValues(alpha: 0.38);
          }
          return SroodColors.gold;
        }),
        foregroundColor: WidgetStateProperty.all(SroodColors.abyss),
        overlayColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.14),
        ),
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return 0;
          return 7;
        }),
        shadowColor: WidgetStateProperty.all(
          SroodColors.gold.withValues(alpha: 0.55),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        side: WidgetStateProperty.all(
          BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.8,
          ),
        ),
        animationDuration: const Duration(milliseconds: 120),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return SroodColors.gold.withValues(alpha: 0.38);
          }
          return SroodColors.gold;
        }),
        overlayColor: WidgetStateProperty.all(
          SroodColors.gold.withValues(alpha: 0.10),
        ),
        elevation: WidgetStateProperty.all(0),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(
              color: SroodColors.gold.withValues(alpha: 0.25),
              width: 1.2,
            );
          }
          return const BorderSide(color: SroodColors.gold, width: 1.2);
        }),
        animationDuration: const Duration(milliseconds: 120),
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
