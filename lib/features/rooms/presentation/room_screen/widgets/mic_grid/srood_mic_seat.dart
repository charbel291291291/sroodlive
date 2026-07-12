/// One complete mic-seat tile: a fixed-size shell containing the avatar zone
/// and a fixed-height label strip (name, support, role badge).
///
/// Layout invariants (the core v2 contract):
///  - The tile is always laid out inside `tileWidth` × `tileHeight` supplied
///    by the grid — identical for empty and occupied seats.
///  - The avatar zone is always `avatarAreaHeight` tall and the circle is
///    always `seatSize` in diameter, regardless of occupancy, VIP frame,
///    speaking state, or mute state.
///  - Label rows use fixed slot heights so a joining user never shifts rows.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/room_member.dart';
import '../../../../models/room_reaction.dart';
import '../../../../utils/vip_room_features.dart';
import '../../../../widgets/pk_stage_overlay.dart';
import '../../../../widgets/seat_reaction_overlay.dart';
import '../../../theme/srood_room_theme.dart';
import 'srood_empty_mic_seat.dart';
import 'srood_occupied_mic_seat.dart';
import 'srood_stage_seat.dart';
import 'srood_support_pill.dart';

class SroodMicSeat extends StatelessWidget {
  const SroodMicSeat({
    required this.seat,
    required this.isArabic,
    required this.isHost,
    required this.isSpeaking,
    required this.isModerator,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
    required this.onOccupiedSeatLongPress,
    required this.onProfileTap,
    required this.selectedForMove,
    required this.roomLevel,
    required this.seatSize,
    required this.avatarAreaHeight,
    required this.tileHeight,
    this.pkTeam,
    this.activeReaction,
    super.key,
  });

  final SroodStageSeat seat;
  final bool isArabic;
  final bool isHost;
  final bool isSpeaking;
  final bool isModerator;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;
  final void Function(RoomMember member, int seatNumber)
  onOccupiedSeatLongPress;
  final ValueChanged<String> onProfileTap;
  final bool selectedForMove;
  final int roomLevel;
  final double seatSize;
  final double avatarAreaHeight;
  final double tileHeight;

  /// 'a', 'b', or null — non-null only when PK is active and seat is assigned.
  final String? pkTeam;
  final RoomReaction? activeReaction;

