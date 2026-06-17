import 'package:flutter/material.dart';

import '../../../core/vip/vip_spec.dart';
import '../models/user_vip.dart';

/// Displays a slide-in banner announcing a VIP user entering the room.
/// Auto-dismisses after the spec-defined duration.
class VipEntranceEffect extends StatefulWidget {
  const VipEntranceEffect({
    required this.userVip,
    required this.username,
    required this.avatarUrl,
    this.onDismissed,
    super.key,
  });

  final UserVip userVip;
  final String username;
  final String? avatarUrl;
  final VoidCallback? onDismissed;

  @override
  State<VipEntranceEffect> createState() => _VipEntranceEffectState();
}

class _VipEntranceEffectState extends State<VipEntranceEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  late final VipSpec _spec;

  @override
  void initState() {
    super.initState();
    _spec = VipSpecResolver.resolve(widget.userVip.effectiveVipLevel);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    _ctrl.forward();
    Future.delayed(_spec.entranceDuration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) {
      widget.onDismissed?.call();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.userVip.hasVip) return const SizedBox.shrink();

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: _dismiss,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _spec.bannerGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: _spec.buildGlowShadows(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.avatarUrl != null)
                  Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _spec.avatarRingColor,
                        width: _spec.avatarRingWidth,
                      ),
                      image: DecorationImage(
                        image: NetworkImage(widget.avatarUrl!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.username,
                      style: TextStyle(
                        color: _spec.entryTextColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _spec.badgeLabel,
                      style: TextStyle(
                        color: _spec.entryTextColor.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
