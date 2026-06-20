import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/config/app_config.dart';
import '../../core/supabase/supabase_service.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../startup_promo/widgets/startup_promo_overlay.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Video splash screen — plays assets/videos/srood_splash.mp4 once.
//
// Navigation fires when BOTH the video ends AND the session check completes.
// If the video fails to load, a static fallback is shown for 2 s instead.
// Banned-user handling is preserved: sign out → show notice → go to onboarding.
// ─────────────────────────────────────────────────────────────────────────────

enum _NavTarget { home, onboarding }

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady   = false; // controller initialized successfully
  bool _videoDone    = false; // video finished playing (or fallback timer fired)
  _NavTarget? _navTarget;
  String? _bannedMsg;

  @override
  void initState() {
    super.initState();
    // Hide status bar and navigation bar for the duration of the splash.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initVideo();
    _checkSession();
  }

  @override
  void dispose() {
    // Restore system overlays when the splash is torn down (covers the case
    // where the widget is disposed without navigating, e.g. hot-restart).
    _restoreSystemUI();
    _videoCtrl?.removeListener(_onVideoUpdate);
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  // ── Video ──────────────────────────────────────────────────────────────────

  Future<void> _initVideo() async {
    try {
      final ctrl = VideoPlayerController.asset(AppConfig.instance.splashVideoPath);
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }

      ctrl.addListener(_onVideoUpdate);
      await ctrl.setLooping(false);
      await ctrl.setVolume(1.0);

      setState(() {
        _videoCtrl  = ctrl;
        _videoReady = true;
      });

      await ctrl.play();
    } catch (e) {
      debugPrint('[Splash] video init failed: $e — using static fallback');
      // Show static fallback for 2 s then proceed as if video finished.
      if (!mounted) return;
      setState(() { _videoReady = false; });
      await Future<void>.delayed(const Duration(seconds: 2));
      _onVideoDone();
    }
  }

  void _onVideoUpdate() {
    final ctrl = _videoCtrl;
    if (ctrl == null || _videoDone) return;
    final v        = ctrl.value;
    final pos      = v.position;
    final duration = v.duration;
    if (duration <= Duration.zero) return;
    // Fire when position reaches the end OR when playback stopped at/near end.
    // The ">= duration" path catches normal completion; the second path catches
    // devices where the player stops a frame short of the reported duration.
    final nearEnd = pos >= duration - const Duration(milliseconds: 200);
    if (pos >= duration || (nearEnd && !v.isPlaying && !v.isBuffering)) {
      _onVideoDone();
    }
  }

  void _onVideoDone() {
    if (_videoDone) return;
    _videoDone = true;
    _tryNavigate();
  }

  // ── Session check ──────────────────────────────────────────────────────────

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
    // Gate: wait for BOTH video end AND session check.
    if (!_videoDone || _navTarget == null) return;
    if (!mounted) return;

    // Restore bars before the next screen renders so it gets a normal UI.
    _restoreSystemUI();

    final Widget dest = _navTarget == _NavTarget.home
        ? const _PromoGateScreen()
        : const OnboardingScreen();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => dest),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_videoReady && _videoCtrl != null)
            _VideoFill(controller: _videoCtrl!)
          else
            _StaticFallback(),

          // Banned-user notice
          if (_bannedMsg != null)
            Positioned(
              bottom: 72,
              left: 32,
              right: 32,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video fill — scales the video to cover the screen (like BoxFit.cover)
// ─────────────────────────────────────────────────────────────────────────────

class _VideoFill extends StatelessWidget {
  const _VideoFill({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    // Cover-fit: scale the video to fill the screen without black bars.
    // FittedBox(cover) over a native-size SizedBox achieves BoxFit.cover
    // since VideoPlayer doesn't accept a BoxFit directly.
    final size = controller.value.size;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width:  size.width,
          height: size.height,
          child:  VideoPlayer(controller),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static fallback shown when the video fails to load
// ─────────────────────────────────────────────────────────────────────────────

class _StaticFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cfg = AppConfig.instance;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.0,
          colors: [Color(0xFF1C0A3E), Color(0xFF0D0524), Color(0xFF06030E)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cfg.appDisplayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              cfg.appTaglineEn,
              style: const TextStyle(
                color: Color(0xFFB8B8C7),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Promo gate — thin black screen inserted between SplashScreen and HomeScreen.
// Fetches + precaches the promo, shows it if applicable, then goes to Home.
// This ensures the promo is the very first thing the user sees after launch.
// ─────────────────────────────────────────────────────────────────────────────

class _PromoGateScreen extends StatefulWidget {
  const _PromoGateScreen();

  @override
  State<_PromoGateScreen> createState() => _PromoGateScreenState();
}

class _PromoGateScreenState extends State<_PromoGateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    await StartupPromoController.maybeShow(context);
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Color(0xFF08060F));
}