  @override
  Widget build(BuildContext context) {
    final canAssignSeat = seat.isEmpty;
    final canManageSeat = !seat.isEmpty && isHost && seat.member != null;
    final isHostSeat = seat.isHostSeat;
    final vipLevel = seat.member?.effectiveVipLevel ?? 0;

    final Color? pkColor = pkTeam == 'a'
        ? kPkRed
        : pkTeam == 'b'
        ? kPkBlue
        : null;

    // Badge only for load-bearing states; empty seats show none.
    final badge = selectedForMove
        ? (isArabic ? 'نقل' : 'Move')
        : seat.isEmpty
        ? ''
        : isHostSeat
        ? (isArabic ? 'مضيف' : 'Host')
        : pkTeam == 'a'
        ? 'A'
        : pkTeam == 'b'
        ? 'B'
        : '';

    final compactSeat = seatSize < 70;
    final hasSupport = seat.supportAmount > 0;
    final hasBadge = badge.isNotEmpty;

    // Fixed slot heights derived from the label strip budget — identical math
    // for empty and occupied seats so rows never shift.
    final remainingHeight = math.max(0.0, tileHeight - avatarAreaHeight);
    final labelGap = remainingHeight >= 30 ? 2.0 : 1.0;
    final bottomSpacer = remainingHeight >= 34 ? 3.0 : 1.0;
    final supportSlotHeight = hasSupport
        ? (remainingHeight >= 38 ? 12.0 : 10.0)
        : 0.0;
    final badgeSlotHeight = hasBadge
        ? (remainingHeight >= 34 ? 11.0 : 9.0)
        : 0.0;
    final nameSlotHeight = seat.isEmpty
        ? 0.0
        : math
              .max(
                9.0,
                remainingHeight -
                    labelGap -
                    supportSlotHeight -
                    badgeSlotHeight -
                    bottomSpacer,
              )
              .clamp(9.0, compactSeat ? 12.0 : 14.0);

    // ── Avatar zone: fixed height, fixed circle diameter ─────────────────────
    final Widget avatarZone = GestureDetector(
      onTap: seat.isLocked
          ? (isHost ? () => onEmptySeatTap(seat.number) : null)
          : canAssignSeat
          ? () => onEmptySeatTap(seat.number)
          : canManageSeat
          ? () => onOccupiedSeatTap(seat.member!, seat.number)
          : null,
      onLongPress: canManageSeat
          ? () => onOccupiedSeatLongPress(seat.member!, seat.number)
          : null,
      child: SizedBox(
        height: avatarAreaHeight,
        child: Center(
          child: SizedBox(
            width: seatSize,
            height: seatSize,
            child: seat.isEmpty
                ? SroodEmptyMicSeat(
                    seat: seat,
                    outerSize: seatSize,
                    roomLevel: roomLevel,
                    iconSize: compactSeat ? 28 : 30,
                  )
                : SroodOccupiedMicSeat(
                    seat: seat,
                    outerSize: seatSize,
                    roomLevel: roomLevel,
                    isSpeaking: isSpeaking,
                    selectedForMove: selectedForMove,
                    onProfileTap: onProfileTap,
                    pkColor: pkColor,
                  ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Zone 1: avatar + floating reaction overlay ──────────────────────
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            avatarZone,
            if (activeReaction != null && activeReaction!.isActive)
              SeatReactionOverlay(
                key: ValueKey(activeReaction!.expiresAt),
                emoji: activeReaction!.emoji,
                onExpired: () {},
              ),
          ],
        ),

        // ── Zone 2: name + inline moderator capsule ─────────────────────────
        if (nameSlotHeight > 0) ...[
          SizedBox(height: labelGap),
          SizedBox(
            height: nameSlotHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    seat.isEmpty ? '' : seat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compactSeat ? 8.5 : 9.5,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      color: seat.isEmpty
                          ? Colors.white.withValues(alpha: 0.38)
                          : vipLevel > 0
                          ? VipVisualStyle.nameColor(vipLevel, context)
                          : Colors.white.withValues(alpha: 0.88),
                      shadows: [
                        const Shadow(
                          blurRadius: 5,
                          color: Colors.black87,
                          offset: Offset(0, 1),
                        ),
                        Shadow(
                          blurRadius: 10,
                          color: Colors.black.withValues(alpha: 0.50),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isModerator && !isHostSeat && nameSlotHeight >= 12) ...[
                  const SizedBox(width: 3),
                  Container(
                    width: 16,
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF25063F), Color(0xFF0F041C)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color.fromRGBO(232, 192, 80, 0.65),
                        width: 0.8,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(232, 192, 80, 0.25),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      size: 10,
                      color: Color(0xFFFFD86B),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── Zone 3: support pill (slot reserved only when present) ──────────
        SizedBox(
          height: supportSlotHeight,
          child: hasSupport
              ? Center(
                  child: SroodSupportPill(
                    amount: seat.supportAmount,
                    compact: true,
                  ),
                )
              : null,
        ),

        // ── Zone 4: role badge ──────────────────────────────────────────────
        SizedBox(
          height: badgeSlotHeight,
          child: badge.isEmpty
              ? null
              : Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compactSeat ? 4 : 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selectedForMove
                          ? SroodRoomColors.seatMove.withValues(alpha: 0.20)
                          : isHostSeat
                          ? SroodRoomColors.gold.withValues(alpha: 0.18)
                          : pkColor != null
                          ? pkColor.withValues(alpha: 0.22)
                          : SroodRoomColors.violetSoft.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(
                        SroodRoomDims.radiusPill,
                      ),
                      border: Border.all(
                        color: selectedForMove
                            ? SroodRoomColors.seatMove.withValues(alpha: 0.8)
                            : isHostSeat
                            ? SroodRoomColors.gold.withValues(alpha: 0.7)
                            : pkColor != null
                            ? pkColor.withValues(alpha: 0.85)
                            : SroodRoomColors.violetSoft.withValues(alpha: 0.4),
                        width: pkColor != null ? 1.0 : 0.7,
                      ),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compactSeat ? 6.5 : 7.5,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        color: selectedForMove
                            ? SroodRoomColors.seatMove
                            : isHostSeat
                            ? SroodRoomColors.gold
                            : pkColor ?? Colors.white.withValues(alpha: 0.75),
                        shadows: const [
                          Shadow(blurRadius: 4, color: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
        ),

        // ── Zone 5: bottom spacer ───────────────────────────────────────────
        SizedBox(height: bottomSpacer),
      ],
    );
  }
}
