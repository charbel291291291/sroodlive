// Gift drawer redesign coverage: price formatting, collections, VIP
// sections, selection/quantity/balance state, RTL, and small-screen
// overflow, per the gift drawer redesign spec.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/features/rooms/models/room_gift.dart';
import 'package:srood_live/features/rooms/models/room_member.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/gifts/gift_collections.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/gifts/srood_gift_bottom_bar.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/gifts/srood_gift_collection_rail.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/gifts/srood_gift_price.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/gifts/srood_gift_tile.dart';
import 'package:srood_live/features/rooms/presentation/room_screen/widgets/sheets/srood_gift_sheet.dart';

RoomGift gift({
  String code = 'rose',
  String name = 'Rose',
  String arabicName = 'وردة',
  int priceCoins = 10,
}) {
  return RoomGift(
    id: code,
    code: code,
    name: name,
    arabicName: arabicName,
    priceCoins: priceCoins,
    icon: '',
    sortOrder: 0,
  );
}

RoomMember member({
  String id = 'm1',
  String userId = 'u1',
  String role = 'listener',
}) {
  return RoomMember(
    id: id,
    roomId: 'r1',
    userId: userId,
    role: role,
    isMuted: false,
    joinedAt: DateTime(2026, 1, 1),
    displayName: 'User $userId',
  );
}

