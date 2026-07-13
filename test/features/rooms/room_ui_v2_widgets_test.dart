// Room UI v2 widget coverage: bottom actions responsiveness + unread badge,
// header truncation, exit sheet, and RTL behavior.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/features/rooms/models/room.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/bottom_actions/srood_room_bottom_actions.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/header/srood_room_header.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/sheets/srood_room_exit_sheet.dart';

Room testRoom({String name = 'Test Room'}) {
  return Room.fromJson({
    'id': '12345678-1234-1234-1234-123456789012',
    'name': name,
    'owner_id': 'owner-1',
    'created_at': '2026-01-01T00:00:00Z',
    'public_room_code': '54321',
  });
}

Widget wrap(Widget child, {double width = 375, bool rtl = false}) {
  return MaterialApp(
    home: Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    ),
  );
}

SroodRoomBottomActions bottomActions({
  bool isArabic = false,
  int unread = 0,
  bool isOnMic = true,
  bool micEnabled = true,
}) {
  return SroodRoomBottomActions(
    isArabic: isArabic,
    connectingAudio: false,
    micEnabled: micEnabled,
    isOnMic: isOnMic,
    leaving: false,
    isSendingMessage: false,
    myVipLevel: 0,
    isUploadingImage: false,
    onToggleMic: () {},
    onGiftTap: () {},
    onMoreTap: () {},
    onReactionTap: () {},
    onInboxTap: () {},
    inboxUnreadCount: unread,
    onSendMessage: (_) async {},
    onSendImage: () async {},
  );
}

void main() {
  group('SroodRoomBottomActions', () {
    testWidgets('shows all five core actions with 44px touch targets',
        (tester) async {
      await tester.pumpWidget(wrap(bottomActions()));

      final buttons = find.byType(SroodQuickActionButton);
      expect(buttons, findsNWidgets(5));

      for (final element in buttons.evaluate()) {
        final size = element.size!;
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('fits a 320px-wide screen without overflow', (tester) async {
      await tester.pumpWidget(wrap(bottomActions(), width: 320));
      expect(tester.takeException(), isNull);
      expect(find.byType(SroodQuickActionButton), findsNWidgets(5));
    });

    testWidgets('shows unread badge count and caps at 99+', (tester) async {
      await tester.pumpWidget(wrap(bottomActions(unread: 7)));
      expect(find.text('7'), findsOneWidget);

      await tester.pumpWidget(wrap(bottomActions(unread: 150)));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('renders RTL for Arabic without overflow', (tester) async {
      await tester.pumpWidget(
        wrap(bottomActions(isArabic: true), width: 320, rtl: true),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SroodRoomHeader', () {
    Widget header({String name = 'Room', bool isArabic = false}) {
      return SroodRoomHeader(
        room: testRoom(name: name),
        roomName: name,
        roomLevel: 5,
        avatarUrl: null,
        memberCount: 12,
        walletCoins: 1500,
        isHost: true,
        isOwner: true,
        isArabic: isArabic,
        leaving: false,
        onExitTap: () {},
        onLevelTap: () {},
        onManagementTap: () {},
      );
    }

    testWidgets('truncates a very long room title without overflow',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          header(
            name: 'An extremely long room title that cannot possibly fit '
                'on a narrow phone screen in one line',
          ),
          width: 320,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows room code, level badge, and online count',
        (tester) async {
      await tester.pumpWidget(wrap(header()));
      expect(find.text('54321'), findsOneWidget);
      expect(find.text('LV 5'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('1.5k'), findsOneWidget);
    });

    testWidgets('renders Arabic RTL without overflow at 320px',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          header(name: 'غرفة صوتية باسم عربي طويل جداً للتجربة', isArabic: true),
          width: 320,
          rtl: true,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SroodRoomExitSheet', () {
    testWidgets('shows minimize + exit for members, close only for owners',
        (tester) async {
      await tester.pumpWidget(
        wrap(const SroodRoomExitSheet(isOwner: false, isArabic: false)),
      );
      expect(find.text('Minimize'), findsOneWidget);
      expect(find.text('Exit Room'), findsOneWidget);
      expect(find.text('Close Room'), findsNothing);

      await tester.pumpWidget(
        wrap(const SroodRoomExitSheet(isOwner: true, isArabic: false)),
      );
      expect(find.text('Close Room'), findsOneWidget);
    });

    testWidgets('pops the selected action', (tester) async {
      SroodRoomExitAction? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showModalBottomSheet<SroodRoomExitAction>(
                      context: context,
                      builder: (_) => const SroodRoomExitSheet(
                        isOwner: true,
                        isArabic: false,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Minimize'));
      await tester.pumpAndSettle();
      expect(popped, SroodRoomExitAction.minimize);
    });

    testWidgets('scrolls on very short screens without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(const SroodRoomExitSheet(isOwner: true, isArabic: true)),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
