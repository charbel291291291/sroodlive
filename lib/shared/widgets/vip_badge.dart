import 'package:flutter/material.dart';

import '../../core/vip/vip_prestige.dart';
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

    final prestige = VipVisualResolver.resolve(vipLevel);
    final label = isHostVisibleMarker
        ? '${VipFeatures.vipLabel(vipLevel)} Protected'
        : VipFeatures.vipLabel(vipLevel);

    final badgeIcon = vipLevel >= 9
        ? Icons.local_fire_department_rounded
        : vipLevel >= 7
            ? Icons.workspace_premium_rounded
            : vipLevel >= 5
                ? Icons.diamond_rounded
                : Icons.auto_awesome_rounded;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: prestige.badgeGradient),
        borderRadius: BorderRadius.circular(999),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: prestige.glowColor
                      .withValues(alpha: prestige.glowIntensity * 0.55),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badgeIcon,
            color: prestige.badgeTextColor,
            size: compact ? 9 : 12,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: prestige.badgeTextColor,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 8 : 10,
            ),
          ),
        ],
      ),
    );
  }
}
