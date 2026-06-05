import 'package:flutter/material.dart';

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
    if (vipLevel <= 0) {
      return const SizedBox.shrink();
    }

    final label = isHostVisibleMarker
        ? '${VipFeatures.vipLabel(vipLevel)} Protected'
        : VipFeatures.vipLabel(vipLevel);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: VipVisualStyle.gradient(vipLevel)),
        borderRadius: BorderRadius.circular(999),
        boxShadow: VipVisualStyle.glow(vipLevel, compact: true),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            vipLevel >= 5
                ? Icons.workspace_premium_rounded
                : vipLevel >= 4
                ? Icons.diamond_rounded
                : Icons.auto_awesome_rounded,
            color: const Color(0xFF160B26),
            size: compact ? 9 : 12,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF160B26),
              fontWeight: FontWeight.w900,
              fontSize: compact ? 8 : 10,
            ),
          ),
        ],
      ),
    );
  }
}
