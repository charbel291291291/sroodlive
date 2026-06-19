import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/supabase/supabase_service.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Branded animated splash screen for Srood Live
//
// Animation timeline (master = 2500 ms):
//   0–300 ms   (0.00–0.12)  background glow fades in
//   300–850 ms (0.12–0.34)  logo + content fades/scales in
//   900–1100ms (0.36–0.44)  right "oo" eye blinks (scaleY: 1 → 0.05 → 1)
//              (0.36 hit)   blink sound plays once
//   1100–1450ms(0.44–0.58)  both eyes pulse with neon glow
//   1500–1800ms(0.60–0.72)  waveform bars pulse in
//   1800–2200ms(0.72–0.88)  tagline fades in
//   2500ms                   navigate (if session already resolved)
//
// Session check runs in parallel with animation. Navigation fires when BOTH
// the 2500 ms animation AND the session check are complete — whichever takes
// longer wins, so the splash never leaves early nor hangs forever.
// ─────────────────────────────────────────────────────────────────────────────

enum _NavTarget { home, onboarding }

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  // ── Master controller (2 500 ms) ─────────────────────────────────────────
  late final AnimationController _master;

  // Derived animations (all driven from _master via Interval curves)
  late final Animation<double> _bgGlow;       // radial bg glow fade-in
  late final Animation<double> _contentFade;  // logo / content fade-in
  late final Animation<double> _logoScale;    // logo subtle scale-up
  late final Animation<double> _blinkScaleY;  // right eye blink
  late final Animation<double> _eyeGlow;      // both-eye glow pulse
  late final Animation<double> _waveIn;       // waveform bars
  late final Animation<double> _taglineFade;  // tagline fade-in

  // ── Navigation state ─────────────────────────────────────────────────────
  bool        _animDone  = false;
  _NavTarget? _navTarget;

  // ── Banned-message edge-case ──────────────────────────────────────────────
  String? _bannedMsg;

  // ── Sound ─────────────────────────────────────────────────────────────────
  AudioPlayer? _blinkPlayer;
  bool         _blinkSoundPlayed = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _buildAnimations();
    _initSound();     // fire-and-forget; failure is silent
    _checkSession();  // runs in parallel with animation
    _master.forward();
  }

  @override
  void dispose() {
    _master.removeListener(_masterTick);
    _master.dispose();
    _blinkPlayer?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Animation setup
  // ─────────────────────────────────────────────────────────────────────────

  void _buildAnimations() {
    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )
      ..addListener(_masterTick)
      ..addStatusListener(_masterStatus);

    // Background radial glow: 0–300 ms
    _bgGlow = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.00, 0.12, curve: Curves.easeOut),
    );

    // Content fade-in: 300–850 ms
    _contentFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.12, 0.34, curve: Curves.easeOut),
    );

    // Logo scale-up (0.88 → 1.0): 300–850 ms
    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.12, 0.34, curve: Curves.easeOutCubic),
      ),
    );

    // Right-eye blink scaleY: 900–1100 ms
    // Close fast (900–1000 ms), open slightly slower (1000–1100 ms)
    _blinkScaleY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.05)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.05, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(CurvedAnimation(
      parent: _master,
      curve: const Interval(0.36, 0.44),
    ));

    // Both-eye glow pulse: 1100–1450 ms (rise then fall)
    _eyeGlow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _master,
      curve: const Interval(0.44, 0.58, curve: Curves.easeInOut),
    ));

    // Waveform bars pulse in: 1500–1800 ms
    _waveIn = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.60, 0.72, curve: Curves.easeOut),
    );

    // Tagline fade: 1800–2200 ms
    _taglineFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.72, 0.88, curve: Curves.easeOut),
    );
  }

  // Fires every animation tick — triggers blink sound at exactly 900 ms mark
  void _masterTick() {
    if (!_blinkSoundPlayed && _master.value >= 0.36) {
      _blinkSoundPlayed = true;
      _playBlinkSound();
    }
  }

  void _masterStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animDone = true;
      _tryNavigate();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sound
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initSound() async {
    // Asset search order:
    //   1. assets/sounds/splash_blink.mp3  (dedicated blink sfx — place here)
    //   2. assets/sounds/lucky_bag_open.mp3 (existing bundled sound, lower vol)
    // Failure at any step is silenced; splash works without sound.
    try {
      final player = AudioPlayer();
      bool loaded = false;

      const candidates = [
        'assets/sounds/splash_blink.mp3',
        'assets/sounds/lucky_bag_open.mp3',
      ];

      for (final path in candidates) {
        try {
          await player.setAsset(path);
          // Very low volume for the blink: subtle, not annoying
          await player.setVolume(path.contains('splash_blink') ? 0.55 : 0.18);
          loaded = true;
          break;
        } catch (_) {
          continue;
        }
      }

      if (loaded) _blinkPlayer = player;
    } catch (_) {
      // Sound is optional — silently skip
    }
  }

  void _playBlinkSound() {
    try {
      _blinkPlayer?.seek(Duration.zero);
      _blinkPlayer?.play();
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session check (runs in parallel with animation)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkSession() async {
    try {
      final client = SupabaseService.client;
      final user   = client?.auth.currentUser;

      if (client == null || user == null) {
        _resolveNav(_NavTarget.onboarding);
        return;
      }

      final profile = await client
          .from('profiles')
          .select('is_banned')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (profile?['is_banned'] == true) {
        await client.auth.signOut();
        if (!mounted) return;
        setState(() => _bannedMsg = 'Your account has been banned.');
        // Show banned notice for at least 2 s on top of the splash
        await Future<void>.delayed(const Duration(seconds: 2));
        _resolveNav(_NavTarget.onboarding);
        return;
      }

      _resolveNav(_NavTarget.home);
    } catch (_) {
      _resolveNav(_NavTarget.onboarding);
    }
  }

  void _resolveNav(_NavTarget target) {
    if (!mounted) return;
    _navTarget = target;
    _tryNavigate();
  }

  void _tryNavigate() {
    // Gate: wait for BOTH animation to finish AND session check to complete.
    if (!_animDone || _navTarget == null) return;
    if (!mounted) return;

    final Widget dest = _navTarget == _NavTarget.home
        ? const HomeScreen()
        : const OnboardingScreen();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => dest),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06030E),
      body: AnimatedBuilder(
        animation: _master,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background radial glow ───────────────────────────────────────
        Opacity(
          opacity: _bgGlow.value,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.15),
                radius: 1.0,
                colors: [
                  Color(0xFF1C0A3E), // deep purple centre
                  Color(0xFF0D0524), // mid
                  Color(0xFF06030E), // edges match scaffold bg
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),

        // ── Main content: logo + wave + tagline ──────────────────────────
        Center(
          child: Opacity(
            opacity: _contentFade.value,
            child: Transform.scale(
              scale: _logoScale.value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLogoRow(),
                  const SizedBox(height: 20),
                  _buildWaveform(),
                  const SizedBox(height: 22),
                  _buildTagline(),
                ],
              ),
            ),
          ),
        ),

        // ── Banned message (edge case) ────────────────────────────────────
        if (_bannedMsg != null)
          Positioned(
            bottom: 72,
            left: 32,
            right: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF3D0A0A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF5C7A).withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                _bannedMsg!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFF5C7A),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Logo row: "Sr 👁️👁️ d  Live" ──────────────────────────────────────────

  Widget _buildLogoRow() {
    // Base text style for "Sr" and "d"
    const base = TextStyle(
      color: Colors.white,
      fontSize: 50,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.5,
      height: 1.0,
    );

    // "Live" in warm gold
    const live = TextStyle(
      color: Color(0xFFF0C15A),
      fontSize: 50,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.5,
      height: 1.0,
    );

    // Diameter of each eye circle — matched to font x-height (~55% of 50px)
    const eyeDiam = 30.0;

    final glow = _eyeGlow.value; // 0.0 → 1.0 → 0.0 during pulse phase

    // Soft neon glow added to logo text during the eye-glow phase
    final textGlowShadows = glow > 0.0
        ? <Shadow>[
            Shadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: glow * 0.6),
              blurRadius: 12.0 * glow,
            ),
          ]
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // "Sr" — static text
        Text('Sr', style: base.copyWith(shadows: textGlowShadows)),

        const SizedBox(width: 3),

        // Left "o" eye — glows but never blinks
        _buildEye(diameter: eyeDiam, glow: glow, blinks: false),

        const SizedBox(width: 3),

        // Right "o" eye — glows AND blinks
        _buildEye(diameter: eyeDiam, glow: glow, blinks: true),

        const SizedBox(width: 3),

        // "d" — static text
        Text('d', style: base.copyWith(shadows: textGlowShadows)),

        const SizedBox(width: 12),

        // "Live" — gold accent, no eye animation
        Text('Live', style: live.copyWith(
          shadows: glow > 0.0
              ? [
                  Shadow(
                    color: const Color(0xFFF0C15A).withValues(alpha: glow * 0.5),
                    blurRadius: 10.0 * glow,
                  ),
                ]
              : null,
        )),
      ],
    );
  }

  /// Builds one eye circle.
  ///
  /// [glow]   — 0.0…1.0 glow pulse intensity (driven by [_eyeGlow])
  /// [blinks] — if true, applies the vertical-squish blink via [_blinkScaleY]
  Widget _buildEye({
    required double diameter,
    required double glow,
    required bool blinks,
  }) {
    // Base glow intensity — eyes always have a subtle ambient glow
    const baseAlpha = 0.35;
    final pulseAlpha = baseAlpha + (1.0 - baseAlpha) * glow;

    Widget eye = Container(
      width:  diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Deep purple iris
        gradient: RadialGradient(
          colors: [
            Color.lerp(const Color(0xFF6B21A8), const Color(0xFFA855F7), glow)!,
            const Color(0xFF2E1065),
          ],
          stops: const [0.0, 1.0],
        ),
        border: Border.all(
          color: Color.lerp(
            const Color(0xFF6D28D9),
            const Color(0xFFE9D5FF),
            glow * 0.75,
          )!,
          width: 1.5 + glow * 0.5,
        ),
        boxShadow: [
          // Inner glow
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: pulseAlpha * 0.65),
            blurRadius: 6.0 + glow * 14.0,
            spreadRadius: glow * 2.0,
          ),
          // Outer aura (only during pulse)
          if (glow > 0.0)
            BoxShadow(
              color: const Color(0xFFC4B5FD).withValues(alpha: glow * 0.30),
              blurRadius: 20.0 + glow * 24.0,
              spreadRadius: glow,
            ),
        ],
      ),
      // Pupil dot
      child: Center(
        child: AnimatedContainer(
          duration: Duration.zero,
          width:  diameter * 0.26,
          height: diameter * 0.26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(
              const Color(0xFF9F7AEA),
              Colors.white,
              glow * 0.65,
            ),
          ),
        ),
      ),
    );

    // Apply blink: vertical squish using scaleY, clipped to prevent layout jank
    if (blinks) {
      eye = ClipRect(
        child: Transform.scale(
          scaleY: _blinkScaleY.value,
          alignment: Alignment.center,
          child: eye,
        ),
      );
    }

    return eye;
  }

  // ── Waveform bars ─────────────────────────────────────────────────────────

  Widget _buildWaveform() {
    return Opacity(
      opacity: _waveIn.value,
      child: Transform.scale(
        scaleY: _waveIn.value,
        alignment: Alignment.center,
        child: const _WaveformBars(),
      ),
    );
  }

  // ── Tagline ───────────────────────────────────────────────────────────────

  Widget _buildTagline() {
    return Opacity(
      opacity: _taglineFade.value,
      child: Text(
        _bannedMsg != null ? '' : 'Voice rooms. Gifts. Prestige.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFB8B8C7),
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform bars — 7 vertical bars with a sine-wave height profile
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformBars extends StatelessWidget {
  const _WaveformBars();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(76, 18),
      painter: const _WaveformPainter(),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter();

  // Height ratios for 7 bars — centred bell shape
  static const _heights = [0.35, 0.55, 0.80, 1.0, 0.80, 0.55, 0.35];

  @override
  void paint(Canvas canvas, Size size) {
    const n = 7;
    const barW = 3.5;
    final gap  = (size.width - n * barW) / (n - 1);

    for (int i = 0; i < n; i++) {
      final h = _heights[i] * size.height;
      final x = i * (barW + gap);
      final y = (size.height - h) / 2;

      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        const Radius.circular(barW / 2),
      );

      // Soft glow pass
      canvas.drawRRect(
        rr,
        Paint()
          ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
      // Solid bar
      canvas.drawRRect(rr, Paint()..color = const Color(0xFF7C3AED));
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter _) => false;
}
