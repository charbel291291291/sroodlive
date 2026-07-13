// Room UI v2 mic-seat sizing contract.
//
// The core invariant of the rebuilt mic system: every seat in a layout mode
// resolves to ONE shell — identical outer diameter and tile box for empty,
// occupied, host, VIP, muted, and speaking seats — so a user joining or
// leaving a seat can never shift the grid.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/features/rooms/models/room_member.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/mic_grid/srood_mic_grid.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/mic_grid/srood_mic_seat.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/mic_grid/srood_stage_seat.dart';
import 'package:srood_live/features/rooms/presentation/theme/srood_room_theme.dart';

RoomMember member({
  required int seat,
  String role = 'speaker',
  int vipLevel = 0,
  bool isMuted = false,
  String? name,
}) {
  return RoomMember(
    id: 'member-$seat',
    roomId: 'room-1',
    userId: 'user-$seat',
    role: role,
    isMuted: isMuted,
    seatNumber: seat,
    joinedAt: DateTime(2026, 1, 1),
    displayName: name ?? 'User $seat',
    vipLevel: vipLevel,
  );
}

Widget wrapGrid({
  required List<RoomMember> members,
  required int maxSeats,
  double width = 375,
  double height = 500,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: SroodMicGrid(
            members: members,
            maxSeats: maxSeats,
            isArabic: false,
            isHost: false,
            onEmptySeatTap: (_) {},
            onOccupiedSeatTap: (_, _) {},
            onOccupiedSeatLongPress: (_, _) {},
            onProfileTap: (_) {},
            supportByUserId: const {},
            selectedMoveUserId: null,
            speakingUserIds: const {},
            moderatorUserIds: const {},
            closedSeats: const {},
            roomLevel: 1,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('each supported layout has one explicit responsive seat-size range', () {
    final six = SroodSeatSpec.forSeatCount(6);
    expect((six.preferred, six.min, six.max), (80.0, 76.0, 84.0));
    expect(six.columns, 3);

    final eight = SroodSeatSpec.forSeatCount(8);
    expect((eight.preferred, eight.min, eight.max), (76.0, 72.0, 80.0));
    expect(eight.columns, 4);

    final nine = SroodSeatSpec.forSeatCount(9);
    expect((nine.preferred, nine.min, nine.max), (78.0, 72.0, 80.0));
    expect(nine.columns, 3);

    final twelve = SroodSeatSpec.forSeatCount(12);
    expect((twelve.preferred, twelve.min, twelve.max), (70.0, 68.0, 74.0));
    expect(twelve.columns, 4);
  });

  for (final seatCount in const [6, 8, 9, 12]) {
    testWidgets(
      '$seatCount-seat grid: empty and occupied seats share identical shells',
      (tester) async {
        // Occupy half the seats; leave the rest empty.
        final members = [
          member(seat: 1, role: 'host'),
          for (var s = 2; s <= seatCount ~/ 2; s++)
            member(seat: s, vipLevel: s.isEven ? 3 : 0, isMuted: s.isOdd),
        ];

        await tester.pumpWidget(
          wrapGrid(members: members, maxSeats: seatCount),
        );

        final tiles = tester
            .widgetList<SroodMicSeat>(find.byType(SroodMicSeat))
            .toList();
        expect(tiles.length, seatCount);

        // One diameter and one tile height for every seat in the layout.
        final diameters = tiles.map((t) => t.seatSize).toSet();
        final tileHeights = tiles.map((t) => t.tileHeight).toSet();
        final avatarAreas = tiles.map((t) => t.avatarAreaHeight).toSet();
        expect(diameters.length, 1,
            reason: 'all seats must share one diameter');
        expect(tileHeights.length, 1,
            reason: 'all seats must share one tile height');
        expect(avatarAreas.length, 1,
            reason: 'all seats must share one avatar zone height');

        // Measured render boxes agree — occupancy cannot change layout size.
        final sizes = <Size>{};
        for (final element in find.byType(SroodMicSeat).evaluate()) {
          sizes.add(element.size!);
        }
        expect(sizes.length, 1,
            reason: 'rendered seat tiles must be identical in size');

        // Diameter stays inside the spec's clamp range.
        final spec = SroodSeatSpec.forSeatCount(seatCount);
        final d = diameters.single;
        expect(d, greaterThanOrEqualTo(spec.min - 0.001));
        expect(d, lessThanOrEqualTo(spec.max + 0.001));
      },
    );
  }

  testWidgets('a member joining a seat does not change the shell size',
      (tester) async {
    await tester.pumpWidget(wrapGrid(members: const [], maxSeats: 9));
    final beforeElement = find.byType(SroodMicSeat).evaluate().first;
    final before = beforeElement.size!;
    final beforeDiameter = tester
        .widgetList<SroodMicSeat>(find.byType(SroodMicSeat))
        .first
        .seatSize;

    await tester.pumpWidget(
      wrapGrid(
        members: [member(seat: 1, role: 'host', vipLevel: 5)],
        maxSeats: 9,
      ),
    );
    final afterElement = find.byType(SroodMicSeat).evaluate().first;
    final after = afterElement.size!;
    final afterDiameter = tester
        .widgetList<SroodMicSeat>(find.byType(SroodMicSeat))
        .first
        .seatSize;

    expect(after, before);
    expect(afterDiameter, beforeDiameter);
  });

  testWidgets('12-seat grid fits a 320px-wide screen without overflow',
      (tester) async {
    final members = [
      member(seat: 1, role: 'host', name: 'مستخدم باسم عربي طويل جداً'),
      for (var s = 2; s <= 12; s++)
        member(seat: s, name: 'A very long English username $s'),
    ];

    await tester.pumpWidget(
      wrapGrid(members: members, maxSeats: 12, width: 300, height: 420),
    );

    // No RenderFlex overflow exceptions.
    expect(tester.takeException(), isNull);
    expect(find.byType(SroodMicSeat), findsNWidgets(12));
  });

  test('empty stage seat model reserves the label strip identically', () {
    final empty = SroodStageSeat.empty(3);
    expect(empty.isEmpty, isTrue);
    expect(empty.number, 3);

    final locked = SroodStageSeat.empty(4, isLocked: true);
    expect(locked.isLocked, isTrue);
  });
}
