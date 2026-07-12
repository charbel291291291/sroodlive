import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Crash Rocket v2 visual language: Srood Live deep purple space, electric
/// blue + cyan glow. All artwork is original (procedural painters — no
/// external or copied game assets).
abstract final class CrashV2Palette {
  static const bgTop = Color(0xFF1B0E3A);
  static const bgMid = Color(0xFF120A28);
  static const bgBottom = Color(0xFF070313);
  static const panel = Color(0xFF171038);
  static const panelBorder = Color(0xFF2E2260);
  static const electric = Color(0xFF28C7FA);
  static const cyanGlow = Color(0xFF67E8F9);
  static const purple = Color(0xFF8B5CF6);
  static const gold = Color(0xFFF4C95D);
  static const green = Color(0xFF4ADE80);
  static const red = Color(0xFFF87171);
  static const textDim = Color(0xFFB9A8E0);

  static Color multiplierColor(double m) {
    if (m < 1.5) return const Color(0xFF9CA3AF);
    if (m < 2) return electric;
    if (m < 5) return green;
    if (m < 10) return gold;
    return const Color(0xFFF472B6);
  }
}

/// Twinkling starfield + drifting nebula dots. Deterministic from a seed so
/// repaints stay cheap and stable.
class StarfieldPainter extends CustomPainter {
  StarfieldPainter({required this.progress});

  /// 0..1 looping animation progress.
  final double progress;

  static final List<_Star> _stars = _buildStars();

