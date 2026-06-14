import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VipEntryTier — drives entry banner style and animation richness
// ─────────────────────────────────────────────────────────────────────────────

enum VipEntryTier {
  none,       // VIP 0 — no banner
  sparkle,    // VIP 1–2 — soft glow, compact banner
  glow,       // VIP 3 — premium glow slide-in
  premium,    // VIP 4 — slide-in with aura
  luxury,     // VIP 5–6 — luxury entrance, rich glow
  royal,      // VIP 7–8 — full-width royal animated entrance
  legendary,  // VIP 9 — cinematic legendary banner
}

// ─────────────────────────────────────────────────────────────────────────────
// VipPrestige — single data class for ALL visual properties of a VIP level
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

  /// VIP level 0–9.
  final int level;

  /// Main accent colour (borders, rings, wave).
  final Color primaryColor;

  /// Secondary accent (inner highlights, shimmer).
  final Color secondaryColor;

  /// Glow / shadow colour.
  final Color glowColor;

  /// 2–3-stop gradient for badges and entry banners.
  final List<Color> gradientColors;

  /// Chat card border colour.
  final Color borderColor;

  /// Chat card border width in logical pixels.
  final double borderWidth;

  /// Spread-shadow outer-ring colour (null = no secondary ring).
  final Color? outerRingColor;

  /// Dark surface tint — solid background for compact containers.
  final Color surfaceTint;

  /// Two-colour list for the chat-bubble linear gradient.
  final List<Color> bubbleGradient;

  /// Username text colour.
  final Color nameColor;

  /// Username font weight.
  final FontWeight nameFontWeight;

  /// Glow intensity 0–1 (scales blur radius and alpha).
  final double glowIntensity;

  /// Animation intensity 0–1 (0 = no animation).
  final double animIntensity;

  /// Room entry animation tier.
  final VipEntryTier entryTier;

  /// Corner radius for chat cards (grows with level).
  final double cardCornerRadius;

  /// Avatar ring colour.
  final Color avatarRingColor;

  /// Avatar ring width in logical pixels (0 = no ring).
  final double avatarRingWidth;

  /// Badge background gradient colours.
  final List<Color> badgeGradient;

  /// Badge label text colour.
  final Color badgeTextColor;

  /// Ordered colours for mic-wave animation rings.
  final List<Color> micWaveColors;

  /// Number of concentric mic-wave rings.
  final int micWaveRingCount;

  // ── Derived helpers ──────────────────────────────────────────────────────

  String get badgeLabel => level <= 0 ? '' : 'VIP $level';
  bool get hasAnimation => animIntensity > 0;
  bool get isElite => level >= 7;
  bool get isLegendary => level == 9;

  /// Foreground text colour on the entry banner background.
  Color get entryTextColor =>
      isElite ? Colors.white : const Color(0xFF160B26);

  /// Duration the entry banner stays on screen.
  Duration get entryBannerDuration => switch (entryTier) {
        VipEntryTier.legendary => const Duration(milliseconds: 4000),
        VipEntryTier.royal => const Duration(milliseconds: 3500),
        VipEntryTier.luxury => const Duration(milliseconds: 3000),
        _ => const Duration(milliseconds: 2500),
      };

  /// Build BoxShadow glow list. [pulseFactor] (0–1) scales the effect —
  /// pass your animation value here for VIP 7–9 pulsing cards.
  List<BoxShadow> buildGlowShadows({double pulseFactor = 1.0}) {
    if (glowIntensity <= 0) return const [];

    final alpha = ((0.18 + glowIntensity * 0.35) * pulseFactor).clamp(0.0, 0.65);
    final blur = 10.0 + glowIntensity * 22.0;
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
          color: const Color(0xFFFFD978)
              .withValues(alpha: 0.22 * pulseFactor),
          blurRadius: 20,
          spreadRadius: -2,
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VipVisualResolver — call resolve(level) from anywhere in the app
// ─────────────────────────────────────────────────────────────────────────────

class VipVisualResolver {
  const VipVisualResolver._();

  static VipPrestige resolve(int rawLevel) =>
      _table[rawLevel.clamp(0, 9)];

  // Alias used by older code referencing VipPrestigeLevel.
  static VipPrestige forLevel(int level) => resolve(level);

  static const List<VipPrestige> _table = [
    _p0, _p1, _p2, _p3, _p4, _p5, _p6, _p7, _p8, _p9,
  ];

  // ── VIP 0 — clean, no luxury ───────────────────────────────────────────────
  static const _p0 = VipPrestige(
    level: 0,
    primaryColor: Color(0xFFAAAAAA),
    secondaryColor: Color(0xFF888888),
    glowColor: Color(0x00000000),
    gradientColors: [Color(0xFF2A2A2A), Color(0xFF383838)],
    borderColor: Color(0x1AFFFFFF),
    borderWidth: 0.8,
    surfaceTint: Color(0xFF101014),
    bubbleGradient: [Color(0xFF101014), Color(0xFF101014)],
    nameColor: Colors.white,
    nameFontWeight: FontWeight.w700,
    glowIntensity: 0,
    animIntensity: 0,
    entryTier: VipEntryTier.none,
    cardCornerRadius: 14,
    avatarRingColor: Color(0x22FFFFFF),
    avatarRingWidth: 0,
    badgeGradient: [Color(0xFF2A2A2A), Color(0xFF444444)],
    badgeTextColor: Color(0xB3FFFFFF),
    micWaveColors: [Color(0xFF4ADE80)],
    micWaveRingCount: 1,
  );

  // ── VIP 1 — champagne bronze ───────────────────────────────────────────────
  static const _p1 = VipPrestige(
    level: 1,
    primaryColor: Color(0xFFB87C36),
    secondaryColor: Color(0xFFE8AE60),
    glowColor: Color(0xFFB87C36),
    gradientColors: [Color(0xFFE8AE60), Color(0xFFB87C36)],
    borderColor: Color(0xFFB87C36),
    borderWidth: 1.0,
    surfaceTint: Color(0xFF120D04),
    bubbleGradient: [Color(0xFF120D04), Color(0xFF120D04)],
    nameColor: Color(0xFFFFD978),
    nameFontWeight: FontWeight.w800,
    glowIntensity: 0.22,
    animIntensity: 0,
    entryTier: VipEntryTier.sparkle,
    cardCornerRadius: 14,
    avatarRingColor: Color(0xFFB87C36),
    avatarRingWidth: 1.2,
    badgeGradient: [Color(0xFFE8AE60), Color(0xFFB87C36)],
    badgeTextColor: Color(0xFF160B26),
    micWaveColors: [Color(0xFFB87C36)],
    micWaveRingCount: 1,
  );

  // ── VIP 2 — rose gold ─────────────────────────────────────────────────────
  static const _p2 = VipPrestige(
    level: 2,
    primaryColor: Color(0xFFCE6E66),
    secondaryColor: Color(0xFFFFB0A6),
    glowColor: Color(0xFFCE6E66),
    gradientColors: [Color(0xFFFFCFB8), Color(0xFFCE6E66)],
    borderColor: Color(0xFFCE6E66),
    borderWidth: 1.2,
    surfaceTint: Color(0xFF140808),
    bubbleGradient: [Color(0xFF1C0C0A), Color(0xFF140808)],
    nameColor: Color(0xFFFFB0A6),
    nameFontWeight: FontWeight.w800,
    glowIntensity: 0.26,
    animIntensity: 0,
    entryTier: VipEntryTier.sparkle,
    cardCornerRadius: 14,
    avatarRingColor: Color(0xFFCE6E66),
    avatarRingWidth: 1.3,
    badgeGradient: [Color(0xFFFFCFB8), Color(0xFFCE6E66)],
    badgeTextColor: Color(0xFF160B26),
    micWaveColors: [Color(0xFFCE6E66), Color(0xFFFFB0A6)],
    micWaveRingCount: 1,
  );

  // ── VIP 3 — warm gold ─────────────────────────────────────────────────────
  static const _p3 = VipPrestige(
    level: 3,
    primaryColor: Color(0xFFCCA020),
    secondaryColor: Color(0xFFFFD978),
    glowColor: Color(0xFFCCA020),
    gradientColors: [Color(0xFFFFE3A3), Color(0xFFCCA020)],
    borderColor: Color(0xFFCCA020),
    borderWidth: 1.4,
    surfaceTint: Color(0xFF130F00),
    bubbleGradient: [Color(0xFF1A1200), Color(0xFF130F00)],
    nameColor: Color(0xFFFFD978),
    nameFontWeight: FontWeight.w900,
    glowIntensity: 0.30,
    animIntensity: 0,
    entryTier: VipEntryTier.glow,
    cardCornerRadius: 15,
    avatarRingColor: Color(0xFFCCA020),
    avatarRingWidth: 1.4,
    badgeGradient: [Color(0xFFFFE3A3), Color(0xFFCCA020)],
    badgeTextColor: Color(0xFF160B26),
    micWaveColors: [Color(0xFFCCA020), Color(0xFFFFD978)],
    micWaveRingCount: 2,
  );

  // ── VIP 4 — gold + royal purple ───────────────────────────────────────────
  static const _p4 = VipPrestige(
    level: 4,
    primaryColor: Color(0xFF9A6ED0),
    secondaryColor: Color(0xFFE4B5FF),
    glowColor: Color(0xFF9A6ED0),
    gradientColors: [Color(0xFFFFD978), Color(0xFF9A6ED0)],
    borderColor: Color(0xFF9A6ED0),
    borderWidth: 1.5,
    outerRingColor: Color(0x55CCA020),
    surfaceTint: Color(0xFF0C0516),
    bubbleGradient: [Color(0xFF130A22), Color(0xFF0C0516)],
    nameColor: Color(0xFFE4B5FF),
    nameFontWeight: FontWeight.w900,
    glowIntensity: 0.32,
    animIntensity: 0,
    entryTier: VipEntryTier.premium,
    cardCornerRadius: 15,
    avatarRingColor: Color(0xFF9A6ED0),
    avatarRingWidth: 1.5,
    badgeGradient: [Color(0xFFFFD978), Color(0xFF9A6ED0)],
    badgeTextColor: Color(0xFFE4B5FF),
    micWaveColors: [Color(0xFF9A6ED0), Color(0xFFCCA020)],
    micWaveRingCount: 2,
  );

  // ── VIP 5 — premium deep gold ─────────────────────────────────────────────
  static const _p5 = VipPrestige(
    level: 5,
    primaryColor: Color(0xFFE0A800),
    secondaryColor: Color(0xFFFFD15C),
    glowColor: Color(0xFFE0A800),
    gradientColors: [Color(0xFFFFE08A), Color(0xFFE0A800)],
    borderColor: Color(0xFFE0A800),
    borderWidth: 1.6,
    surfaceTint: Color(0xFF130A00),
    bubbleGradient: [Color(0xFF1E1200), Color(0xFF130A00)],
    nameColor: Color(0xFFFFD15C),
    nameFontWeight: FontWeight.w900,
    glowIntensity: 0.38,
    animIntensity: 0,
    entryTier: VipEntryTier.luxury,
    cardCornerRadius: 15,
    avatarRingColor: Color(0xFFE0A800),
    avatarRingWidth: 1.8,
    badgeGradient: [Color(0xFFFFE08A), Color(0xFFE0A800)],
    badgeTextColor: Color(0xFF160B26),
    micWaveColors: [Color(0xFFE0A800), Color(0xFFFFD15C), Color(0xFFCCA020)],
    micWaveRingCount: 2,
  );

  // ── VIP 6 — crimson + gold ────────────────────────────────────────────────
  static const _p6 = VipPrestige(
    level: 6,
    primaryColor: Color(0xFFBB1A38),
    secondaryColor: Color(0xFFFF8FAF),
    glowColor: Color(0xFFBB1A38),
    gradientColors: [Color(0xFFFFD978), Color(0xFFBB1A38)],
    borderColor: Color(0xFFBB1A38),
    borderWidth: 1.8,
    outerRingColor: Color(0x55E0A800),
    surfaceTint: Color(0xFF120008),
    bubbleGradient: [Color(0xFF1C0010), Color(0xFF120008)],
    nameColor: Color(0xFF5DDCFF),
    nameFontWeight: FontWeight.w900,
    glowIntensity: 0.38,
    animIntensity: 0,
    entryTier: VipEntryTier.luxury,
    cardCornerRadius: 16,
    avatarRingColor: Color(0xFFBB1A38),
    avatarRingWidth: 1.8,
    badgeGradient: [Color(0xFFFFD978), Color(0xFFBB1A38)],
    badgeTextColor: Color(0xFFFF8FAF),
    micWaveColors: [Color(0xFFBB1A38), Color(0xFFE0A800), Color(0xFFFF8FAF)],
    micWaveRingCount: 3,
  );

  // ── VIP 7 — sapphire + gold (animated) ───────────────────────────────────
  static const _p7 = VipPrestige(
    level: 7,
    primaryColor: Color(0xFF1A5CE8),
    secondaryColor: Color(0xFF80CCFF),
    glowColor: Color(0xFF1A5CE8),
    gradientColors: [Color(0xFFFFD978), Color(0xFF1A5CE8)],
    borderColor: Color(0xFF1A5CE8),
    borderWidth: 1.8,
    outerRingColor: Color(0x66E0A800),
    surfaceTint: Color(0xFF02061C),
    bubbleGradient: [Color(0xFF060C28), Color(0xFF02061C)],
    nameColor: Color(0xFFC875FF),
    nameFontWeight: FontWeight.w900,
    glowIntensity: 0.42,
    animIntensity: 0.6,
    entryTier: VipEntryTier.royal,
    cardCornerRadius: 16,
    avatarRingColor: Color(0xFF1A5CE8),
    avatarRingWidth: 2.0,
    badgeGradient: [Color(0xFFFFD978), Color(0xFF1A5CE8)],
    badgeTextColor: Color(0xFF80CCFF),
    micWaveColors: [Color(0xFF1A5CE8), Color(0xFFE0A800), Color(0xFF80CCFF)],
    micWaveRingCount: 3,
  );

  // ── VIP 8 — amethyst + gold (animated) ───────────────────────────────────
  static const _p8 = VipPrestige(
    level: 8,
    primaryColor: Color(0xFF8822D8),
    secondaryColor: Color(0xFFD9A8FF),
    glowColor: Color(0xFF8822D8),
    gradientColors: [Color(0xFFFFD978), Color(0xFF8822D8)],
    borderColor: Color(0xFF8822D8),
    borderWidth: 2.0,
    outerRingColor: Color(0x77FFD978),
    surfaceTint: Color(0xFF07001A),
    bubbleGradient: [Color(0xFF0E0028), Color(0xFF07001A)],
    nameColor: Color(0xFFFFB44C),
    nameFontWeight: FontWeight.w900,
    glowIntensity: 0.46,
    animIntensity: 0.8,
    entryTier: VipEntryTier.royal,
    cardCornerRadius: 16,
    avatarRingColor: Color(0xFF8822D8),
    avatarRingWidth: 2.0,
    badgeGradient: [Color(0xFFFFD978), Color(0xFF8822D8)],
    badgeTextColor: Color(0xFFD9A8FF),
    micWaveColors: [Color(0xFF8822D8), Color(0xFFFFD978), Color(0xFFD9A8FF)],
    micWaveRingCount: 3,
  );

  // ── VIP 9 — imperial legendary (animated) ────────────────────────────────
  static const _p9 = VipPrestige(
    level: 9,
    primaryColor: Color(0xFFD00060),
    secondaryColor: Color(0xFFFF88CC),
    glowColor: Color(0xFFD00060),
    gradientColors: [Color(0xFFFFD978), Color(0xFFD00060), Color(0xFF8822D8)],
    borderColor: Color(0xFFD00060),
    borderWidth: 2.2,
    outerRingColor: Color(0x88FFD978),
    surfaceTint: Color(0xFF0A0008),
    bubbleGradient: [Color(0xFF180014), Color(0xFF0A0008)],
    nameColor: Color(0xFF75FFE8),
    nameFontWeight: FontWeight.w900,
    glowIntensity: 0.52,
    animIntensity: 1.0,
    entryTier: VipEntryTier.legendary,
    cardCornerRadius: 16,
    avatarRingColor: Color(0xFFFFD978),
    avatarRingWidth: 2.2,
    badgeGradient: [Color(0xFFFFD978), Color(0xFFD00060), Color(0xFF8822D8)],
    badgeTextColor: Color(0xFFFF88CC),
    micWaveColors: [
      Color(0xFFD00060),
      Color(0xFFFFD978),
      Color(0xFF8822D8),
      Color(0xFFFF88CC),
    ],
    micWaveRingCount: 3,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// VipAvatarHalo — reusable halo decoration for avatars at any size
// ─────────────────────────────────────────────────────────────────────────────

/// Returns BoxDecoration glow shadows suitable for a circular avatar at
/// the given [vipLevel]. Safe to call with level 0 (returns empty list).
List<BoxShadow> vipAvatarHaloShadows(int vipLevel, {double pulseFactor = 1.0}) {
  final prestige = VipVisualResolver.resolve(vipLevel);
  return prestige.buildGlowShadows(pulseFactor: pulseFactor);
}

// ─────────────────────────────────────────────────────────────────────────────
// VipMicWaveRing — animated expanding ring for speaking mic seats
// ─────────────────────────────────────────────────────────────────────────────

/// Mic-wave animation widget. Place inside a Stack with clipBehavior:Clip.none.
/// Has [size: Size.zero] so it doesn't change layout; rings paint outward.
class VipMicWaveRing extends StatefulWidget {
  const VipMicWaveRing({
    required this.vipLevel,
    required this.isActive,
    required this.isHost,
    required this.outerSize,
    super.key,
  });

  final int vipLevel;

  /// True when the user is NOT muted — the ring animates.
  final bool isActive;

  final bool isHost;

  /// Layout diameter of the avatar circle (outerSize from the seat bubble).
  final double outerSize;

  @override
  State<VipMicWaveRing> createState() => _VipMicWaveRingState();
}

class _VipMicWaveRingState extends State<VipMicWaveRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  Duration _period() {
    final lvl = widget.vipLevel;
    if (lvl >= 9) return const Duration(milliseconds: 1100);
    if (lvl >= 7) return const Duration(milliseconds: 1400);
    if (lvl >= 5) return const Duration(milliseconds: 1700);
    if (lvl >= 3) return const Duration(milliseconds: 2000);
    return const Duration(milliseconds: 2300);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _period());
    if (widget.isActive) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(VipMicWaveRing old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      if (widget.isActive) {
        _ctrl.repeat();
      } else {
        _ctrl
          ..stop()
          ..reset();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prestige = VipVisualResolver.resolve(widget.vipLevel);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => CustomPaint(
          size: Size.zero,
          painter: _MicWavePainter(
            progress: widget.isActive ? _ctrl.value : 0.0,
            prestige: prestige,
            isHost: widget.isHost,
            outerSize: widget.outerSize,
            isActive: widget.isActive,
          ),
        ),
      ),
    );
  }
}

class _MicWavePainter extends CustomPainter {
  const _MicWavePainter({
    required this.progress,
    required this.prestige,
    required this.isHost,
    required this.outerSize,
    required this.isActive,
  });

  final double progress;
  final VipPrestige prestige;
  final bool isHost;
  final double outerSize;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final level = prestige.level;
    if (!isActive && level <= 0 && !isHost) return;

    const center = Offset.zero;
    final baseRadius = outerSize / 2;

    if (!isActive) {
      // Static halo for non-speaking VIP / host seats.
      final haloColor = level > 0
          ? prestige.glowColor.withValues(alpha: prestige.glowIntensity * 0.28)
          : const Color(0xFFF0C15A).withValues(alpha: 0.14);
      canvas.drawCircle(
        center,
        baseRadius + 3,
        Paint()
          ..color = haloColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      return;
    }

    final colors = prestige.micWaveColors;
    final ringCount = prestige.micWaveRingCount;
    final maxExpand = baseRadius * (0.38 + level * 0.04).clamp(0.30, 0.72);
    final strokeW = (1.0 + level * 0.20).clamp(1.0, 2.8);
    final blurSigma = level >= 5 ? (1.5 + level * 0.28).clamp(1.5, 4.0) : 0.0;

    for (int i = 0; i < ringCount; i++) {
      final stagger = i / ringCount;
      final p = (progress + stagger) % 1.0;
      final eased = Curves.easeOut.transform(p);

      final radius = baseRadius + maxExpand * eased;
      final alpha = (1.0 - eased) * 0.80;
      if (alpha < 0.02) continue;

      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW * (1.0 - eased * 0.45);

      if (blurSigma > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
      }
      canvas.drawCircle(center, radius, paint);
    }

    // Sparkle dots for VIP 7+
    if (level >= 7 && progress > 0.05) {
      final sparkleCount = level == 9 ? 6 : 4;
      final spR = baseRadius * (0.80 + progress * 0.28);
      final spAlpha = (0.65 - progress * 0.55).clamp(0.0, 0.65);
      final spSize = (1.4 + level * 0.14).clamp(1.4, 2.6);
      final spColor = colors[math.min(1, colors.length - 1)]
          .withValues(alpha: spAlpha);
      final spPaint = Paint()
        ..color = spColor
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

      for (int i = 0; i < sparkleCount; i++) {
        final angle =
            (i / sparkleCount) * 2 * math.pi + progress * math.pi;
        canvas.drawCircle(
          Offset(spR * math.cos(angle), spR * math.sin(angle)),
          spSize,
          spPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MicWavePainter old) =>
      old.progress != progress ||
      old.isActive != isActive ||
      old.prestige.level != prestige.level ||
      old.outerSize != outerSize;
}
