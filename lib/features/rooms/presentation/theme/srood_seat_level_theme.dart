/// Srood Room UI v2 — 10-level luxury seat identity system.
///
/// Ported unchanged from the legacy `RoomSeatTheme` so a room's earned level
/// identity (violet glass → mythic elite) is preserved pixel-for-pixel across
/// the redesign. Pass `roomLevel` (1–10+); out-of-range values are clamped.
/// Level 0 (locked seat) has its own dedicated muted style.
library;

import 'package:flutter/material.dart';

class SroodSeatLevelTheme {
  const SroodSeatLevelTheme({
    required this.bgColors,
    required this.borderColor,
    required this.glowColor,
    required this.iconColor,
    required this.accentColor,
    required this.borderWidth,
    required this.glowBlur,
    required this.innerRingOpacity,
    required this.occupiedGlowColor,
    required this.occupiedGlowBlur,
    this.highlightOpacity = 0.0,
    this.outerHaloColor = const Color(0x00000000),
    this.outerHaloBlur = 0.0,
    this.pulseGlow = false,
  });

  // Empty seat circle
  final List<Color> bgColors;
  final Color borderColor;
  final Color glowColor;
  final Color iconColor;
  final Color accentColor; // inner ring + ornament tint
  final double borderWidth;
  final double glowBlur;
  final double innerRingOpacity; // 0 = no inner ring
  final double highlightOpacity; // shimmer bright spot at top (0 = none)
  final Color outerHaloColor; // extra outer ring (transparent = none)
  final double outerHaloBlur;
  final bool pulseGlow; // animated aura for L7+

  // Occupied seat
  final Color occupiedGlowColor;
  final double occupiedGlowBlur;

  static SroodSeatLevelTheme forLevel(int level) {
    if (level <= 0) return _kLocked;
    return _kThemes[level.clamp(1, 10) - 1];
  }

  // Locked seat: always the same dark-muted style.
  static const SroodSeatLevelTheme _kLocked = SroodSeatLevelTheme(
    bgColors: [Color(0x14050510), Color(0x0A030308)],
    borderColor: Color(0x1EFFFFFF),
    glowColor: Color(0x0F8B26D9),
    iconColor: Color(0x47FFFFFF),
    accentColor: Color(0x14FFFFFF),
    borderWidth: 1.2,
    glowBlur: 6,
    innerRingOpacity: 0,
    occupiedGlowColor: Color(0x338B26D9),
    occupiedGlowBlur: 10,
  );