  static List<_Star> _buildStars() {
    final rng = math.Random(7);
    return List.generate(90, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 0.4 + rng.nextDouble() * 1.4,
        phase: rng.nextDouble() * math.pi * 2,
        speed: 0.15 + rng.nextDouble() * 0.5,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final star in _stars) {
      final twinkle =
          0.35 +
          0.65 *
              (0.5 +
                  0.5 *
                      math.sin(
                        star.phase + progress * math.pi * 2 * star.speed,
                      ));
      paint.color = Colors.white.withValues(alpha: 0.5 * twinkle);
      final dy = (star.y + progress * 0.02 * star.speed) % 1.0;
      canvas.drawCircle(
        Offset(star.x * size.width, dy * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.speed,
  });
  final double x;
  final double y;
  final double radius;
  final double phase;
  final double speed;
}

/// The rocket flight scene: an exponential trail, glowing rocket, exhaust
/// flame while flying, and an explosion burst when crashed.
class RocketFlightPainter extends CustomPainter {
  RocketFlightPainter({
    required this.multiplier,
    required this.maxVisualMultiplier,
    required this.crashed,
    required this.crashProgress,
    required this.idle,
  });

  final double multiplier;
  final double maxVisualMultiplier;
  final bool crashed;

  /// 0..1 explosion animation progress once crashed.
  final double crashProgress;

  /// True while no flight is in progress (waiting/betting): rocket parked.
  final bool idle;

  Offset _positionFor(double m, Size size) {
    // Normalize multiplier onto the visible window using log scale.
    final t =
        (math.log(m.clamp(1.0, maxVisualMultiplier)) /
                math.log(maxVisualMultiplier))
            .clamp(0.0, 1.0);
    final x = 0.12 + 0.74 * t;
    final y = 0.86 - 0.68 * math.pow(t, 0.85);
    return Offset(x * size.width, y * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pos = idle
        ? Offset(0.14 * size.width, 0.84 * size.height)
        : _positionFor(multiplier, size);

    // Trail.
    if (!idle) {
      final trail = Path()..moveTo(0.10 * size.width, 0.88 * size.height);
      const steps = 24;
      for (var i = 1; i <= steps; i++) {
        final m =
            1.0 +
            (multiplier.clamp(1.0, maxVisualMultiplier) - 1.0) * i / steps;
        final p = _positionFor(m, size);
        trail.lineTo(p.dx, p.dy);
      }
      final trailPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..shader =
            LinearGradient(
              colors: [
                CrashV2Palette.gold.withValues(alpha: 0.0),
                CrashV2Palette.gold.withValues(alpha: 0.85),
              ],
            ).createShader(
              Rect.fromPoints(Offset(0, size.height), Offset(size.width, 0)),
            );
      canvas.drawPath(trail, trailPaint);

      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = CrashV2Palette.gold.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(trail, glowPaint);
    }

    if (crashed) {
      _paintExplosion(canvas, pos);
      return;
    }
    _paintRocket(canvas, pos, size);
  }

  void _paintRocket(Canvas canvas, Offset pos, Size size) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(idle ? -math.pi / 4 : -math.pi / 5);

    final s = (size.shortestSide * 0.055).clamp(14.0, 26.0);

    // Exhaust flame.
    if (!idle) {
      final flame = Path()
        ..moveTo(-s * 0.34, s * 0.9)
        ..quadraticBezierTo(0, s * 2.6, s * 0.34, s * 0.9)
        ..close();
      canvas.drawPath(
        flame,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              CrashV2Palette.gold,
              const Color(0xFFF97316).withValues(alpha: 0.15),
            ],
          ).createShader(Rect.fromLTWH(-s, s, s * 2, s * 2.2))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Body.
    final body = Path()
      ..moveTo(0, -s * 1.5)
      ..quadraticBezierTo(s * 0.75, -s * 0.25, s * 0.52, s * 0.95)
      ..lineTo(-s * 0.52, s * 0.95)
      ..quadraticBezierTo(-s * 0.75, -s * 0.25, 0, -s * 1.5)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDE9FE), Color(0xFF94A3B8)],
        ).createShader(Rect.fromLTWH(-s, -s * 1.6, s * 2, s * 3)),
    );

    // Window.
    canvas.drawCircle(
      Offset(0, -s * 0.3),
      s * 0.30,
      Paint()..color = CrashV2Palette.electric,
    );
    canvas.drawCircle(
      Offset(0, -s * 0.3),
      s * 0.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Fins.
    final finPaint = Paint()..color = CrashV2Palette.purple;
    canvas.drawPath(
      Path()
        ..moveTo(-s * 0.52, s * 0.28)
        ..lineTo(-s * 1.05, s * 1.15)
        ..lineTo(-s * 0.52, s * 0.95)
        ..close(),
      finPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.52, s * 0.28)
        ..lineTo(s * 1.05, s * 1.15)
        ..lineTo(s * 0.52, s * 0.95)
        ..close(),
      finPaint,
    );

    canvas.restore();

    // Halo glow.
    canvas.drawCircle(
      pos,
      s * 2.1,
      Paint()
        ..color = CrashV2Palette.cyanGlow.withValues(alpha: idle ? 0.05 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  void _paintExplosion(Canvas canvas, Offset pos) {
    final t = crashProgress.clamp(0.0, 1.0);
    final radius = 14 + 46 * Curves.easeOutCubic.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0);

    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = CrashV2Palette.red.withValues(alpha: 0.5 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      pos,
      radius * 0.62,
      Paint()
        ..color = CrashV2Palette.gold.withValues(alpha: 0.7 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final rng = math.Random(11);
    final shard = Paint()
      ..color = Colors.white.withValues(alpha: 0.8 * fade)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final len = radius * (0.7 + rng.nextDouble() * 0.5);
      canvas.drawLine(
        pos + Offset(math.cos(angle), math.sin(angle)) * radius * 0.35,
        pos + Offset(math.cos(angle), math.sin(angle)) * len,
        shard,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RocketFlightPainter oldDelegate) =>
      oldDelegate.multiplier != multiplier ||
      oldDelegate.crashed != crashed ||
      oldDelegate.crashProgress != crashProgress ||
      oldDelegate.idle != idle;
}

/// Rounded chip showing a past round's crash multiplier, colored by value.
class HistoryChip extends StatelessWidget {
  const HistoryChip({required this.multiplier, super.key});

  final double multiplier;

  @override
  Widget build(BuildContext context) {
    final color = CrashV2Palette.multiplierColor(multiplier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        multiplier.toStringAsFixed(2),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Stepper row used for the auto-cashout target and the bet amount.
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    required this.label,
    required this.onMinus,
    required this.onPlus,
    required this.enabled,
    super.key,
  });

  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF0E0A22),
        border: Border.all(color: CrashV2Palette.panelBorder),
      ),
      child: Row(
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            onTap: enabled ? onMinus : null,
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: enabled ? onPlus : null),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 34,
        height: 38,
        child: Icon(
          icon,
          size: 18,
          color: onTap == null
              ? Colors.white.withValues(alpha: 0.25)
              : CrashV2Palette.cyanGlow,
        ),
      ),
    );
  }
}

/// Betting-window progress bar (fills down as the window closes).
class CountdownBar extends StatelessWidget {
  const CountdownBar({required this.fraction, super.key});

  /// 1.0 = window just opened, 0.0 = closed.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation<Color>(
            fraction > 0.35 ? CrashV2Palette.green : CrashV2Palette.red,
          ),
        ),
      ),
    );
  }
}
