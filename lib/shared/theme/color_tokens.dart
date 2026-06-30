/// Centralised design-token colours for Srood Live.
///
/// All gold, purple, surface, and semantic colours come from here.
/// Use these constants instead of hardcoded Color(0xFF…) values.
library;

import 'package:flutter/material.dart';

abstract final class ColorTokens {
  // ── Brand gold ────────────────────────────────────────────────────────────
  /// Primary gold accent (buttons, active nav, highlights).
  static const gold       = Color(0xFFF0C15A);
  /// Slightly warmer gold variant used in some gradients.
  static const goldWarm   = Color(0xFFF4C95D);
  /// Bright gold used in luxury toasts and VIP badges.
  static const goldBright = Color(0xFFFFD76B);
  /// Muted/disabled gold.
  static const goldMuted  = Color(0xFFBB9B40);

  // ── Brand purple ──────────────────────────────────────────────────────────
  static const purple       = Color(0xFF8B26D9);
  static const purpleLight  = Color(0xFF8B5CF6);
  static const purpleDark   = Color(0xFF4C1D95);
  static const purpleDeep   = Color(0xFF3A1375);
  static const purpleSurface= Color(0xFF1A0838);

  // ── Backgrounds & surfaces ────────────────────────────────────────────────
  static const bg         = Color(0xFF0C0E14);
  static const surface    = Color(0xFF141720);
  static const surfaceAlt = Color(0xFF1A1E2C);
  static const sidebar    = Color(0xFF0F1117);
  static const border     = Color(0xFF1E2435);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const success = Color(0xFF22C55E);
  static const successMuted = Color(0xFF4CAF82);
  static const error   = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info    = Color(0xFF60A5FA);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF1F5F9);
  static const textMuted   = Color(0xFF64748B);
  static const textDisabled= Color(0xFF3A3F52);

  // ── Misc ─────────────────────────────────────────────────────────────────
  static const navActive = Color(0xFF1A2040);
  static const navAccent = Color(0xFF6366F1);
  static const red       = Color(0xFFEF4444);
  static const blue      = Color(0xFF60A5FA);
  static const green     = Color(0xFF22C55E);
  static const amber     = Color(0xFFF59E0B);
}
