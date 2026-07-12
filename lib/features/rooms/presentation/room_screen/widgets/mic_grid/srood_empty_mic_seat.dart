/// Empty / locked mic seat — visual identity driven by the room's earned
/// level theme (10 tiers). The circle is always exactly `outerSize` in
/// diameter; glow and pulse render via shadows and never affect layout.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_seat_level_theme.dart';
import 'srood_stage_seat.dart';

class SroodEmptyMicSeat extends StatefulWidget {
  const SroodEmptyMicSeat({
    required this.seat,
    required this.outerSize,
    required this.roomLevel,
    required this.iconSize,
    super.key,
  });

  final SroodStageSeat seat;
  final double outerSize;
  final int roomLevel;
  final double iconSize;

  @override
  State<SroodEmptyMicSeat> createState() => _SroodEmptyMicSeatState();
}

class _SroodEmptyMicSeatState extends State<SroodEmptyMicSeat>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  @override
  void initState() {
    super.initState();
    _initPulse();
  }

  @override
  void didUpdateWidget(SroodEmptyMicSeat old) {
    super.didUpdateWidget(old);
    if (old.roomLevel != widget.roomLevel ||
        old.seat.isLocked != widget.seat.isLocked) {
      _pulseCtrl?.dispose();
      _pulseCtrl = null;
      _pulseAnim = null;
      _initPulse();
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  void _initPulse() {
    final theme = SroodSeatLevelTheme.forLevel(
      widget.seat.isLocked ? 0 : widget.roomLevel,
    );
    if (!theme.pulseGlow) return;
    // Honor reduced-motion: skip the ambient pulse entirely.
    final reduceMotion =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    if (reduceMotion) return;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.60,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut));
  }

  @override
  Widget build(BuildContext context) {
    final theme = SroodSeatLevelTheme.forLevel(
      widget.seat.isLocked ? 0 : widget.roomLevel,
    );
    final outerSize = widget.outerSize;
    final isLocked = widget.seat.isLocked;

    final Widget seatCircle = Semantics(
      label: isLocked
          ? 'Locked seat ${widget.seat.number}'
          : 'Empty seat ${widget.seat.number}',
      button: true,
      child: Container(
        width: outerSize,
        height: outerSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.0,
            colors: theme.bgColors,
          ),
          border: Border.all(
            color: theme.borderColor,
            width: theme.borderWidth,
          ),
          boxShadow: [
            BoxShadow(color: theme.glowColor, blurRadius: theme.glowBlur),
            if (theme.outerHaloBlur > 0 && _pulseAnim == null)
              BoxShadow(
                color: theme.outerHaloColor,
                blurRadius: theme.outerHaloBlur,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Inner accent ring (L3+, not locked)
            if (theme.innerRingOpacity > 0 && !isLocked)
              Container(
                width: outerSize * 0.72,
                height: outerSize * 0.72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.accentColor.withValues(
                      alpha: theme.innerRingOpacity,
                    ),
                    width: 0.8,
                  ),
                ),
              ),
            // Shimmer highlight spot — bright cap at top of circle (L6+)
            if (theme.highlightOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.65),
                        radius: 0.55,
                        colors: [
                          Color.fromRGBO(
                            255,
                            255,
                            255,
                            theme.highlightOpacity,
                          ),
                          const Color(0x00FFFFFF),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Icon + seat number
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLocked ? Icons.lock_rounded : Icons.mic_rounded,
                  color: theme.iconColor,
                  size: widget.iconSize,
                ),
                const SizedBox(height: 1),
                Text(
                  '${widget.seat.number}',
                  style: TextStyle(
                    color: theme.iconColor.withValues(
                      alpha: isLocked ? 0.50 : 0.65,
                    ),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // L7+ animated pulse: animated outer halo, layout-neutral (shadows only).
    final Animation<double>? pulse = _pulseAnim;
    if (pulse == null) return seatCircle;

    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: Container(
              width: outerSize + 8,
              height: outerSize + 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.outerHaloColor,
                    blurRadius: theme.outerHaloBlur * pulse.value,
                    spreadRadius: 2.0 * pulse.value,
                  ),
                ],
              ),
            ),
          ),
          child!,
        ],
      ),
      child: seatCircle,
    );
  }
}
