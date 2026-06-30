import 'package:flutter/material.dart';

enum SroodToastType { success, error, info, warning }

/// Luxury toast system — replaces all Material SnackBars across Srood Live.
///
/// Usage:
///   SroodToast.show(context, 'تم الحفظ', type: SroodToastType.success);
class SroodToast {
  SroodToast._();

  static void show(
    BuildContext context,
    String message, {
    SroodToastType type = SroodToastType.info,
  }) {
    if (!context.mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _SroodToastOverlay(
        message: message,
        type: type,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

// ── Internal overlay widget ───────────────────────────────────────────────────

class _SroodToastOverlay extends StatefulWidget {
  const _SroodToastOverlay({
    required this.message,
    required this.type,
    required this.onDone,
  });
  final String message;
  final SroodToastType type;
  final VoidCallback onDone;

  @override
  State<_SroodToastOverlay> createState() => _SroodToastOverlayState();
}

class _SroodToastOverlayState extends State<_SroodToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideY;
  late final Animation<double> _opacity;

  // Errors/warnings stay a little longer.
  Duration get _totalDuration {
    return switch (widget.type) {
      SroodToastType.error   => const Duration(milliseconds: 3200),
      SroodToastType.warning => const Duration(milliseconds: 3000),
      _                      => const Duration(milliseconds: 2600),
    };
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _totalDuration);

    // Slide: starts 60px below, springs up, holds, drops back down on exit.
    _slideY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 60.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 14,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 66),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 40.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 20,
      ),
    ]).animate(_ctrl);

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0),           weight: 72),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 18),
    ]).animate(_ctrl);

    _ctrl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accent => switch (widget.type) {
    SroodToastType.success => const Color(0xFF4CAF82),
    SroodToastType.error   => const Color(0xFFEF4444),
    SroodToastType.warning => const Color(0xFFFFD76B),
    SroodToastType.info    => const Color(0xFF9B5DE5),
  };

  IconData get _icon => switch (widget.type) {
    SroodToastType.success => Icons.check_circle_rounded,
    SroodToastType.error   => Icons.error_rounded,
    SroodToastType.warning => Icons.warning_amber_rounded,
    SroodToastType.info    => Icons.info_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Positioned(
        left: 16,
        right: 16,
        bottom: bottom + 24 + _slideY.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Material(
            color: Colors.transparent,
            child: _ToastCard(
              message: widget.message,
              accent: _accent,
              icon: _icon,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.message,
    required this.accent,
    required this.icon,
  });
  final String message;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16052E),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Left accent bar
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Container(width: 3, color: accent),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}
