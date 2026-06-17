import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VipEntryTier — room entry animation richness
// ─────────────────────────────────────────────────────────────────────────────

enum VipEntryTier {
  none,       // VIP 0 — no banner
  sparkle,    // VIP 1–2 — compact banner
  glow,       // VIP 3 — premium glow slide-in
  premium,    // VIP 4 — slide-in with aura
  luxury,     // VIP 5–6 — rich glow (L6 is silent, tier kept for future use)
  royal,      // VIP 7–8 — animated entrance (L7–8 silent)
  legendary,  // VIP 9 — cinematic (silent)
}

// ─────────────────────────────────────────────────────────────────────────────
// VipSpec — single source of truth for all VIP visual properties
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class VipSpec {
  const VipSpec({
    required this.level,
    // Name / username
    required this.nameColor,
    required this.nameFontWeight,
    required this.nameGradient,
    required this.glowOpacity,
    // Badge
    required this.badgeGradient,
    required this.badgeTextColor,
    required this.badgeIcon,
    // Banner (entrance background gradient)
    required this.bannerGradient,
    // Colors
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.glowIntensity,
    required this.borderColor,
    required this.borderWidth,
    this.outerRingColor,
    required this.surfaceTint,
    // Chat bubble
    required this.bubbleGradient,
    // Avatar ring
    required this.avatarRingColor,
    required this.avatarRingWidth,
    // Frame
    this.frameAsset,
    // Mic wave
    required this.micWaveColors,
    required this.micWaveRingCount,
    // Entry / animation
    required this.entryTier,
    required this.cardCornerRadius,
    required this.animIntensity,
    // Flags
    required this.hasBadge,
    required this.hasFrame,
    required this.hasMicWave,
    required this.hasEntranceEffect,
    required this.hasProfileGlow,
  });

  final int level;

  // ── Name / username ────────────────────────────────────────────────────────
  final Color nameColor;
  final FontWeight nameFontWeight;
  final List<Color> nameGradient;
  final double glowOpacity;

  // ── Badge ──────────────────────────────────────────────────────────────────
  final List<Color> badgeGradient;
  final Color badgeTextColor;
  final IconData badgeIcon;

  // ── Entrance banner ────────────────────────────────────────────────────────
  final List<Color> bannerGradient;

  // ── Core colors ────────────────────────────────────────────────────────────
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final double glowIntensity;
  final Color borderColor;
  final double borderWidth;
  final Color? outerRingColor;
  final Color surfaceTint;
  final List<Color> bubbleGradient;

  // ── Avatar ─────────────────────────────────────────────────────────────────
  final Color avatarRingColor;
  final double avatarRingWidth;

  // ── Frame ──────────────────────────────────────────────────────────────────
  final String? frameAsset;

  // ── Mic wave ───────────────────────────────────────────────────────────────
  final List<Color> micWaveColors;
  final int micWaveRingCount;

  // ── Entry / card ───────────────────────────────────────────────────────────
  final VipEntryTier entryTier;
  final double cardCornerRadius;
  final double animIntensity;

  // ── Feature flags ──────────────────────────────────────────────────────────
  final bool hasBadge;
  final bool hasFrame;
  final bool hasMicWave;
  final bool hasEntranceEffect;
  final bool hasProfileGlow;

  // ── Derived ────────────────────────────────────────────────────────────────

  bool get isElite => level >= 8;
  bool get isLegendary => level == 9;
  bool get hasAnimation => animIntensity > 0;
  bool get useNameGradient => level >= 6;
  String get badgeLabel => level <= 0 ? '' : 'VIP $level';

  /// Text colour for use on the entrance banner background.
  Color get entryTextColor =>
      isElite ? Colors.white : const Color(0xFF160B26);

  /// How long the entrance banner stays visible.
  Duration get entranceDuration => switch (entryTier) {
        VipEntryTier.legendary => const Duration(milliseconds: 4000),
        VipEntryTier.royal     => const Duration(milliseconds: 3500),
        VipEntryTier.luxury    => const Duration(milliseconds: 3000),
        _                      => const Duration(milliseconds: 2500),
      };

  /// Soft glow shadows to place behind a username or avatar container.
  List<Shadow> nameShadows() {
    if (level < 5) return const [];
    return [
      Shadow(
        color: glowColor.withValues(alpha: glowOpacity.clamp(0.0, 0.6)),
        blurRadius: isElite ? 14 : 9,
      ),
    ];
  }

  /// BoxShadow glow suitable for avatar containers or entry banners.
  /// [pulseFactor] (0–1) scales the effect for animated seats.
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
// Helpers — single authoritative implementations
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the asset path for the PNG VIP frame at [level] (1–9).
/// Returns `null` for level 0 or out-of-range.
String? vipFrameAssetPath(int level) => switch (level.clamp(0, 9)) {
      1 => 'assets/images/vip_frames/11.png',
      2 => 'assets/images/vip_frames/2.png',
      3 => 'assets/images/vip_frames/3.png',
      4 => 'assets/images/vip_frames/vip4.png',
      5 => 'assets/images/vip_frames/5.png',
      6 => 'assets/images/vip_frames/6.png',
      7 => 'assets/images/vip_frames/7.png',
      8 => 'assets/images/vip_frames/88.png',
      9 => 'assets/images/vip_frames/99.png',
      _ => null,
    };

/// Frame bounding-box scale relative to the avatar diameter.
/// A VIP PNG frame at 1.35× means the photo fills 74 % of the frame box.
/// [custom] = true for non-VIP custom/luxury frames (different ratio).
double vipFrameScale(int level, {bool compact = false, bool custom = false}) {
  if (custom) {
    return compact ? 1.18 : 1.45;
  }
  if (level > 0) return compact ? 1.32 : 1.35;
  return 1.0;
}

// TODO Phase 5: decide whether VIP 10 is a reserved admin tier or whether
//              the DB constraint should be clamped to 0–9 permanently.
//              Flutter already clamps via .clamp(0, 9) everywhere.

// ─────────────────────────────────────────────────────────────────────────────
// VipSpecResolver — call resolve(level) from anywhere in the app
// ─────────────────────────────────────────────────────────────────────────────

class VipSpecResolver {
  const VipSpecResolver._();

  /// Returns the [VipSpec] for [rawLevel], clamped to 0–9.
  static VipSpec resolve(int rawLevel) => _table[rawLevel.clamp(0, 9)];

  static const List<VipSpec> _table = [
    _s0, _s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9,
  ];

  // ── VIP 0 — no luxury ─────────────────────────────────────────────────────
  static const _s0 = VipSpec(
    level: 0,
    nameColor: Colors.white,
    nameFontWeight: FontWeight.w700,
    nameGradient: [Colors.white],
    glowOpacity: 0,
    badgeGradient: [Color(0xFF2A2A2A), Color(0xFF444444)],
    badgeTextColor: Color(0xB3FFFFFF),
    badgeIcon: Icons.auto_awesome_rounded,
    bannerGradient: [Color(0xFF2A2A2A), Color(0xFF383838)],
    primaryColor: Color(0xFFAAAAAA),
    secondaryColor: Color(0xFF888888),
    glowColor: Color(0x00000000),
    glowIntensity: 0,
    borderColor: Color(0x1AFFFFFF),
    borderWidth: 0.8,
    surfaceTint: Color(0xFF101014),
    bubbleGradient: [Color(0xFF101014), Color(0xFF101014)],
    avatarRingColor: Color(0x22FFFFFF),
    avatarRingWidth: 0,
    frameAsset: null,
    micWaveColors: [Color(0xFF4ADE80)],
    micWaveRingCount: 1,
    entryTier: VipEntryTier.none,
    cardCornerRadius: 14,
    animIntensity: 0,
    hasBadge: false,
    hasFrame: false,
    hasMicWave: false,
    hasEntranceEffect: false,
    hasProfileGlow: false,
  );

  // ── VIP 1 — champagne bronze ───────────────────────────────────────────────
  static const _s1 = VipSpec(
    level: 1,
    nameColor: Color(0xFFE6E8EF),
    nameFontWeight: FontWeight.w800,
    nameGradient: [Color(0xFFF6F8FF), Color(0xFFAEB6C8)],
    glowOpacity: 0.16,
    badgeGradient: [Color(0xFFE8AE60), Color(0xFFB87C36)],
    badgeTextColor: Color(0xFF160B26),
    badgeIcon: Icons.auto_awesome_rounded,
    bannerGradient: [Color(0xFFE8AE60), Color(0xFFB87C36)],
    primaryColor: Color(0xFFB87C36),
    secondaryColor: Color(0xFFE8AE60),
    glowColor: Color(0xFFB87C36),
    glowIntensity: 0.22,
    borderColor: Color(0xFFB87C36),
    borderWidth: 1.0,
    surfaceTint: Color(0xFF120D04),
    bubbleGradient: [Color(0xFF120D04), Color(0xFF120D04)],
    avatarRingColor: Color(0xFFB87C36),
    avatarRingWidth: 1.2,
    frameAsset: 'assets/images/vip_frames/11.png',
    micWaveColors: [Color(0xFFB87C36)],
    micWaveRingCount: 1,
    entryTier: VipEntryTier.sparkle,
    cardCornerRadius: 14,
    animIntensity: 0,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: true,
    hasProfileGlow: true,
  );

  // ── VIP 2 — rose gold ─────────────────────────────────────────────────────
  static const _s2 = VipSpec(
    level: 2,
    nameColor: Color(0xFFFFD978),
    nameFontWeight: FontWeight.w800,
    nameGradient: [Color(0xFFFFE9A8), Color(0xFFD99A2B)],
    glowOpacity: 0.22,
    badgeGradient: [Color(0xFFFFCFB8), Color(0xFFCE6E66)],
    badgeTextColor: Color(0xFF160B26),
    badgeIcon: Icons.auto_awesome_rounded,
    bannerGradient: [Color(0xFFFFCFB8), Color(0xFFCE6E66)],
    primaryColor: Color(0xFFCE6E66),
    secondaryColor: Color(0xFFFFB0A6),
    glowColor: Color(0xFFCE6E66),
    glowIntensity: 0.26,
    borderColor: Color(0xFFCE6E66),
    borderWidth: 1.2,
    surfaceTint: Color(0xFF140808),
    bubbleGradient: [Color(0xFF1C0C0A), Color(0xFF140808)],
    avatarRingColor: Color(0xFFCE6E66),
    avatarRingWidth: 1.3,
    frameAsset: 'assets/images/vip_frames/2.png',
    micWaveColors: [Color(0xFFCE6E66), Color(0xFFFFB0A6)],
    micWaveRingCount: 1,
    entryTier: VipEntryTier.sparkle,
    cardCornerRadius: 14,
    animIntensity: 0,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: true,
    hasProfileGlow: true,
  );

  // ── VIP 3 — warm gold ─────────────────────────────────────────────────────
  static const _s3 = VipSpec(
    level: 3,
    nameColor: Color(0xFFFFC6A8),
    nameFontWeight: FontWeight.w900,
    nameGradient: [Color(0xFFFFD9B8), Color(0xFFE8896B)],
    glowOpacity: 0.24,
    badgeGradient: [Color(0xFFFFE3A3), Color(0xFFCCA020)],
    badgeTextColor: Color(0xFF160B26),
    badgeIcon: Icons.auto_awesome_rounded,
    bannerGradient: [Color(0xFFFFE3A3), Color(0xFFCCA020)],
    primaryColor: Color(0xFFCCA020),
    secondaryColor: Color(0xFFFFD978),
    glowColor: Color(0xFFCCA020),
    glowIntensity: 0.30,
    borderColor: Color(0xFFCCA020),
    borderWidth: 1.4,
    surfaceTint: Color(0xFF130F00),
    bubbleGradient: [Color(0xFF1A1200), Color(0xFF130F00)],
    avatarRingColor: Color(0xFFCCA020),
    avatarRingWidth: 1.4,
    frameAsset: 'assets/images/vip_frames/3.png',
    micWaveColors: [Color(0xFFCCA020), Color(0xFFFFD978)],
    micWaveRingCount: 2,
    entryTier: VipEntryTier.glow,
    cardCornerRadius: 15,
    animIntensity: 0,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: true,
    hasProfileGlow: true,
  );

  // ── VIP 4 — gold + royal purple ───────────────────────────────────────────
  static const _s4 = VipSpec(
    level: 4,
    nameColor: Color(0xFFFF9A6B),
    nameFontWeight: FontWeight.w900,
    nameGradient: [Color(0xFFFFD978), Color(0xFFE0322B)],
    glowOpacity: 0.26,
    badgeGradient: [Color(0xFFFFD978), Color(0xFF9A6ED0)],
    badgeTextColor: Color(0xFFE4B5FF),
    badgeIcon: Icons.auto_awesome_rounded,
    bannerGradient: [Color(0xFFFFD978), Color(0xFF9A6ED0)],
    primaryColor: Color(0xFF9A6ED0),
    secondaryColor: Color(0xFFE4B5FF),
    glowColor: Color(0xFF9A6ED0),
    glowIntensity: 0.32,
    borderColor: Color(0xFF9A6ED0),
    borderWidth: 1.5,
    outerRingColor: Color(0x55CCA020),
    surfaceTint: Color(0xFF0C0516),
    bubbleGradient: [Color(0xFF130A22), Color(0xFF0C0516)],
    avatarRingColor: Color(0xFF9A6ED0),
    avatarRingWidth: 1.5,
    frameAsset: 'assets/images/vip_frames/vip4.png',
    micWaveColors: [Color(0xFF9A6ED0), Color(0xFFCCA020)],
    micWaveRingCount: 2,
    entryTier: VipEntryTier.premium,
    cardCornerRadius: 15,
    animIntensity: 0,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: true,
    hasProfileGlow: true,
  );

  // ── VIP 5 — premium deep gold ─────────────────────────────────────────────
  static const _s5 = VipSpec(
    level: 5,
    nameColor: Color(0xFFFFD15C),
    nameFontWeight: FontWeight.w900,
    nameGradient: [Color(0xFFFFE08A), Color(0xFFE0002B), Color(0xFFFFD15C)],
    glowOpacity: 0.30,
    badgeGradient: [Color(0xFFFFE08A), Color(0xFFE0A800)],
    badgeTextColor: Color(0xFF160B26),
    badgeIcon: Icons.diamond_rounded,
    bannerGradient: [Color(0xFFFFE08A), Color(0xFFE0A800)],
    primaryColor: Color(0xFFE0A800),
    secondaryColor: Color(0xFFFFD15C),
    glowColor: Color(0xFFE0A800),
    glowIntensity: 0.38,
    borderColor: Color(0xFFE0A800),
    borderWidth: 1.6,
    surfaceTint: Color(0xFF130A00),
    bubbleGradient: [Color(0xFF1E1200), Color(0xFF130A00)],
    avatarRingColor: Color(0xFFE0A800),
    avatarRingWidth: 1.8,
    frameAsset: 'assets/images/vip_frames/5.png',
    micWaveColors: [Color(0xFFE0A800), Color(0xFFFFD15C), Color(0xFFCCA020)],
    micWaveRingCount: 2,
    entryTier: VipEntryTier.luxury,
    cardCornerRadius: 15,
    animIntensity: 0,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: true,
    hasProfileGlow: true,
  );

  // ── VIP 6 — crimson + gold (silent entry) ─────────────────────────────────
  static const _s6 = VipSpec(
    level: 6,
    nameColor: Color(0xFFE4B5FF),
    nameFontWeight: FontWeight.w900,
    nameGradient: [Color(0xFFFFD978), Color(0xFF8B26D9)],
    glowOpacity: 0.30,
    badgeGradient: [Color(0xFFFFD978), Color(0xFFBB1A38)],
    badgeTextColor: Color(0xFFFF8FAF),
    badgeIcon: Icons.diamond_rounded,
    bannerGradient: [Color(0xFFFFD978), Color(0xFFBB1A38)],
    primaryColor: Color(0xFFBB1A38),
    secondaryColor: Color(0xFFFF8FAF),
    glowColor: Color(0xFFBB1A38),
    glowIntensity: 0.38,
    borderColor: Color(0xFFBB1A38),
    borderWidth: 1.8,
    outerRingColor: Color(0x55E0A800),
    surfaceTint: Color(0xFF120008),
    bubbleGradient: [Color(0xFF1C0010), Color(0xFF120008)],
    avatarRingColor: Color(0xFFBB1A38),
    avatarRingWidth: 1.8,
    frameAsset: 'assets/images/vip_frames/6.png',
    micWaveColors: [Color(0xFFBB1A38), Color(0xFFE0A800), Color(0xFFFF8FAF)],
    micWaveRingCount: 3,
    entryTier: VipEntryTier.luxury,
    cardCornerRadius: 16,
    animIntensity: 0,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: false, // silent entry
    hasProfileGlow: true,
  );

  // ── VIP 7 — sapphire + gold, animated (silent entry) ─────────────────────
  static const _s7 = VipSpec(
    level: 7,
    nameColor: Color(0xFF9BE8FF),
    nameFontWeight: FontWeight.w900,
    nameGradient: [Color(0xFFD8F6FF), Color(0xFFFFD978), Color(0xFF4CC9F0)],
    glowOpacity: 0.32,
    badgeGradient: [Color(0xFFFFD978), Color(0xFF1A5CE8)],
    badgeTextColor: Color(0xFF80CCFF),
    badgeIcon: Icons.workspace_premium_rounded,
    bannerGradient: [Color(0xFFFFD978), Color(0xFF1A5CE8)],
    primaryColor: Color(0xFF1A5CE8),
    secondaryColor: Color(0xFF80CCFF),
    glowColor: Color(0xFF1A5CE8),
    glowIntensity: 0.42,
    borderColor: Color(0xFF1A5CE8),
    borderWidth: 1.8,
    outerRingColor: Color(0x66E0A800),
    surfaceTint: Color(0xFF02061C),
    bubbleGradient: [Color(0xFF060C28), Color(0xFF02061C)],
    avatarRingColor: Color(0xFF1A5CE8),
    avatarRingWidth: 2.0,
    frameAsset: 'assets/images/vip_frames/7.png',
    micWaveColors: [Color(0xFF1A5CE8), Color(0xFFE0A800), Color(0xFF80CCFF)],
    micWaveRingCount: 3,
    entryTier: VipEntryTier.royal,
    cardCornerRadius: 16,
    animIntensity: 0.6,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: false, // silent entry
    hasProfileGlow: true,
  );

  // ── VIP 8 — amethyst + gold, animated (silent entry) ─────────────────────
  static const _s8 = VipSpec(
    level: 8,
    nameColor: Color(0xFFFFE9A8),
    nameFontWeight: FontWeight.w900,
    nameGradient: [Color(0xFFFFF3C4), Color(0xFFC8952D), Color(0xFF1A1320)],
    glowOpacity: 0.34,
    badgeGradient: [Color(0xFFFFD978), Color(0xFF8822D8)],
    badgeTextColor: Color(0xFFD9A8FF),
    badgeIcon: Icons.workspace_premium_rounded,
    bannerGradient: [Color(0xFFFFD978), Color(0xFF8822D8)],
    primaryColor: Color(0xFF8822D8),
    secondaryColor: Color(0xFFD9A8FF),
    glowColor: Color(0xFF8822D8),
    glowIntensity: 0.46,
    borderColor: Color(0xFF8822D8),
    borderWidth: 2.0,
    outerRingColor: Color(0x77FFD978),
    surfaceTint: Color(0xFF07001A),
    bubbleGradient: [Color(0xFF0E0028), Color(0xFF07001A)],
    avatarRingColor: Color(0xFF8822D8),
    avatarRingWidth: 2.0,
    frameAsset: 'assets/images/vip_frames/88.png',
    micWaveColors: [Color(0xFF8822D8), Color(0xFFFFD978), Color(0xFFD9A8FF)],
    micWaveRingCount: 3,
    entryTier: VipEntryTier.royal,
    cardCornerRadius: 16,
    animIntensity: 0.8,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: false, // silent entry
    hasProfileGlow: true,
  );

  // ── VIP 9 — imperial legendary, animated (silent entry) ──────────────────
  static const _s9 = VipSpec(
    level: 9,
    nameColor: Color(0xFFFFC857),
    nameFontWeight: FontWeight.w900,
    nameGradient: [Color(0xFFFFE08A), Color(0xFFFF4A2A), Color(0xFFE0002B)],
    glowOpacity: 0.38,
    badgeGradient: [Color(0xFFFFD978), Color(0xFFD00060), Color(0xFF8822D8)],
    badgeTextColor: Color(0xFFFF88CC),
    badgeIcon: Icons.local_fire_department_rounded,
    bannerGradient: [Color(0xFFFFD978), Color(0xFFD00060), Color(0xFF8822D8)],
    primaryColor: Color(0xFFD00060),
    secondaryColor: Color(0xFFFF88CC),
    glowColor: Color(0xFFD00060),
    glowIntensity: 0.52,
    borderColor: Color(0xFFD00060),
    borderWidth: 2.2,
    outerRingColor: Color(0x88FFD978),
    surfaceTint: Color(0xFF0A0008),
    bubbleGradient: [Color(0xFF180014), Color(0xFF0A0008)],
    avatarRingColor: Color(0xFFFFD978),
    avatarRingWidth: 2.2,
    frameAsset: 'assets/images/vip_frames/99.png',
    micWaveColors: [
      Color(0xFFD00060),
      Color(0xFFFFD978),
      Color(0xFF8822D8),
      Color(0xFFFF88CC),
    ],
    micWaveRingCount: 3,
    entryTier: VipEntryTier.legendary,
    cardCornerRadius: 16,
    animIntensity: 1.0,
    hasBadge: true,
    hasFrame: true,
    hasMicWave: true,
    hasEntranceEffect: false, // silent entry
    hasProfileGlow: true,
  );
}
