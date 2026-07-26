/// Frame System v2 — VIP 1–9 PLACEHOLDER tier art.
///
/// Original programmatic vector frames, one distinct identity per tier,
/// following docs/frames_v2/VIP_TIER_SPECS.md. These are temporary stand-ins
/// until the final bitmap assets are produced from the asset-generation
/// prompts (docs/frames_v2/ASSET_PROMPTS.md) — DO NOT treat them as final
/// production artwork.
///
/// Raster-friendly by design:
/// - no MaskFilter blur, no saveLayer, no shader per-notch — glow is layered
///   translucent strokes;
/// - the avatar opening stays ≥ 74% of the box (center never covered);
/// - tier recognizability at small sizes: palette + notch count == tier;
/// - static at [t] = 0; tiers 6+ accept an animation phase for accents.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SroodTierFramePalette {
  const SroodTierFramePalette({
    required this.base,
    required this.light,
    required this.dark,
    required this.accent,
    this.glowAlpha = 0.30,
  });

  final Color base;
  final Color light;
  final Color dark;
  final Color accent;
  final double glowAlpha;

  static SroodTierFramePalette of(int tier) => _palettes[tier.clamp(1, 9) - 1];

  static const List<SroodTierFramePalette> _palettes = [
    // VIP 1 — clean bronze, minimal glow.
    SroodTierFramePalette(
      base: Color(0xFFB87C36),
      light: Color(0xFFE8AE60),
      dark: Color(0xFF6E4318),
      accent: Color(0xFFF4D3A0),
      glowAlpha: 0.16,
    ),
    // VIP 2 — polished silver, small details.
    SroodTierFramePalette(
      base: Color(0xFFB9C2D3),
      light: Color(0xFFF2F5FB),
      dark: Color(0xFF6B7488),
      accent: Color(0xFFDCE4F2),
      glowAlpha: 0.20,
    ),
    // VIP 3 — royal gold, controlled light.
    SroodTierFramePalette(
      base: Color(0xFFD9A62B),
      light: Color(0xFFFFE9A8),
      dark: Color(0xFF8A6410),
      accent: Color(0xFFFFF3C9),
      glowAlpha: 0.26,
    ),
    // VIP 4 — emerald royal, premium corners.
    SroodTierFramePalette(
      base: Color(0xFF1E9E5A),
      light: Color(0xFF7BE8AC),
      dark: Color(0xFF0B5A32),
      accent: Color(0xFFF0C15A),
      glowAlpha: 0.28,
    ),
    // VIP 5 — ruby prestige.
    SroodTierFramePalette(
      base: Color(0xFFC81E3E),
      light: Color(0xFFFF7A8C),
      dark: Color(0xFF6E0E20),
      accent: Color(0xFFFFD978),
      glowAlpha: 0.32,
    ),
    // VIP 6 — sapphire, royal animated accents.
    SroodTierFramePalette(
      base: Color(0xFF1A5CE8),
      light: Color(0xFF80CCFF),
      dark: Color(0xFF0C2C74),
      accent: Color(0xFFD8F6FF),
      glowAlpha: 0.34,
    ),
    // VIP 7 — imperial purple, particles.
    SroodTierFramePalette(
      base: Color(0xFF8B26D9),
      light: Color(0xFFE4B5FF),
      dark: Color(0xFF43106E),
      accent: Color(0xFFF0C15A),
      glowAlpha: 0.36,
    ),
    // VIP 8 — black diamond energy.
    SroodTierFramePalette(
      base: Color(0xFF23202E),
      light: Color(0xFF9BE8FF),
      dark: Color(0xFF0C0A12),
      accent: Color(0xFFDFF8FF),
      glowAlpha: 0.38,
    ),
    // VIP 9 — Srood mythic: gold, violet, black.
    SroodTierFramePalette(
      base: Color(0xFFF0C15A),
      light: Color(0xFFFFE9A8),
      dark: Color(0xFF120722),
      accent: Color(0xFF8B26D9),
      glowAlpha: 0.42,
    ),
  ];
}

