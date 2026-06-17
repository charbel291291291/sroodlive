import 'package:flutter/material.dart';

import '../vip/vip_spec.dart';

/// Display-only visual properties for a VIP level.
/// Use [getVipVisualStyle] to obtain an instance. Never grants or changes VIP.
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

  final int level;
  final String label;
  final String frameAsset;
  final Color nameColor;
  final List<Color> nameGradient;
  final Color glowColor;
  final Color profileAccentColor;
  final double glowOpacity;
  final FontWeight fontWeight;

  bool get isElite => level >= 8;
  bool get useNameGradient => level >= 6;

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

/// Returns the visual package for [vipLevel], or `null` for level 0 / inactive.
/// Delegates to [VipSpecResolver] — single source of truth.
VipVisuals? getVipVisualStyle(int? vipLevel) {
  final raw = vipLevel ?? 0;
  if (raw <= 0) return null;
  final spec = VipSpecResolver.resolve(raw);
  return VipVisuals(
    level: spec.level,
    label: spec.badgeLabel,
    frameAsset: spec.frameAsset ?? '',
    nameColor: spec.nameColor,
    nameGradient: spec.nameGradient,
    glowColor: spec.glowColor,
    profileAccentColor: spec.primaryColor,
    glowOpacity: spec.glowOpacity,
    fontWeight: spec.nameFontWeight,
  );
}

/// Whether a golden-ID flag is currently active (handles optional expiry).
/// Display only — never grants anything.
bool isGoldenIdActive(bool? isGolden, DateTime? expiresAt) {
  if (isGolden != true) return false;
  if (expiresAt == null) return true;
  return expiresAt.isAfter(DateTime.now());
}
