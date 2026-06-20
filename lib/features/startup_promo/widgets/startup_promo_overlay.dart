import 'dart:async';

import 'package:flutter/material.dart';

import '../models/startup_promo.dart';
import '../services/startup_promo_service.dart';

/// Shows full-screen startup promo overlay as part of the startup gate.
/// Called from the promo gate screen inserted between splash and HomeScreen.
class StartupPromoController {
  static bool _showing = false;
  static bool _shownThisSession = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (_showing || _shownThisSession) return;

    final service = const StartupPromoService();
    final promo = await service.fetchActivePromo();
    if (promo == null) return;

    final should = await service.shouldDisplay(promo);
    if (!should) {
      debugPrint('[PerfStartupPromo] skipped (frequency rule: ${promo.frequency})');
      return;
    }

    if (!context.mounted) return;

    // Precache image before showing to avoid flash.
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      await precacheImage(NetworkImage(promo.imageUrl), context);
      debugPrint('[PerfStartupPromo] image precached in ${DateTime.now().millisecondsSinceEpoch - t0}ms');
    } catch (_) {
      // Continue even if precache fails — errorBuilder handles bad images.
      debugPrint('[PerfStartupPromo] precache failed, showing anyway');
    }

    if (!context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    _showing = true;
    _shownThisSession = true;
    await service.recordDisplayed(promo);
    debugPrint('[PerfStartupPromo] shown id=${promo.id}');

    await navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => _StartupPromoPage(promo: promo),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );

    _showing = false;
  }
}

class _StartupPromoPage extends StatefulWidget {
  const _StartupPromoPage({required this.promo});

  final StartupPromo promo;

  @override
  State<_StartupPromoPage> createState() => _StartupPromoPageState();
}

class _StartupPromoPageState extends State<_StartupPromoPage> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.promo.durationSeconds.clamp(3, 10);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _close(completed: true);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close({bool completed = false}) {
    _timer?.cancel();
    if (completed) {
      debugPrint('[PerfStartupPromo] completed id=${widget.promo.id}');
    } else {
      debugPrint('[PerfStartupPromo] skipped id=${widget.promo.id}');
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08060F),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-screen image ──────────────────────────────────────────
            Image.network(
              widget.promo.imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: const Color(0xFF12061F),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFF4C95D),
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFF12061F),
                child: const Center(
                  child: Icon(
                    Icons.image_not_supported_rounded,
                    color: Color(0xFF3D2A5A),
                    size: 48,
                  ),
                ),
              ),
            ),

            // ── Gradient vignette ──────────────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.25),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    stops: const [0.0, 0.2, 0.75, 1.0],
                  ),
                ),
              ),
            ),

            // ── Skip button ────────────────────────────────────────────────
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 16),
                  child: GestureDetector(
                    onTap: () => _close(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        _remaining > 0 ? 'Skip ${_remaining}s' : 'Skip',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