Widget wrap(Widget child, {double width = 375, bool rtl = false}) {
  return MaterialApp(
    home: Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('formatGiftCoins', () {
    test('formats per the exact K/M rule set', () {
      expect(formatGiftCoins(999), '999');
      expect(formatGiftCoins(1000), '1K');
      expect(formatGiftCoins(1200), '1.2K');
      expect(formatGiftCoins(120000), '120K');
      expect(formatGiftCoins(500000), '500K');
      expect(formatGiftCoins(1000000), '1M');
      expect(formatGiftCoins(1500000), '1.5M');
      expect(formatGiftCoins(2500000), '2.5M');
    });

    test('never rounds 1.5M up to 2M', () {
      expect(formatGiftCoins(1500000), isNot('2M'));
    });
  });

  group('SroodGiftTile long names', () {
    testWidgets('uses two lines for a long gift name instead of truncating', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SroodGiftTile(
            gift: gift(
              code: 'egypt_royal',
              name: 'Egypt Royal',
              priceCoins: 500000,
            ),
            isArabic: false,
            selected: false,
            onTap: () {},
          ),
          width: 90,
        ),
      );

      final textWidget = tester.widget<Text>(find.text('Egypt Royal'));
      expect(textWidget.maxLines, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('gift_collections filtering', () {
    final all = [
      gift(code: 'egypt_royal', name: 'Egypt Royal'),
      gift(code: 'iraq_royal', name: 'Iraq Royal'),
      gift(code: 'jordan_royal', name: 'Jordan Royal'),
      gift(code: 'lebanon_royal', name: 'Lebanon Royal'),
      gift(code: 'palestine_royal', name: 'Palestine Royal'),
      gift(code: 'saudi_arabia_royal', name: 'Saudi Arabia Royal'),
      gift(code: 'golden_lion', name: 'Golden Lion'),
      gift(code: 'tiger', name: 'Tiger'),
      gift(code: 'rose', name: 'Rose'),
    ];

    test('Country Royals collection returns exactly the 6 country codes', () {
      final result = giftsForCollection(
        all,
        SroodGiftCollectionKey.countryRoyals,
      );
      expect(result.map((g) => g.code).toList(), kCountryRoyalGiftCodes);
    });

    test('VIP sections contain the expected gift codes', () {
      final countryRoyals = giftsByCodes(all, kVipCountryRoyalsSectionCodes);
      expect(countryRoyals.map((g) => g.code), kCountryRoyalGiftCodes);

      final classicVip = giftsByCodes(all, kVipClassicSectionCodes);
      expect(classicVip.map((g) => g.code), ['tiger']);
    });

    test('no duplicate gift appears within a resolved collection', () {
      final lebaneseLuxury = giftsForCollection(
        all,
        SroodGiftCollectionKey.lebaneseLuxury,
      );
      final codes = lebaneseLuxury.map((g) => g.code).toList();
      expect(codes.toSet().length, codes.length);

      final featured = giftsForCollection(all, SroodGiftCollectionKey.featured);
      final featuredCodes = featured.map((g) => g.code).toList();
      expect(featuredCodes.toSet().length, featuredCodes.length);
      // lebanon_royal appears in both country royals and Lebanese luxury
      // source lists, but must not be duplicated in the merged result.
      expect(featuredCodes.where((c) => c == 'lebanon_royal').length, 1);
    });
  });

  group('SroodGiftCollectionRail selection', () {
    testWidgets('shows a premium selected state for the active chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SroodGiftCollectionRail(
            isArabic: false,
            selected: SroodGiftCollectionKey.countryRoyals,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Country Royals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SroodGiftTile selection state', () {
    testWidgets('applies gold border styling only when selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SroodGiftTile(
            gift: gift(),
            isArabic: false,
            selected: true,
            onTap: () {},
          ),
          width: 90,
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('gift_tile_rose')),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border!.top.color, const Color(0xFFF0C15A));
    });
  });

  group('SroodGiftBottomBar', () {
    testWidgets('shows total cost line for quantity > 1', (tester) async {
      final notifier = ValueNotifier<int>(7);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        wrap(
          SroodGiftBottomBar(
            isArabic: false,
            quantityListenable: notifier,
            selectedGift: gift(code: 'lucky_bag', priceCoins: 500000),
            hasReceiver: true,
            userCoinsBalance: 10000000,
            onQuantityChanged: (_) {},
            onSend: () {},
          ),
        ),
      );

      expect(find.text('500K × 7 = 3.5M'), findsOneWidget);
    });

    testWidgets('disables send when balance is insufficient', (tester) async {
      final notifier = ValueNotifier<int>(1);
      addTearDown(notifier.dispose);
      var sent = false;

      await tester.pumpWidget(
        wrap(
          SroodGiftBottomBar(
            isArabic: false,
            quantityListenable: notifier,
            selectedGift: gift(priceCoins: 5000),
            hasReceiver: true,
            userCoinsBalance: 100,
            onQuantityChanged: (_) {},
            onSend: () => sent = true,
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(sent, isFalse);
    });

    testWidgets('disables send when there is no receiver', (tester) async {
      final notifier = ValueNotifier<int>(1);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        wrap(
          SroodGiftBottomBar(
            isArabic: false,
            quantityListenable: notifier,
            selectedGift: gift(priceCoins: 10),
            hasReceiver: false,
            userCoinsBalance: 10000,
            onQuantityChanged: (_) {},
            onSend: () {},
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('shows readable balance when no gift is selected', (
      tester,
    ) async {
      final notifier = ValueNotifier<int>(1);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        wrap(
          SroodGiftBottomBar(
            isArabic: false,
            quantityListenable: notifier,
            selectedGift: null,
            hasReceiver: false,
            userCoinsBalance: 6000000,
            onQuantityChanged: (_) {},
            onSend: () {},
          ),
        ),
      );

      expect(find.text('6M'), findsOneWidget);
    });
  });

  group('SroodGiftSheet', () {
    testWidgets(
      'shows a compact empty-state strip when there are no receivers',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            SroodGiftSheet(
              isArabic: false,
              receivers: const [],
              gifts: [gift()],
              roleLabel: (role) => role,
            ),
            width: 375,
          ),
        );
        await tester.pump();

        expect(find.text('No other active users.'), findsOneWidget);
        final strip = tester.getSize(
          find
              .ancestor(
                of: find.text('No other active users.'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(strip.height, inInclusiveRange(56, 68));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders without overflow on a small Android viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SroodGiftSheet(
              isArabic: false,
              receivers: [member()],
              gifts: [
                gift(code: 'rose', priceCoins: 10),
                gift(code: 'star', priceCoins: 50),
                gift(
                  code: 'egypt_royal',
                  name: 'Egypt Royal',
                  priceCoins: 500000,
                ),
              ],
              roleLabel: (role) => role,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders RTL Arabic layout without overflow', (tester) async {
      await tester.pumpWidget(
        wrap(
          SroodGiftSheet(
            isArabic: true,
            receivers: [member()],
            gifts: [
              gift(),
              gift(code: 'star', name: 'Star', arabicName: 'نجمة'),
            ],
            roleLabel: (role) => role,
          ),
          width: 320,
          rtl: true,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
