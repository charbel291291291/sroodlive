/// Main stage: stage header row (live counts / participants) or PK banner,
/// the PK result banner, and the fixed-shell mic grid with an optional PK
/// team backdrop split.
library;

import 'package:flutter/material.dart';

import '../../../../models/pk_session.dart';
import '../../../../models/room_member.dart';
import '../../../../models/room_reaction.dart';
import '../../../../widgets/pk_stage_overlay.dart';
import '../../../../widgets/room_details/room_status_badges.dart';
import '../../../theme/srood_room_theme.dart';
import '../mic_grid/srood_mic_grid.dart';

class SroodRoomStage extends StatelessWidget {
  const SroodRoomStage({
    required this.members,
    required this.maxSeats,
    required this.isArabic,
    required this.activeSpeakerCount,
    required this.isHost,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
    required this.onOccupiedSeatLongPress,
    required this.onProfileTap,
    required this.memberCount,
    required this.onParticipantsTap,
    required this.supportByUserId,
    required this.selectedMoveUserId,
    required this.speakingUserIds,
    required this.moderatorUserIds,
    required this.closedSeats,
    required this.roomLevel,
    this.activePk,
    this.showPkResult = false,
    this.pkResult,
    this.onPkFinish,
    this.onPkResultClose,
    this.seatReactions = const {},
    super.key,
  });

  final List<RoomMember> members;
  final int maxSeats;
  final bool isArabic;
  final int activeSpeakerCount;
  final bool isHost;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;
  final void Function(RoomMember member, int seatNumber)
  onOccupiedSeatLongPress;
  final ValueChanged<String> onProfileTap;
  final int memberCount;
  final VoidCallback onParticipantsTap;
  final Map<String, int> supportByUserId;
  final String? selectedMoveUserId;
  final Set<String> speakingUserIds;
  final Set<String> moderatorUserIds;
  final Set<int> closedSeats;
  final int roomLevel;
  final PkSession? activePk;
  final bool showPkResult;
  final PkSession? pkResult;
  final VoidCallback? onPkFinish;
  final VoidCallback? onPkResultClose;
  final Map<int, RoomReaction> seatReactions;

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SroodRoomDims.space2,
        SroodRoomDims.space4,
        SroodRoomDims.space2,
        SroodRoomDims.space6,
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          // ── Header: PK banner OR compact live status row ────────────────
          if (activePk != null)
            PkBanner(
              session: activePk!,
              isArabic: isArabic,
              isHost: isHost,
              onFinish: onPkFinish ?? () {},
            )
          else
            Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Expanded(
                  child: Row(
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      // Live dot
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: SroodRoomColors.live,
                        ),
                      ),
                      const SizedBox(width: SroodRoomDims.space4),
                      Flexible(
                        child: Text(
                          '$activeSpeakerCount/$maxSeats',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SroodRoomText.caption.copyWith(
                            fontSize: SroodRoomDims.textSm,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                      const SizedBox(width: SroodRoomDims.space6),
                      RoomParticipantsChip(
                        count: memberCount,
                        isArabic: isArabic,
                        onTap: onParticipantsTap,
                      ),
                    ],
                  ),
                ),
                // Animated EQ medallion — cyan/violet glass in v2.
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        SroodRoomColors.violet,
                        SroodRoomColors.electric,
                      ],
                    ),
                    boxShadow: SroodRoomDecor.glow(
                      SroodRoomColors.violet,
                      opacity: 0.35,
                    ),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          const SizedBox(height: SroodRoomDims.space12),

          // ── PK result banner ─────────────────────────────────────────────
          if (showPkResult && pkResult != null) ...[
            PkResultBanner(
              session: pkResult!,
              isArabic: isArabic,
              onClose: onPkResultClose ?? () {},
            ),
            const SizedBox(height: SroodRoomDims.space12),
          ],

          // ── Seat grid with optional PK team backdrop split ───────────────
          Expanded(
            child: Stack(
              children: [
                if (activePk != null)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        SroodRoomDims.radiusLg,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    kPkRed.withValues(alpha: 0.09),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.transparent,
                                    kPkBlue.withValues(alpha: 0.09),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SroodMicGrid(
                  members: members,
                  maxSeats: maxSeats,
                  isArabic: isArabic,
                  isHost: isHost,
                  onEmptySeatTap: onEmptySeatTap,
                  onOccupiedSeatTap: onOccupiedSeatTap,
                  onOccupiedSeatLongPress: onOccupiedSeatLongPress,
                  onProfileTap: onProfileTap,
                  supportByUserId: supportByUserId,
                  selectedMoveUserId: selectedMoveUserId,
                  speakingUserIds: speakingUserIds,
                  moderatorUserIds: moderatorUserIds,
                  closedSeats: closedSeats,
                  roomLevel: roomLevel,
                  activePk: activePk,
                  seatReactions: seatReactions,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
