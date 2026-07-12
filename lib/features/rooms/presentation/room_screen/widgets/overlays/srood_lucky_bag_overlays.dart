/// Lucky Bag full-screen overlays: the entrance flash shown when a bag drops
/// (with one-shot SFX) and the win celebration with coin rain and count-up.
/// Both auto-dismiss via their animation controllers and notify the screen
/// through `onDone`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'package:srood_live/shared/utils/error_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entrance overlay — receivers see this on Realtime INSERT. ~2s, self-dismiss.
// ─────────────────────────────────────────────────────────────────────────────

class SroodLuckyBagEntranceOverlay extends StatefulWidget {
  const SroodLuckyBagEntranceOverlay({
    required this.onDone,
    required this.soundEnabled,
    super.key,
  });

  final VoidCallback onDone;
  final bool soundEnabled;

  @override
  State<SroodLuckyBagEntranceOverlay> createState() =>
      _SroodLuckyBagEntranceOverlayState();
}

class _SroodLuckyBagEntranceOverlayState
    extends State<SroodLuckyBagEntranceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _masterFade;
  late final Animation<double> _sparkle;
  AudioPlayer? _sfxPlayer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.2,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.18,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 25),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.7,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
    ]).animate(_ctrl);

    _masterFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_ctrl);

    _sparkle = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.15, 0.85, curve: Curves.easeInOut),
    );

    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });

    unawaited(_tryPlaySound());
  }

  Future<void> _tryPlaySound() async {
    if (!widget.soundEnabled) return;
    try {
      // handleInterruptions: false keeps room music playing under the SFX.
      _sfxPlayer ??= AudioPlayer(handleInterruptions: false);
      await _sfxPlayer!.setAsset('assets/sounds/lucky_bag_open.mp3');
      unawaited(_sfxPlayer!.play());
    } catch (e, st) {
      debugError('SroodLuckyBagEntranceOverlay._tryPlaySound', e, st);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sfxPlayer?.dispose();
    if (kDebugMode) debugPrint('[LuckyBagEntrance] sfxPlayer disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final fade = _masterFade.value;
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6B0000).withValues(alpha: 0.85 * fade),
                    Colors.black.withValues(alpha: 0.75 * fade),
                  ],
                  radius: 1.2,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glowing bag icon with sparkle coins around it
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: _sparkle.value,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFFD700,
                                    ).withValues(alpha: 0.55),
                                    blurRadius: 60,
                                    spreadRadius: 20,
                                  ),
                                  BoxShadow(
                                    color: const Color(
                                      0xFFE63946,
                                    ).withValues(alpha: 0.3),
                                    blurRadius: 40,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: _scale.value,
                            child: const Icon(
                              Icons.card_giftcard_rounded,
                              size: 110,
                              color: Color(0xFFFFD700),
                            ),
                          ),
                          ..._buildSparkles(_sparkle.value),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Transform.scale(
                      scale: (_scale.value).clamp(0.5, 1.0),
                      child: Column(
                        children: [
                          Text(
                            'Lucky Bag!',
                            style: TextStyle(
                              color: const Color(0xFFFFD700),
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                  color: const Color(
                                    0xFFE63946,
                                  ).withValues(alpha: 0.8),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap to win coins!',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSparkles(double t) {
    // 8 coin icons in a circle, fading/drifting outward.
    const count = 8;
    const radius = 72.0;
    return List.generate(count, (i) {
      final angle = (i / count) * 2 * math.pi;
      final drift = t * 14;
      final x = math.cos(angle) * (radius + drift);
      final y = math.sin(angle) * (radius + drift);
      final opacity = (math.sin(t * math.pi)).clamp(0.0, 1.0);
      return Positioned(
        left: 100 + x - 10,
        top: 100 + y - 10,
        child: Opacity(
          opacity: opacity,
          child: const Icon(
            Icons.monetization_on_rounded,
            size: 20,
            color: Color(0xFFFFD700),
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Win overlay — claimer sees coin rain + animated count-up. Self-dismiss.
// ─────────────────────────────────────────────────────────────────────────────

class SroodLuckyBagWinOverlay extends StatefulWidget {
  const SroodLuckyBagWinOverlay({
    required this.coins,
    required this.onDone,
    required this.soundEnabled,
    super.key,
  });

  final int coins;
  final VoidCallback onDone;
  final bool soundEnabled;

  @override
  State<SroodLuckyBagWinOverlay> createState() =>
      _SroodLuckyBagWinOverlayState();
}

class _SroodLuckyBagWinOverlayState extends State<SroodLuckyBagWinOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _masterFade;
  late final Animation<double> _textScale;
  late final Animation<double> _textBounce;
  late final Animation<int> _countUp;
  AudioPlayer? _sfxPlayer;

  // Pre-computed deterministic coin positions.
  static const _coinXFractions = [
    0.05,
    0.15,
    0.25,
    0.38,
    0.50,
    0.62,
    0.75,
    0.85,
    0.92,
    0.32,
  ];
  static const _coinDelayFractions = [
    0.00,
    0.08,
    0.04,
    0.12,
    0.02,
    0.10,
    0.06,
    0.14,
    0.03,
    0.09,
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _masterFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 63),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_ctrl);

    _textScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
    ]).animate(_ctrl);

    _textBounce = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 20),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -12.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -12.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
    ]).animate(_ctrl);

    _countUp = IntTween(begin: 0, end: widget.coins).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.15, 0.65, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });

    unawaited(_tryPlayWinSound());
  }

  Future<void> _tryPlayWinSound() async {
    if (!widget.soundEnabled) return;
    try {
      _sfxPlayer ??= AudioPlayer(handleInterruptions: false);
      await _sfxPlayer!.setAsset('assets/sounds/lucky_bag_win.wav');
      unawaited(_sfxPlayer!.play());
    } catch (e, st) {
      debugError('SroodLuckyBagWinOverlay._tryPlayWinSound', e, st);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sfxPlayer?.dispose();
    if (kDebugMode) debugPrint('[LuckyBagWin] sfxPlayer disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final fade = _masterFade.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Stack(
              children: [
                Container(color: Colors.black.withValues(alpha: 0.35 * fade)),
                ..._buildRain(screenWidth, screenHeight),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, _textBounce.value),
                    child: Transform.scale(
                      scale: _textScale.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 36,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF8B0000),
                              Color(0xFFBF1B0B),
                              Color(0xFF8B0000),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.6),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFFD700,
                              ).withValues(alpha: 0.35),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: const Color(
                                0xFFE63946,
                              ).withValues(alpha: 0.4),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.card_giftcard_rounded,
                              size: 52,
                              color: Color(0xFFFFD700),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'You got',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.monetization_on_rounded,
                                  color: Color(0xFFFFD700),
                                  size: 32,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_countUp.value}',
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 48,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'coins!',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double _coinProgressFor(double t, double delay) {
    final end = math.min(1.0, delay + 0.55);
    if (t <= delay) return 0.0;
    if (t >= end) return 1.0;
    final x = (t - delay) / (end - delay);
    return Curves.easeIn.transform(x);
  }

  List<Widget> _buildRain(double w, double h) {
    final t = _ctrl.value;
    return List.generate(10, (i) {
      final xFrac = _coinXFractions[i];
      final delay = _coinDelayFractions[i];
      final p = _coinProgressFor(t, delay);
      final y = -30.0 + p * (h + 40);
      final opacity = p < 0.85 ? 1.0 : (1.0 - (p - 0.85) / 0.15);
      return Positioned(
        left: xFrac * w - 12,
        top: y,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: p * 2 * math.pi * (i.isEven ? 1 : -1),
            child: Icon(
              Icons.monetization_on_rounded,
              size: 22 + (i % 3) * 4.0,
              color: const Color(0xFFFFD700),
            ),
          ),
        ),
      );
    });
  }
}