/// Paints the placeholder frame for [tier] into a square canvas.
/// [t] is an animation phase in 0..1; pass 0 for a fully static frame.
class SroodTierFramePainter extends CustomPainter {
  const SroodTierFramePainter({
    required this.tier,
    this.t = 0.0,
    this.compact = false,
  });

  final int tier;
  final double t;

  /// Compact seats: thinner strokes, no fine detail pass.
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final level = tier.clamp(1, 9);
    final p = SroodTierFramePalette.of(level);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // Ring radius keeps the opening ≥ 74% of the box.
    final ringR = radius * 0.88;
    final stroke = math.max(
      compact ? 1.6 : 2.2,
      radius * (compact ? 0.055 : 0.075),
    );

    // 1. Glow illusion — two translucent strokes, no blur filter.
    if (p.glowAlpha > 0) {
      final glowOuter = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.4
        ..color = p.base.withValues(alpha: p.glowAlpha * 0.45);
      canvas.drawCircle(center, ringR, glowOuter);
      final glowInner = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.6
        ..color = p.light.withValues(alpha: p.glowAlpha * 0.35);
      canvas.drawCircle(center, ringR, glowInner);
    }

    // 2. Main metal ring — sweep gradient base + dark rim + light hairline.
    final rect = Rect.fromCircle(center: center, radius: ringR);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.25
        ..color = p.dark,
    );
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          colors: [p.dark, p.light, p.base, p.light, p.dark],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    if (!compact) {
      canvas.drawCircle(
        center,
        ringR - stroke * 0.85,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, stroke * 0.22)
          ..color = p.light.withValues(alpha: 0.75),
      );
    }

    // 3. Tier motif — notch count equals the tier so every level stays
    //    recognizable even at room-seat sizes.
    _paintTierNotches(canvas, center, ringR, stroke, level, p);

    // 4. Tier-specific signature treatments.
    if (level == 4) _paintCornerGems(canvas, center, ringR, stroke, p);
    if (level == 5 && !compact)
      _paintApexGem(canvas, center, ringR, stroke, p, sides: 4);
    if (level >= 6)
      _paintAnimatedAccents(canvas, center, ringR, stroke, level, p);
    if (level == 8) _paintEnergyArcs(canvas, center, ringR, stroke, p);
    if (level == 9) _paintMythicCrest(canvas, center, ringR, stroke, p);
  }

  void _paintTierNotches(
    Canvas canvas,
    Offset center,
    double ringR,
    double stroke,
    int level,
    SroodTierFramePalette p,
  ) {
    final notchPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = p.accent;
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, stroke * 0.25)
      ..color = p.dark;
    final notchSize = math.max(compact ? 1.6 : 2.2, stroke * 0.62);

    // Notches sit along the top arc, symmetric around 12 o'clock.
    const arcSpan = math.pi * 0.62;
    for (var i = 0; i < level; i++) {
      final f = level == 1 ? 0.5 : i / (level - 1);
      final angle = -math.pi / 2 - arcSpan / 2 + arcSpan * f;
      final at = Offset(
        center.dx + math.cos(angle) * ringR,
        center.dy + math.sin(angle) * ringR,
      );
      final path = Path()
        ..moveTo(at.dx, at.dy - notchSize)
        ..lineTo(at.dx + notchSize, at.dy)
        ..lineTo(at.dx, at.dy + notchSize)
        ..lineTo(at.dx - notchSize, at.dy)
        ..close();
      canvas.drawPath(path, notchPaint);
      if (!compact) canvas.drawPath(path, rimPaint);
    }
  }

  void _paintCornerGems(
    Canvas canvas,
    Offset center,
    double ringR,
    double stroke,
    SroodTierFramePalette p,
  ) {
    // Emerald royal: four gold corner details at the diagonals.
    final gemPaint = Paint()..color = p.accent;
    for (final angle in const [
      math.pi * 0.25,
      math.pi * 0.75,
      math.pi * 1.25,
      math.pi * 1.75,
    ]) {
      final at = Offset(
        center.dx + math.cos(angle) * ringR,
        center.dy + math.sin(angle) * ringR,
      );
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle + math.pi / 4);
      final s = math.max(compact ? 2.0 : 2.6, stroke * 0.8);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: s * 1.7, height: s * 1.7),
        gemPaint,
      );
      canvas.restore();
    }
  }

  void _paintApexGem(
    Canvas canvas,
    Offset center,
    double ringR,
    double stroke,
    SroodTierFramePalette p, {
    required int sides,
  }) {
    // Faceted gem at 12 o'clock.
    final at = Offset(center.dx, center.dy - ringR);
    final s = math.max(3.0, stroke * 1.15);
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / sides;
      final v = Offset(at.dx + math.cos(a) * s, at.dy + math.sin(a) * s);
      i == 0 ? path.moveTo(v.dx, v.dy) : path.lineTo(v.dx, v.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [p.light, p.base],
        ).createShader(Rect.fromCircle(center: at, radius: s)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, stroke * 0.25)
        ..color = p.accent,
    );
  }

  void _paintAnimatedAccents(
    Canvas canvas,
    Offset center,
    double ringR,
    double stroke,
    int level,
    SroodTierFramePalette p,
  ) {
    // Orbiting accent dots; static composition at t == 0.
    final count = level >= 8 ? 4 : 3;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      final phase = (t + i / count) % 1.0;
      final angle = phase * 2 * math.pi + math.pi / 6;
      final pulse = 0.55 + 0.45 * math.sin(phase * 2 * math.pi);
      dotPaint.color = p.accent.withValues(alpha: 0.35 + 0.5 * pulse);
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(angle) * ringR,
          center.dy + math.sin(angle) * ringR,
        ),
        math.max(1.4, stroke * 0.45) * (0.8 + 0.4 * pulse),
        dotPaint,
      );
    }
  }

  void _paintEnergyArcs(
    Canvas canvas,
    Offset center,
    double ringR,
    double stroke,
    SroodTierFramePalette p,
  ) {
    // Black diamond: two ice-blue energy arcs sweeping the ring.
    final sweep = math.pi * 0.42;
    for (var i = 0; i < 2; i++) {
      final start = t * 2 * math.pi + i * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringR),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.2, stroke * 0.5)
          ..color = p.light.withValues(alpha: 0.85),
      );
    }
  }

  void _paintMythicCrest(
    Canvas canvas,
    Offset center,
    double ringR,
    double stroke,
    SroodTierFramePalette p,
  ) {
    // Srood mythic: violet under-ring + gold over-ring + apex crest that
    // echoes the Srood owl silhouette as three simple arcs (original mark).
    canvas.drawCircle(
      center,
      ringR + stroke * 0.9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, stroke * 0.4)
        ..color = p.accent.withValues(alpha: 0.85),
    );

    final apex = Offset(center.dx, center.dy - ringR);
    final s = math.max(3.5, stroke * 1.3);
    final crest = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.1, stroke * 0.4)
      ..color = p.light;
    // Center arc (head) + two side arcs (wings).
    canvas.drawArc(
      Rect.fromCircle(center: apex.translate(0, -s * 0.4), radius: s * 0.8),
      math.pi * 1.15,
      math.pi * 0.7,
      false,
      crest,
    );
    for (final dir in const [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCircle(
          center: apex.translate(dir * s * 1.2, s * 0.15),
          radius: s * 0.7,
        ),
        dir < 0 ? math.pi * 0.9 : math.pi * 1.4,
        math.pi * 0.7,
        false,
        crest,
      );
    }
    // Black backing diamond behind the crest keeps it readable on light
    // avatars without covering the face (sits on the rim).
    final backing = Path()
      ..moveTo(apex.dx, apex.dy - s * 1.15)
      ..lineTo(apex.dx + s * 1.05, apex.dy)
      ..lineTo(apex.dx, apex.dy + s * 1.15)
      ..lineTo(apex.dx - s * 1.05, apex.dy)
      ..close();
    canvas.drawPath(
      backing,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.9, stroke * 0.3)
        ..color = p.dark,
    );
  }

  @override
  bool shouldRepaint(covariant SroodTierFramePainter old) =>
      old.tier != tier || old.t != t || old.compact != compact;
}
