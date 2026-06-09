import 'package:flutter/material.dart';

import '../../shared/widgets/vip_framed_avatar.dart';

/// Single source of truth for the *visual* package that goes with each VIP
/// level (1-10). This is **display only** - it never grants, changes, or
/// validates VIP. VIP ownership stays 100% server / admin controlled.
///
/// Levels escalate in richness: 1 is a clean silver look, 8-10 are elite, and
/// 10 is the highest-status look in the whole app.
@immutable
class VipVisuals {
  const VipVisuals({
    required this.level,
    required this.label,
    required this.frameAsset,
    required this.nameColor,
    required this.nameGradient,
    required this.glowColor,
    required this.profileAccentColor,
    required this.glowOpacity,
    required this.fontWeight,
  });

  /// Effective VIP level (1-10).
  final int level;

  /// Short label, e.g. "VIP 5".
  final String label;

  /// Frame PNG for this level (always non-null for a valid VIP level).
  final String frameAsset;

  /// Primary username color.
  final Color nameColor;

  /// Gradient used for the username on premium tiers (and badges/accents).
  final List<Color> nameGradient;

  /// Color of the soft glow around the name / avatar / profile accent.
  final Color glowColor;

  /// Accent color used for profile borders / highlights.
  final Color profileAccentColor;

  /// Strength of the glow (0-1). Higher levels glow more.
  final double glowOpacity;

  /// Font weight for the username.
  final FontWeight fontWeight;

  /// VIP 8-10 are the elite, most luxurious tiers.
  bool get isElite => level >= 8;

  /// Whether to paint the username with a gradient (premium tiers only).
  bool get useNameGradient => level >= 6;

  /// Soft text/box glow shadows derived from this tier (empty for low tiers).
  List<Shadow> nameShadows() {
    if (level < 5) return const [];
    return [
      Shadow(
        color: glowColor.withValues(alpha: glowOpacity.clamp(0.0, 0.6)),
        blurRadius: isElite ? 14 : 9,
      ),
    ];
  }
}

/// Returns the full visual package for [vipLevel], or `null` when the user is
/// not an active VIP (null / 0 / expired levels should be passed as 0 by the
/// caller, e.g. via `effectiveVipLevel`).
VipVisuals? getVipVisualStyle(int? vipLevel) {
  final raw = vipLevel ?? 0;
  if (raw <= 0) return null;
  final level = raw.clamp(1, 10);

  final spec = switch (level) {
    // 1 - Silver: clean, light, simple premium.
    1 => const _Spec(
        name: Color(0xFFE6E8EF),
        gradient: [Color(0xFFF6F8FF), Color(0xFFAEB6C8)],
        glow: Color(0xFFB9C2D3),
        accent: Color(0xFFC9CFDD),
        opacity: 0.16,
        weight: FontWeight.w800,
      ),
    // 2 - Gold: stronger name color, soft glow.
    2 => const _Spec(
        name: Color(0xFFFFD978),
        gradient: [Color(0xFFFFE9A8), Color(0xFFD99A2B)],
        glow: Color(0xFFE0A83A),
        accent: Color(0xFFFFD978),
        opacity: 0.22,
        weight: FontWeight.w800,
      ),
    // 3 - Rose / warm gold, better glow.
    3 => const _Spec(
        name: Color(0xFFFFC6A8),
        gradient: [Color(0xFFFFD9B8), Color(0xFFE8896B)],
        glow: Color(0xFFFF9A6B),
        accent: Color(0xFFFFB48C),
        opacity: 0.24,
        weight: FontWeight.w900,
      ),
    // 4 - Red + gold, stronger premium look.
    4 => const _Spec(
        name: Color(0xFFFF9A6B),
        gradient: [Color(0xFFFFD978), Color(0xFFE0322B)],
        glow: Color(0xFFFF4A3A),
        accent: Color(0xFFFF6B4A),
        opacity: 0.26,
        weight: FontWeight.w900,
      ),
    // 5 - Royal gold with red glow, visible accent.
    5 => const _Spec(
        name: Color(0xFFFFD15C),
        gradient: [Color(0xFFFFE08A), Color(0xFFE0002B), Color(0xFFFFD15C)],
        glow: Color(0xFFFF2A4A),
        accent: Color(0xFFFFD15C),
        opacity: 0.30,
        weight: FontWeight.w900,
      ),
    // 6 - Purple + gold, stronger profile highlight.
    6 => const _Spec(
        name: Color(0xFFE4B5FF),
        gradient: [Color(0xFFFFD978), Color(0xFF8B26D9)],
        glow: Color(0xFFB44DFF),
        accent: Color(0xFFC875FF),
        opacity: 0.30,
        weight: FontWeight.w900,
      ),
    // 7 - Blue diamond + gold, premium glow.
    7 => const _Spec(
        name: Color(0xFF9BE8FF),
        gradient: [Color(0xFFD8F6FF), Color(0xFFFFD978), Color(0xFF4CC9F0)],
        glow: Color(0xFF43C6FF),
        accent: Color(0xFF7FE6FF),
        opacity: 0.32,
        weight: FontWeight.w900,
      ),
    // 8 - Black + gold + diamond, elite look.
    8 => const _Spec(
        name: Color(0xFFFFE9A8),
        gradient: [Color(0xFFFFF3C4), Color(0xFFC8952D), Color(0xFF1A1320)],
        glow: Color(0xFFFFD978),
        accent: Color(0xFFFFE27A),
        opacity: 0.34,
        weight: FontWeight.w900,
      ),
    // 9 - Fire gold + ruby.
    9 => const _Spec(
        name: Color(0xFFFFC857),
        gradient: [Color(0xFFFFE08A), Color(0xFFFF4A2A), Color(0xFFE0002B)],
        glow: Color(0xFFFF5A2A),
        accent: Color(0xFFFF7A3A),
        opacity: 0.38,
        weight: FontWeight.w900,
      ),
    // 10 - Royal crown, strongest gold glow, highest status.
    _ => const _Spec(
        name: Color(0xFFFFE9A8),
        gradient: [
          Color(0xFFFFF3C4),
          Color(0xFFFFD24A),
          Color(0xFFFF4FD8),
          Color(0xFF7D2BFF),
        ],
        glow: Color(0xFFFFD24A),
        accent: Color(0xFFFFD978),
        opacity: 0.42,
        weight: FontWeight.w900,
      ),
  };

  return VipVisuals(
    level: level,
    label: 'VIP $level',
    frameAsset: vipFrameAssetPath(level)!,
    nameColor: spec.name,
    nameGradient: spec.gradient,
    glowColor: spec.glow,
    profileAccentColor: spec.accent,
    glowOpacity: spec.opacity,
    fontWeight: spec.weight,
  );
}

/// Whether a golden-ID flag is currently active (handles optional expiry).
/// Golden ID is a server/admin-controlled display flag - this only decides
/// whether to render the premium golden style, never grants anything.
bool isGoldenIdActive(bool? isGolden, DateTime? expiresAt) {
  if (isGolden != true) return false;
  if (expiresAt == null) return true;
  return expiresAt.isAfter(DateTime.now());
}

/// Internal compact spec holder for the level table above.
class _Spec {
  const _Spec({
    required this.name,
    required this.gradient,
    required this.glow,
    required this.accent,
    required this.opacity,
    required this.weight,
  });

  final Color name;
  final List<Color> gradient;
  final Color glow;
  final Color accent;
  final double opacity;
  final FontWeight weight;
}
