import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'crash_v3_rocket.dart';

class CrashV3Chart extends StatelessWidget {
  const CrashV3Chart({required this.multiplier, super.key});
  final double multiplier;
  @override
  Widget build(BuildContext context) {
    final progress = (math.log(math.max(1, multiplier)) / math.log(20)).clamp(
      0.0,
      1.0,
    );
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ChartPainter(progress))),
          Align(
            alignment: Alignment(-.8 + 1.45 * progress, .75 - 1.3 * progress),
            child: CrashV3Rocket(progress: progress),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 5),
        Offset(size.width, size.height * i / 5),
        grid,
      );
    }
    final path = Path()..moveTo(0, size.height * .85);
    for (var i = 0; i <= 60; i++) {
      final x = size.width * i / 60;
      final t = i / 60;
      path.lineTo(x, size.height * (.85 - .72 * t * t));
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFFFC857)],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.progress != progress;
}
