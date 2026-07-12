/// Full-screen vault-style closing overlay shown while the room tears down.
/// Owner sees a locking vault; members see a farewell logout treatment.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

class SroodRoomClosingOverlay extends StatefulWidget {
  const SroodRoomClosingOverlay({
    required this.isOwnerClosing,
    required this.isArabic,
    super.key,
  });

  final bool isOwnerClosing;
  final bool isArabic;

  @override
  State<SroodRoomClosingOverlay> createState() =>
      _SroodRoomClosingOverlayState();
}

class _SroodRoomClosingOverlayState extends State<SroodRoomClosingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _lockScaleCtrl;
  late final AnimationController _shimmerCtrl;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _lockScaleAnim;
  late final Animation<double> _shimmerAnim;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: SroodRoomMotion.slow,
    );
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _lockScaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _lockScaleAnim = CurvedAnimation(
      parent: _lockScaleCtrl,
      curve: Curves.elasticOut,
    );
    _shimmerAnim = CurvedAnimation(
      parent: _shimmerCtrl,
      curve: Curves.easeInOut,
    );

    _fadeCtrl.forward();
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _disposed) return;
      if (!_lockScaleCtrl.isAnimating &&
          _lockScaleCtrl.status == AnimationStatus.dismissed) {
        _lockScaleCtrl.forward();
      }
      if (!_ringCtrl.isAnimating) _ringCtrl.repeat();
    });
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _disposed) return;
      if (!_shimmerCtrl.isAnimating) _shimmerCtrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _fadeCtrl.stop();
    _ringCtrl.stop();
    _lockScaleCtrl.stop();
    _shimmerCtrl.stop();
    _fadeCtrl.dispose();
    _ringCtrl.dispose();
    _lockScaleCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isArabic;
    final isOwner = widget.isOwnerClosing;

    final titleText = isOwner
        ? (isAr ? 'جارٍ إغلاق الغرفة...' : 'Closing Room...')
        : (isAr ? 'جارٍ مغادرة الغرفة...' : 'Leaving Room...');
    final subtitleText = isOwner
        ? (isAr ? 'يتم تأمين الغرفة' : 'Securing the room')
        : (isAr ? 'نراك قريباً' : 'See you around');

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vault ring + lock
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: SroodRoomColors.gold.withValues(
                              alpha: 0.18,
                            ),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _ringCtrl,
                      builder: (_, _) => CustomPaint(
                        size: const Size(130, 130),
                        painter: _VaultRingPainter(progress: _ringCtrl.value),
                      ),
                    ),
                    ScaleTransition(
                      scale: _lockScaleAnim,
                      child: AnimatedBuilder(
                        animation: _shimmerAnim,
                        builder: (_, _) {
                          final shimmerColor = Color.lerp(
                            SroodRoomColors.gold,
                            const Color(0xFFFFFFAA),
                            _shimmerAnim.value,
                          )!;
                          return Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  shimmerColor.withValues(alpha: 0.22),
                                  const Color(
                                    0xFF2A0A50,
                                  ).withValues(alpha: 0.9),
                                ],
                              ),
                              border: Border.all(
                                color: shimmerColor.withValues(alpha: 0.50),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              isOwner
                                  ? Icons.lock_rounded
                                  : Icons.logout_rounded,
                              color: shimmerColor,
                              size: 32,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                titleText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: SroodRoomDims.space8),
              Text(
                subtitleText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              const _PulsingDots(),
            ],
          ),
        ),
      ),
    );
  }
}

// Vault ring: rotating arc segments like a combination lock.
class _VaultRingPainter extends CustomPainter {
  const _VaultRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF2A1050).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );

    const segmentCount = 8;
    const gapFraction = 0.08;
    final segmentSweep = (1.0 - gapFraction * segmentCount) / segmentCount;
    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < segmentCount; i++) {
      final startFraction = i / segmentCount + gapFraction / 2;
      final startAngle = (startFraction + progress) * 2 * math.pi;
      final sweepAngle = segmentSweep * 2 * math.pi;

      final relPos = ((startFraction + progress) % 1.0);
      final opacity = relPos < 0.5 ? relPos * 2 : (1.0 - relPos) * 2;
      goldPaint.color = Color.lerp(
        const Color(0xFF4A2A80),
        SroodRoomColors.gold,
        opacity.clamp(0.15, 1.0),
      )!;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        goldPaint,
      );
    }

    // Notch markers (vault dial ticks).
    final notchPaint = Paint()
      ..color = SroodRoomColors.gold.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12 + progress * 0.3) * 2 * math.pi;
      final inner = radius + 6;
      final outer = radius + 10;
      canvas.drawLine(
        Offset(
          center.dx + inner * math.cos(angle),
          center.dy + inner * math.sin(angle),
        ),
        Offset(
          center.dx + outer * math.cos(angle),
          center.dy + outer * math.sin(angle),
        ),
        notchPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_VaultRingPainter old) => old.progress != progress;
}

// Three pulsing dots indicating progress.
class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
            final scale =
                0.6 + 0.4 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8 * scale,
              height: 8 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SroodRoomColors.gold.withValues(
                  alpha: 0.5 + 0.5 * scale,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
