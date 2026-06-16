import 'package:flutter/material.dart';

/// Animated emoji that floats centered over a mic seat avatar for 3 seconds.
class SeatReactionOverlay extends StatefulWidget {
  const SeatReactionOverlay({
    super.key,
    required this.emoji,
    required this.onExpired,
  });

  final String emoji;
  final VoidCallback onExpired;

  @override
  State<SeatReactionOverlay> createState() => _SeatReactionOverlayState();
}

class _SeatReactionOverlayState extends State<SeatReactionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 7),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 76),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 17),
    ]).animate(_ctrl);

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.3, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 4,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 69),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.4)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 17,
      ),
    ]).animate(_ctrl);

    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onExpired();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: child,
          ),
        ),
        child: Text(
          widget.emoji,
          style: const TextStyle(fontSize: 28, height: 1.0),
        ),
      ),
    );
  }
}
