import 'package:flutter/material.dart';

import '../config/app_config.dart';
import 'srood_colors.dart';

class AppTheme {
  // Computed getter so any AppConfig registered before runApp() is reflected.
  // For Srood Live the output is identical to the previous static field.
  //
  // TODO(white-label): If a client needs to restyle non-primary elements
  // (borders, muted text, card gradients, etc.) extend AppConfig with those
  // colors and replace the remaining SroodColors.* refs below.
  static ThemeData get darkTheme {
    final cfg       = AppConfig.instance;
    final primary   = cfg.primaryColor;
    final secondary = cfg.secondaryColor;
    final bg        = cfg.backgroundColor;
    final surface   = cfg.surfaceColor;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: SroodColors.danger,
        onPrimary: bg,
        onSecondary: bg,
        onSurface: SroodColors.text,
        onError: SroodColors.text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: SroodColors.text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
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
        prefixIconColor: primary,
        suffixIconColor: primary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SroodColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 1.4),
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
              return primary.withValues(alpha: 0.38);
            }
            return primary;
          }),
          foregroundColor: WidgetStateProperty.all(bg),
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.12),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return 0;
            return 6;
          }),
          shadowColor: WidgetStateProperty.all(primary.withValues(alpha: 0.55)),
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
            BorderSide(color: Colors.white.withValues(alpha: 0.20), width: 0.8),
          ),
          animationDuration: const Duration(milliseconds: 120),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return primary.withValues(alpha: 0.38);
            }
            return primary;
          }),
          foregroundColor: WidgetStateProperty.all(bg),
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.14),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return 0;
            return 7;
          }),
          shadowColor: WidgetStateProperty.all(primary.withValues(alpha: 0.55)),
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
            BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          animationDuration: const Duration(milliseconds: 120),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return primary.withValues(alpha: 0.38);
            }
            return primary;
          }),
          overlayColor: WidgetStateProperty.all(
            primary.withValues(alpha: 0.10),
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
                color: primary.withValues(alpha: 0.25),
                width: 1.2,
              );
            }
            return BorderSide(color: primary, width: 1.2);
          }),
          animationDuration: const Duration(milliseconds: 120),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: secondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
