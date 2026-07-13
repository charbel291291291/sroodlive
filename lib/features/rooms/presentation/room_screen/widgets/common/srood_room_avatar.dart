/// Circular avatar with optional frame, VIP badge, agent marker, and gold
/// selection ring — shared by chat rows, the gift receiver rail, and the
/// participants sheet.
library;

import 'package:flutter/material.dart';

import '../../../../../../shared/widgets/avatar_with_frame.dart';
import '../../../../widgets/agent_identity_badge.dart';
import '../../../theme/srood_room_theme.dart';

class SroodRoomAvatar extends StatelessWidget {
  const SroodRoomAvatar({
    required this.avatarUrl,
    required this.frameKey,
    required this.vipLevel,
    required this.size,
    required this.selected,
    required this.fallbackIcon,
    this.isOfficialAgent = false,
    this.onTap,
    super.key,
  });

  final String? avatarUrl;
  final String? frameKey;
  final int vipLevel;
  final double size;
  final bool selected;
  final IconData fallbackIcon;
  final bool isOfficialAgent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? SroodRoomColors.gold : Colors.transparent,
                width: 2,
              ),
            ),
            child: AvatarWithFrame(
              imageUrl: avatarUrl,
              radius: (size - 4) / 2,
              frameKey: frameKey,
              vipLevel: vipLevel,
              showVipBadge: vipLevel > 0 && size >= 42,
              fallbackIcon: fallbackIcon,
            ),
          ),
          if (isOfficialAgent)
            Positioned(
              top: -1,
              right: -1,
              child: AgentAvatarMarker(size: size >= 40 ? 16 : 12),
            ),
        ],
      ),
    );

    if (onTap == null) {
      return avatar;
    }

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: avatar,
    );
  }
}
