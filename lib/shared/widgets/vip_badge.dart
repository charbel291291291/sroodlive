import 'package:flutter/material.dart';

import '../../core/vip/vip_spec.dart';
import '../../features/rooms/utils/vip_room_features.dart';

class VipBadge extends StatelessWidget {
  const VipBadge({
    required this.vipLevel,
    this.compact = false,
    this.isHostVisibleMarker = false,
    super.key,
  });

  final int vipLevel;
  final bool compact;
  final bool isHostVisibleMarker;

  @override
  Widget build(BuildContext context) {
    if (vipLevel <= 0) return const SizedBox.shrink();

    final spec  = VipSpecResolver.resolve(vipLevel);
    final label = isHostVisibleMarker
        ? '${VipFeatures.vipLabel(vipLevel)} Protected'
        : VipFeatures.vipLabel(vipLevel);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: spec.badgeGradient),
        borderRadius: BorderRadius.circular(999),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: spec.glowColor
                      .withValues(alpha: spec.glowIntensity * 0.55),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            spec.badgeIcon,
            color: spec.badgeTextColor,
            size: compact ? 9 : 12,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: spec.badgeTextColor,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 8 : 10,
            ),
          ),
        ],
      ),
    );
  }
}
