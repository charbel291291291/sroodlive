/// Centralised typography for Srood Live.
///
/// Use these named styles instead of inline TextStyle(...) definitions.
library;

import 'package:flutter/material.dart';
import 'color_tokens.dart';

abstract final class SroodTextStyles {
  // ── Display ───────────────────────────────────────────────────────────────
  static const displayLarge = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const displayMedium = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  // ── Titles ────────────────────────────────────────────────────────────────
  static const titleLarge = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  static const titleMedium = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const titleSmall = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  // ── Body ──────────────────────────────────────────────────────────────────
  static const bodyLarge = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const bodyMedium = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const bodySmall = TextStyle(
    color: ColorTokens.textMuted,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  // ── Labels ────────────────────────────────────────────────────────────────
  static const labelLarge = TextStyle(
    color: ColorTokens.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  static const labelMedium = TextStyle(
    color: ColorTokens.textMuted,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static const labelSmall = TextStyle(
    color: ColorTokens.textMuted,
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.2,
  );

  // ── Caption ───────────────────────────────────────────────────────────────
  static const caption = TextStyle(
    color: ColorTokens.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  // ── Gold accent ───────────────────────────────────────────────────────────
  static const goldLabel = TextStyle(
    color: ColorTokens.gold,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.3,
  );

  static const goldTitle = TextStyle(
    color: ColorTokens.gold,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  // ── Button ────────────────────────────────────────────────────────────────
  static const buttonLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.3,
  );

  static const buttonMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}
