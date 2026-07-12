/// Fixed-shell mic grid for 6 / 8 / 9 / 12 seat layouts.
///
/// Sizing contract: one [SroodSeatSpec] per layout mode resolves a single
/// seat diameter and tile box from the available constraints; every seat in
/// the grid — empty, occupied, host, VIP, speaking — uses that exact shell.
/// Rows are aligned with fixed gaps; a partial last row centers its seats.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/pk_session.dart';
import '../../../../models/room_member.dart';
import '../../../../models/room_reaction.dart';
import '../../../../widgets/pk_stage_overlay.dart';
import '../../../theme/srood_room_theme.dart';
import 'srood_mic_seat.dart';
import 'srood_stage_seat.dart';

class SroodMicGrid extends StatelessWidget {
  const SroodMicGrid({
    required this.members,
    required this.maxSeats,
    required this.isArabic,
    required this.isHost,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
    required this.onOccupiedSeatLongPress,
    required this.onProfileTap,
    required this.supportByUserId,
    required this.selectedMoveUserId,
    required this.speakingUserIds,
    required this.moderatorUserIds,
    required this.closedSeats,
    required this.roomLevel,
    this.activePk,
    this.seatReactions = const {},
    super.key,
  });

  final List<RoomMember> members;
  final int maxSeats;
  final bool isArabic;
  final bool isHost;
  final ValueChanged<int> onEmptySeatTap;
  final void Function(RoomMember member, int seatNumber) onOccupiedSeatTap;
  final void Function(RoomMember member, int seatNumber)
  onOccupiedSeatLongPress;
  final ValueChanged<String> onProfileTap;
  final Map<String, int> supportByUserId;
  final String? selectedMoveUserId;
  final Set<String> speakingUserIds;
  final Set<String> moderatorUserIds;
  final Set<int> closedSeats;
  final int roomLevel;
  final PkSession? activePk;
  final Map<int, RoomReaction> seatReactions;

  List<SroodStageSeat> _buildSeats() {
    final safeMaxSeats = maxSeats <= 0 ? 12 : maxSeats;
    final seats = List<SroodStageSeat>.generate(
      safeMaxSeats,
      (index) => SroodStageSeat.empty(
        index + 1,
        isLocked: closedSeats.contains(index + 1),
      ),
    );

    final stageMembers = members
        .where((member) => member.role == 'host' || member.role == 'speaker')
        .toList();

    for (final member in stageMembers) {
      final preferredSeat = member.seatNumber;

      if (preferredSeat != null &&
          preferredSeat >= 1 &&
          preferredSeat <= safeMaxSeats &&
          seats[preferredSeat - 1].isEmpty) {
        seats[preferredSeat - 1] = SroodStageSeat.fromMember(
          number: preferredSeat,
          member: member,
          isArabic: isArabic,
          supportAmount: supportByUserId[member.userId] ?? 0,
          isLocked: closedSeats.contains(preferredSeat),
        );
        continue;
      }

      final emptyIndex = seats.indexWhere((seat) => seat.isEmpty);
      if (emptyIndex != -1) {
        seats[emptyIndex] = SroodStageSeat.fromMember(
          number: emptyIndex + 1,
          member: member,
          isArabic: isArabic,
          supportAmount: supportByUserId[member.userId] ?? 0,
          isLocked: closedSeats.contains(emptyIndex + 1),
        );
      }
    }

    return seats;
  }

  @override
  Widget build(BuildContext context) {
    final seats = _buildSeats();
    final spec = SroodSeatSpec.forSeatCount(seats.length);
    final cols = spec.columns;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = <List<SroodStageSeat>>[];
        for (var i = 0; i < seats.length; i += cols) {
          final end = (i + cols).clamp(0, seats.length);
          rows.add(seats.sublist(i, end));
        }

        final rowCount = rows.isEmpty ? 1 : rows.length;
        final preferredGap = cols >= 4 ? 2.0 : 18.0;
        final preferredRowGap = rowCount >= 4 ? 4.0 : 10.0;

        final availableSeatWidth =
            (constraints.maxWidth - preferredGap * (cols - 1)) / cols;
        final minSeatBoxWidth = seats.length > 12 ? 54.0 : spec.min;
        final availableSeatHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - preferredRowGap * (rowCount - 1)) /
                  rowCount
            : spec.tileMaxHeight;

        final seatBoxWidth = math
            .min(availableSeatWidth, spec.tileMaxWidth)
            .clamp(minSeatBoxWidth, spec.tileMaxWidth);
        final tileHeight = math
            .min(availableSeatHeight, spec.tileMaxHeight)
            .clamp(spec.min, spec.tileMaxHeight);

        // Resolve ONE diameter for every seat in this layout.
        final maximumFittingSeatSize = math.max(
          0.0,
          math.min(seatBoxWidth, tileHeight - spec.labelAreaHeight),
        );
        final responsiveMin = math.min(spec.min, maximumFittingSeatSize);
        final seatSize = math
            .min(spec.preferred, maximumFittingSeatSize)
            .clamp(responsiveMin, spec.max);

        final colGap = cols <= 1
            ? 0.0
            : math.max(
                0.0,
                math.min(
                  preferredGap,
                  (constraints.maxWidth - seatBoxWidth * cols) / (cols - 1),
                ),
              );
        final rowGap = rowCount <= 1
            ? 0.0
            : math.max(
                0.0,
                math.min(
                  preferredRowGap,
                  (constraints.maxHeight - tileHeight * rowCount) /
                      (rowCount - 1),
                ),
              );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: rowGap),
              _buildRow(rows[r], cols, seatBoxWidth, tileHeight, colGap,
                  seatSize),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRow(
    List<SroodStageSeat> row,
    int cols,
    double tileWidth,
    double tileHeight,
    double gap,
    double seatSize,
  ) {
    final isFull = row.length == cols;
    return Row(
      mainAxisAlignment: isFull
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.center,
      children: [
        for (var c = 0; c < row.length; c++) ...[
          if (c > 0) SizedBox(width: gap),
          // RepaintBoundary isolates each seat's animation from its
          // neighbours so speaking waves never propagate repaints.
          RepaintBoundary(
            child: SizedBox(
              width: tileWidth,
              height: tileHeight,
              child: SroodMicSeat(
                seat: row[c],
                isArabic: isArabic,
                isHost: isHost,
                isSpeaking: speakingUserIds.contains(
                  row[c].member?.userId ?? '',
                ),
                isModerator: moderatorUserIds.contains(
                  row[c].member?.userId ?? '',
                ),
                onEmptySeatTap: onEmptySeatTap,
                onOccupiedSeatTap: onOccupiedSeatTap,
                onOccupiedSeatLongPress: onOccupiedSeatLongPress,
                onProfileTap: onProfileTap,
                selectedForMove:
                    selectedMoveUserId != null &&
                    row[c].member?.userId == selectedMoveUserId,
                roomLevel: roomLevel,
                seatSize: seatSize,
                avatarAreaHeight: seatSize,
                tileHeight: tileHeight,
                pkTeam: pkSeatTeam(row[c].member?.userId ?? '', activePk),
                activeReaction: seatReactions[row[c].number],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
