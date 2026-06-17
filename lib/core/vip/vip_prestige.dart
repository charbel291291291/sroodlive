import 'package:flutter/material.dart';

import 'vip_spec.dart';

// VipEntryTier lives in vip_spec.dart — re-export so existing imports don't break.
export 'vip_spec.dart' show VipEntryTier;

// ─────────────────────────────────────────────────────────────────────────────
// VipPrestige — kept for backward compat; consumers that need it build it via
// VipVisualResolver.resolve() which now delegates to VipSpecResolver.
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class VipPrestige {
  const VipPrestige({
    required this.level,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.gradientColors,
    required this.borderColor,
    required this.borderWidth,
    this.outerRingColor,
    required this.surfaceTint,
    required this.bubbleGradient,
    required this.nameColor,
    required this.nameFontWeight,
    required this.glowIntensity,
    required this.animIntensity,
    required this.entryTier,
    required this.cardCornerRadius,
    required this.avatarRingColor,
    required this.avatarRingWidth,
    required this.badgeGradient,
    required this.badgeTextColor,
    required this.micWaveColors,
    required this.micWaveRingCount,
  });

  final int level;
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final List<Color> gradientColors;
  final Color borderColor;
  final double borderWidth;
  final Color? outerRingColor;
  final Color surfaceTint;
  final List<Color> bubbleGradient;
  final Color nameColor;
  final FontWeight nameFontWeight;
  final double glowIntensity;
  final double animIntensity;
  final VipEntryTier entryTier;
  final double cardCornerRadius;
  final Color avatarRingColor;
  final double avatarRingWidth;
  final List<Color> badgeGradient;
  final Color badgeTextColor;
  final List<Color> micWaveColors;
  final int micWaveRingCount;

  String get badgeLabel => level <= 0 ? '' : 'VIP $level';
  bool get hasAnimation => animIntensity > 0;
  bool get isElite => level >= 8;
  bool get isLegendary => level == 9;

  Color get entryTextColor =>
      isElite ? Colors.white : const Color(0xFF160B26);

  Duration get entryBannerDuration => switch (entryTier) {
        VipEntryTier.legendary => const Duration(milliseconds: 4000),
        VipEntryTier.royal     => const Duration(milliseconds: 3500),
        VipEntryTier.luxury    => const Duration(milliseconds: 3000),
        _                      => const Duration(milliseconds: 2500),
      };

  List<BoxShadow> buildGlowShadows({double pulseFactor = 1.0}) {
    if (glowIntensity <= 0) return const [];

    final alpha =
        ((0.18 + glowIntensity * 0.35) * pulseFactor).clamp(0.0, 0.65);
    final blur   = 10.0 + glowIntensity * 22.0;
    final spread = glowIntensity * 1.5;

    return [
      BoxShadow(
        color: glowColor.withValues(alpha: alpha),
        blurRadius: blur,
        spreadRadius: spread,
      ),
      if (outerRingColor != null)
        BoxShadow(
          color: outerRingColor!,
          blurRadius: 0,
          spreadRadius: 1.2,
        ),
      if (level == 9)
        BoxShadow(
          color: const Color(0xFFFFD978).withValues(alpha: 0.22 * pulseFactor),
          blurRadius: 20,
          spreadRadius: -2,
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VipVisualResolver — delegates to VipSpecResolver (single source of truth)
// ─────────────────────────────────────────────────────────────────────────────

class VipVisualResolver {
  const VipVisualResolver._();

  /// Returns a [VipPrestige] built from [VipSpecResolver] data.
  static VipPrestige resolve(int rawLevel) {
    final spec = VipSpecResolver.resolve(rawLevel);
    return VipPrestige(
      level: spec.level,
      primaryColor: spec.primaryColor,
      secondaryColor: spec.secondaryColor,
      glowColor: spec.glowColor,
      gradientColors: spec.bannerGradient,
      borderColor: spec.borderColor,
      borderWidth: spec.borderWidth,
      outerRingColor: spec.outerRingColor,
      surfaceTint: spec.surfaceTint,
      bubbleGradient: spec.bubbleGradient,
      nameColor: spec.nameColor,
      nameFontWeight: spec.nameFontWeight,
      glowIntensity: spec.glowIntensity,
      animIntensity: spec.animIntensity,
      entryTier: spec.entryTier,
      cardCornerRadius: spec.cardCornerRadius,
      avatarRingColor: spec.avatarRingColor,
      avatarRingWidth: spec.avatarRingWidth,
      badgeGradient: spec.badgeGradient,
      badgeTextColor: spec.badgeTextColor,
      micWaveColors: spec.micWaveColors,
      micWaveRingCount: spec.micWaveRingCount,
    );
  }

  // Alias kept for any legacy call sites.
  static VipPrestige forLevel(int level) => resolve(level);
}