  static const List<SroodSeatLevelTheme> _kThemes = [
    // ── Level 1: Violet Glass Pod ───────────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF1A0D2E), Color(0xFF0E0720)],
      borderColor: Color(0xCC8B5CF6),
      glowColor: Color(0x807C3AED),
      iconColor: Color(0xFFDDD6FE),
      accentColor: Color(0xFF8B5CF6),
      borderWidth: 1.8,
      glowBlur: 18,
      innerRingOpacity: 0.22,
      highlightOpacity: 0.12,
      outerHaloColor: Color.fromRGBO(124, 58, 237, 0.18),
      outerHaloBlur: 22,
      occupiedGlowColor: Color(0x808B5CF6),
      occupiedGlowBlur: 16,
    ),
    // ── Level 2: Silver Glass ───────────────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0x440D1828), Color(0x2A080E18)],
      borderColor: Color(0x8C9BAABB),
      glowColor: Color(0x268EB4D0),
      iconColor: Color(0xB4B4C8D4),
      accentColor: Color(0x339BAABB),
      borderWidth: 1.3,
      glowBlur: 9,
      innerRingOpacity: 0,
      occupiedGlowColor: Color(0x4D7BA8C8),
      occupiedGlowBlur: 13,
    ),
    // ── Level 3: Blue Prestige ──────────────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF0A1428), Color(0xFF060A18)],
      borderColor: Color(0xFF5BA3D9),
      glowColor: Color(0x384A90C0),
      iconColor: Color(0xFF7EC8F0),
      accentColor: Color(0xFF5BA3D9),
      borderWidth: 1.4,
      glowBlur: 11,
      innerRingOpacity: 0.08,
      occupiedGlowColor: Color(0x5260B0E0),
      occupiedGlowBlur: 14,
    ),
    // ── Level 4: Gold Warmth ────────────────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF1A1004), Color(0xFF0E0904)],
      borderColor: Color(0xFFD4A844),
      glowColor: Color(0x47B8900A),
      iconColor: Color(0xFFE8C060),
      accentColor: Color(0xFFD4A844),
      borderWidth: 1.5,
      glowBlur: 13,
      innerRingOpacity: 0.12,
      occupiedGlowColor: Color(0x59D4A844),
      occupiedGlowBlur: 16,
    ),
    // ── Level 5: Purple Luxury ──────────────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF160830), Color(0xFF0A051A)],
      borderColor: Color(0xFFD4A0FF),
      glowColor: Color(0x4D8B26D9),
      iconColor: Color(0xFFD4A0FF),
      accentColor: Color(0xFFBB80EE),
      borderWidth: 1.6,
      glowBlur: 15,
      innerRingOpacity: 0.18,
      occupiedGlowColor: Color(0x668B26D9),
      occupiedGlowBlur: 18,
    ),
    // ── Level 6: Ruby Royal ─────────────────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF240814), Color(0xFF140410)],
      borderColor: Color(0xFFE84060),
      glowColor: Color(0x4DCC2040),
      iconColor: Color(0xFFFF8090),
      accentColor: Color(0xFFFFD700),
      borderWidth: 1.7,
      glowBlur: 16,
      innerRingOpacity: 0.22,
      occupiedGlowColor: Color(0x59E84060),
      occupiedGlowBlur: 18,
      highlightOpacity: 0.12,
    ),
    // ── Level 7: Emerald Jewel (pulse) ──────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF041C10), Color(0xFF020E08)],
      borderColor: Color(0xFF40D090),
      glowColor: Color(0x5230C080),
      iconColor: Color(0xFF80F0C0),
      accentColor: Color(0xFFE8C844),
      borderWidth: 1.8,
      glowBlur: 18,
      innerRingOpacity: 0.25,
      occupiedGlowColor: Color(0x6640D090),
      occupiedGlowBlur: 20,
      highlightOpacity: 0.15,
      outerHaloColor: Color(0x2640D090),
      outerHaloBlur: 28,
      pulseGlow: true,
    ),
    // ── Level 8: Diamond Crystal (pulse) ────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF0A1830), Color(0xFF060C1C)],
      borderColor: Color(0xFF90D0FF),
      glowColor: Color(0x5960B8F0),
      iconColor: Color(0xFFD0ECFF),
      accentColor: Color(0xFFFFFFFF),
      borderWidth: 1.9,
      glowBlur: 20,
      innerRingOpacity: 0.30,
      occupiedGlowColor: Color(0x6690D0FF),
      occupiedGlowBlur: 22,
      highlightOpacity: 0.22,
      outerHaloColor: Color(0x1A90D0FF),
      outerHaloBlur: 32,
      pulseGlow: true,
    ),
    // ── Level 9: Black Gold Crown (pulse) ───────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF1A0C00), Color(0xFF0E0618)],
      borderColor: Color(0xFFFFD700),
      glowColor: Color(0x66FFD700),
      iconColor: Color(0xFFFFD700),
      accentColor: Color(0xFFFFD700),
      borderWidth: 2.0,
      glowBlur: 22,
      innerRingOpacity: 0.38,
      occupiedGlowColor: Color(0x73FFD700),
      occupiedGlowBlur: 26,
      highlightOpacity: 0.25,
      outerHaloColor: Color(0x2DFFD700),
      outerHaloBlur: 36,
      pulseGlow: true,
    ),
    // ── Level 10: Mythic Elite (pulse) ──────────────────────────────────────
    SroodSeatLevelTheme(
      bgColors: [Color(0xFF1A0030), Color(0xFF0C0020), Color(0xFF060010)],
      borderColor: Color(0xFFFFD700),
      glowColor: Color(0x80FFD700),
      iconColor: Color(0xFFFFD86B),
      accentColor: Color(0xFFE040FB),
      borderWidth: 2.2,
      glowBlur: 28,
      innerRingOpacity: 0.45,
      occupiedGlowColor: Color(0x80FFD700),
      occupiedGlowBlur: 30,
      highlightOpacity: 0.30,
      outerHaloColor: Color(0x40E040FB),
      outerHaloBlur: 48,
      pulseGlow: true,
    ),
  ];
}
