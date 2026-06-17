import 'dart:math' as math;
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

// ─────────────────────────────────────────────────────────────────────────────
// VipAvatarHalo — glow shadows for avatar decorations
// ─────────────────────────────────────────────────────────────────────────────

List<BoxShadow> vipAvatarHaloShadows(int vipLevel, {double pulseFactor = 1.0}) {
  final prestige = VipVisualResolver.resolve(vipLevel);
  return prestige.buildGlowShadows(pulseFactor: pulseFactor);
}

// ─────────────────────────────────────────────────────────────────────────────
// VipMicWaveRing — animated expanding ring for speaking mic seats
// ─────────────────────────────────────────────────────────────────────────────

class VipMicWaveRing extends StatefulWidget {
  const VipMicWaveRing({
    required this.vipLevel,
    required this.isActive,
    required this.isHost,
    required this.outerSize,
    super.key,
  });

  final int vipLevel;
  final bool isActive;
  final bool isHost;
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
    final spec = VipSpecResolver.resolve(widget.vipLevel);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => CustomPaint(
          size: Size.zero,
          painter: _MicWavePainter(
            progress: widget.isActive ? _ctrl.value : 0.0,
            spec: spec,
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
    required this.spec,
    required this.isHost,
    required this.outerSize,
    required this.isActive,
  });

  final double progress;
  final VipSpec spec;
  final bool isHost;
  final double outerSize;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final level = spec.level;
    if (!isActive && level <= 0 && !isHost) return;

    const center = Offset.zero;
    final baseRadius = outerSize / 2;

    if (!isActive) {
      final haloColor = level > 0
          ? spec.glowColor.withValues(alpha: spec.glowIntensity * 0.28)
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

    final colors    = spec.micWaveColors;
    final ringCount = spec.micWaveRingCount;
    final maxExpand = baseRadius * (0.38 + level * 0.04).clamp(0.30, 0.72);
    final strokeW   = (1.0 + level * 0.20).clamp(1.0, 2.8);
    final blurSigma = level >= 5 ? (1.5 + level * 0.28).clamp(1.5, 4.0) : 0.0;

    for (int i = 0; i < ringCount; i++) {
      final stagger = i / ringCount;
      final p       = (progress + stagger) % 1.0;
      final eased   = Curves.easeOut.transform(p);

      final radius = baseRadius + maxExpand * eased;
      final alpha  = (1.0 - eased) * 0.80;
      if (alpha < 0.02) continue;

      final paint = Paint()
        ..color       = colors[i % colors.length].withValues(alpha: alpha)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeW * (1.0 - eased * 0.45);

      if (blurSigma > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
      }
      canvas.drawCircle(center, radius, paint);
    }

    // Sparkle dots for VIP 7+
    if (level >= 7 && progress > 0.05) {
      final sparkleCount = level == 9 ? 6 : 4;
      final spR          = baseRadius * (0.80 + progress * 0.28);
      final spAlpha      = (0.65 - progress * 0.55).clamp(0.0, 0.65);
      final spSize       = (1.4 + level * 0.14).clamp(1.4, 2.6);
      final spColor      = colors[math.min(1, colors.length - 1)]
          .withValues(alpha: spAlpha);
      final spPaint = Paint()
        ..color      = spColor
        ..style      = PaintingStyle.fill
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
      old.spec.level != spec.level ||
      old.outerSize != outerSize;
}
