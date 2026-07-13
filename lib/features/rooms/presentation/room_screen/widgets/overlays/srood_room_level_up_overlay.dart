/// Room level-up celebration overlay — royal achievement card with crown,
/// sparkle burst, and bilingual level pill. Auto-dismisses via `onDone`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SroodRoomLevelUpOverlay extends StatefulWidget {
  const SroodRoomLevelUpOverlay({
    required this.newLevel,
    required this.onDone,
    super.key,
  });

  final int newLevel;
  final VoidCallback onDone;

  @override
  State<SroodRoomLevelUpOverlay> createState() =>
      _SroodRoomLevelUpOverlayState();
}

class _SroodRoomLevelUpOverlayState extends State<SroodRoomLevelUpOverlay>
    with TickerProviderStateMixin {
  // Main lifecycle: fade+scale in → hold → fade out
  late final AnimationController _main;
  // Gold border pulse (loops while card is visible)
  late final AnimationController _glow;
  // Sparkle particles (fires once on entry)
  late final AnimationController _spark;

  late final Animation<double> _cardScale;
  late final Animation<double> _fadeIn;
  late final Animation<double> _fadeOut;

  static const _kGold = Color(0xFFFFD76B);
  static const _kPurple = Color(0xFF8B26D9);

  @override
  void initState() {
    super.initState();

    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _spark = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _cardScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 22,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.00), weight: 8),
      TweenSequenceItem(tween: ConstantTween(1.00), weight: 48),
      TweenSequenceItem(tween: Tween(begin: 1.00, end: 0.88), weight: 22),
    ]).animate(_main);

    _fadeIn = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.00, 0.18, curve: Curves.easeIn),
    );
    _fadeOut = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.80, 1.00, curve: Curves.easeOut),
    );

    // Delay sparkles slightly so they burst right after the card pops.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _spark.forward();
    });

    _main.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _main.dispose();
    _glow.dispose();
    _spark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_main, _glow, _spark]),
      builder: (context, _) {
        final bgOpacity = (_fadeIn.value - _fadeOut.value).clamp(0.0, 1.0);
        final cardOpacity = (_fadeIn.value - _fadeOut.value * 0.85).clamp(
          0.0,
          1.0,
        );
        final glowAlpha = 0.55 + _glow.value * 0.30;

        return Material(
          color: Colors.black.withValues(alpha: bgOpacity * 0.60),
          child: Center(
            child: Opacity(
              opacity: cardOpacity,
              child: Transform.scale(
                scale: _cardScale.value,
                child: SizedBox(
                  width: 280,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // ── Sparkle particles behind the card ──────────────
                      CustomPaint(
                        size: const Size(280, 280),
                        painter: _SparklePainter(
                          progress: _spark.value,
                          goldColor: _kGold,
                        ),
                      ),

                      // ── Card ────────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF1A0540),
                              Color(0xFF2E0E6E),
                              Color(0xFF5A18B0),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: _kGold.withValues(alpha: glowAlpha),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _kPurple.withValues(
                                alpha: 0.55 + _glow.value * 0.20,
                              ),
                              blurRadius: 48,
                              spreadRadius: 6,
                            ),
                            BoxShadow(
                              color: _kGold.withValues(
                                alpha: 0.18 + _glow.value * 0.14,
                              ),
                              blurRadius: 28,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.55),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            decoration: TextDecoration.none,
                            fontFamilyFallback: ['NotoSansArabic', 'Arial'],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _GlowingCrown(glowT: _glow.value),
                              const SizedBox(height: 20),

                              // Arabic headline — largest, most prominent
                              Text(
                                'الغرفة ارتقت!',
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: _kGold,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                  letterSpacing: 0.5,
                                  shadows: [
                                    Shadow(
                                      color: _kGold.withValues(alpha: 0.70),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),

                              const Text(
                                'Room Leveled Up',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 22),

                              _LevelPill(
                                level: widget.newLevel,
                                glowT: _glow.value,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Crown icon with pulsing gold glow ────────────────────────────────────────

class _GlowingCrown extends StatelessWidget {
  const _GlowingCrown({required this.glowT});

  final double glowT;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFE87C), Color(0xFFCC8A00), Color(0xFF5A18B0)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFFFFD76B,
            ).withValues(alpha: 0.40 + glowT * 0.35),
            blurRadius: 24 + glowT * 16,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.50),
            blurRadius: 16,
          ),
        ],
      ),
      child: const Icon(
        Icons.workspace_premium_rounded,
        color: Colors.white,
        size: 38,
      ),
    );
  }
}

// ── Level number pill ─────────────────────────────────────────────────────────

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.level, required this.glowT});

  final int level;
  final double glowT;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [Color(0xFF3A1375), Color(0xFF8B26D9)],
        ),
        border: Border.all(
          color: const Color(0xFFFFD76B).withValues(alpha: 0.55 + glowT * 0.30),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFFFFD76B,
            ).withValues(alpha: 0.15 + glowT * 0.15),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'المستوى $level',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: Color(0xFFFFD76B),
              fontSize: 17,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
              letterSpacing: 0.3,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '·',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 17,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Text(
            'Level $level',
            style: const TextStyle(
              color: Color(0xFFFFD76B),
              fontSize: 17,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sparkle particle painter ──────────────────────────────────────────────────
// 16 particles at even angles, each traveling outward and fading.

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress, required this.goldColor});

  final double progress;
  final Color goldColor;

  static const int _kCount = 16;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.width * 0.48;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _kCount; i++) {
      final angle = (i / _kCount) * 2 * math.pi;
      final dotSize = (i % 3 == 0)
          ? 5.0
          : (i % 2 == 0)
          ? 3.5
          : 2.5;
      final r = maxR * Curves.easeOut.transform(progress);
      final alpha = (1.0 - progress).clamp(0.0, 1.0);

      final color = i % 3 == 0
          ? goldColor.withValues(alpha: alpha * 0.95)
          : Colors.white.withValues(alpha: alpha * 0.70);

      paint.color = color;
      canvas.drawCircle(
        Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)),
        dotSize,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.progress != progress;
}
