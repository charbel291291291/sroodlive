/// Occupied mic seat avatar stack — glass backing, seat ring, VIP wave ring,
/// framed avatar, agent marker, and mute badge. Rendered inside the fixed
/// `outerSize` shell owned by [SroodMicSeat]; every layer here is either
/// exactly `outerSize` or positioned with Clip.none so occupying a seat can
/// never change the measured tile size.
library;

import 'package:flutter/material.dart';

import '../../../../../vip/widgets/vip_mic_wave_ring.dart';
import '../../../../../../shared/widgets/avatar_with_frame.dart';
import '../../../../widgets/agent_identity_badge.dart';
import '../../../../widgets/pk_stage_overlay.dart';
import '../../../theme/srood_room_theme.dart';
import '../../../theme/srood_seat_level_theme.dart';
import 'srood_stage_seat.dart';

class SroodOccupiedMicSeat extends StatelessWidget {
  const SroodOccupiedMicSeat({
    required this.seat,
    required this.outerSize,
    required this.roomLevel,
    required this.isSpeaking,
    required this.selectedForMove,
    required this.onProfileTap,
    this.pkColor,
    super.key,
  });

  final SroodStageSeat seat;
  final double outerSize;
  final int roomLevel;
  final bool isSpeaking;
  final bool selectedForMove;
  final ValueChanged<String> onProfileTap;

  /// PK team color ('a'=red / 'b'=blue) or null when no PK is active.
  final Color? pkColor;

  @override
  Widget build(BuildContext context) {
    final levelTheme = SroodSeatLevelTheme.forLevel(roomLevel);
    final isHostSeat = seat.isHostSeat;
    final vipLevel = seat.member?.effectiveVipLevel ?? 0;
    final avatarRadius = (outerSize - 8) / 2;

    final Color borderColor = selectedForMove
        ? SroodRoomColors.seatMove
        : isHostSeat
        ? SroodRoomColors.seatHost
        : pkColor != null
        ? pkColor!.withValues(alpha: 0.85)
        : SroodRoomColors.seatOccupied.withValues(alpha: 0.55);

    final double borderWidth = isHostSeat
        ? SroodRoomDims.borderSeatHost
        : SroodRoomDims.borderSeat;

    // Single soft glow per state — v2 keeps glow minimal.
    final List<BoxShadow> glowShadows = selectedForMove
        ? SroodRoomDecor.glow(SroodRoomColors.seatMove, opacity: 0.55)
        : isHostSeat
        ? SroodRoomDecor.glow(SroodRoomColors.seatHost, opacity: 0.50)
        : pkColor != null
        ? SroodRoomDecor.glow(pkColor!, opacity: 0.50)
        : [
            BoxShadow(
              color: levelTheme.occupiedGlowColor,
              blurRadius: levelTheme.occupiedGlowBlur,
            ),
          ];

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // PK team pulse ring (behind avatar during active PK).
        if (pkColor != null)
          IgnorePointer(
            child: PkPulseRing(color: pkColor!, radius: outerSize / 2 + 4),
          ),

        // Dark glass backing — keeps the avatar readable over any background.
        IgnorePointer(
          child: Container(
            width: outerSize,
            height: outerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.22),
                ],
              ),
            ),
          ),
        ),

        // Seat ring + glow. A VIP frame supplies its own ring, so the plain
        // border only paints for non-VIP members.
        IgnorePointer(
          child: Container(
            width: outerSize,
            height: outerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: vipLevel == 0
                  ? Border.all(color: borderColor, width: borderWidth)
                  : null,
              boxShadow: glowShadows,
            ),
          ),
        ),

        // VIP mic wave ring — expands outward via Clip.none, layout-neutral.
        IgnorePointer(
          child: VipMicWaveRing(
            vipLevel: vipLevel,
            isActive: !seat.isMuted && isSpeaking,
            isHost: isHostSeat,
            outerSize: outerSize,
          ),
        ),

        // Avatar + frame (centered inside the seat ring).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: seat.member == null
              ? null
              : () => onProfileTap(seat.member!.userId),
          child: Semantics(
            label: seat.name.isEmpty ? 'Seat ${seat.number}' : seat.name,
            button: true,
            child: AvatarWithFrame(
              imageUrl: seat.member?.avatarUrl,
              radius: avatarRadius,
              frameKey: seat.member?.selectedAvatarFrameKey,
              vipLevel: vipLevel,
              showVipBadge: false,
              compact: !isHostSeat,
              fallbackIcon: Icons.person_rounded,
            ),
          ),
        ),

        if (seat.member?.isOfficialAgent == true)
          const Positioned(
            top: -2,
            right: -2,
            child: AgentAvatarMarker(size: 17),
          ),

        // Mute badge — overlays the ring, never affects layout.
        if (seat.isMuted)
          Positioned(
            bottom: 1,
            right: 1,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SroodRoomColors.mutedMic.withValues(alpha: 0.85),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.85),
                  width: 1.4,
                ),
              ),
              child: const Icon(
                Icons.mic_off_rounded,
                color: Colors.white,
                size: 11,
              ),
            ),
          ),
      ],
    );
  }
}
