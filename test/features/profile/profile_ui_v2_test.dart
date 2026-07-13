// Profile UI v2 widget coverage: header identity (fixed avatar shell, name
// ellipsis), stat row, bio card expand, social stats taps, and the progress
// card's contradiction-free status line.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/features/profile/presentation/srood_profile_avatar.dart';
import 'package:srood_live/features/profile/presentation/srood_profile_bio_card.dart';
import 'package:srood_live/features/profile/presentation/srood_profile_header.dart';
import 'package:srood_live/features/profile/presentation/srood_profile_stats.dart';
import 'package:srood_live/features/profile/presentation/srood_progress_card.dart';
import 'package:srood_live/features/profile/presentation/srood_social_stats_card.dart';
import 'package:srood_live/features/profile_hub/models/profile_hub_models.dart';

Widget wrap(Widget child, {double width = 375, bool rtl = false}) {
  return MaterialApp(
    home: Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF07030D),
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

SroodProfileHeader header({
  String name = 'Test User',
  int vipLevel = 0,
  bool isArabic = false,
  String country = '',
}) {
  return SroodProfileHeader(
    displayName: name,
    publicUserId: '12345678',
    avatarUrl: null,
    frameKey: null,
    vipLevel: vipLevel,
    isGoldenId: false,
    country: country,
    isUploadingAvatar: false,
    isArabic: isArabic,
    onAvatarTap: () {},
    onEditTap: () {},
    onFrameTap: () {},
    onCopyId: () {},
  );
}

UserLevel level({
  int lvl = 5,
  int xp = 500,
  int? nextLevel = 6,
  int? requiredXp = 1000,
  int? toNext = 500,
  double? progress = 0.5,
}) {
  return UserLevel(
    level: lvl,
    xp: xp,
    totalSpentCoins: 0,
    totalReceivedGiftsValue: 0,
    totalRoomMinutes: 0,
    totalGiftsSent: 0,
    totalGiftsReceived: 0,
    lastXpAt: null,
    currentLevelTitle: null,
    currentLevelColor: null,
    currentLevelBadgeKey: null,
    nextLevel: nextLevel,
    nextLevelTitle: nextLevel == null ? null : 'Rising Star',
    nextLevelRequiredXp: requiredXp,
    xpToNextLevel: toNext,
    levelProgress: progress,
  );
}

void main() {
  group('SroodProfileHeader', () {
    for (final width in const [320.0, 430.0]) {
      testWidgets('renders without overflow at ${width.round()}px', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            header(
              name: 'A ridiculously long display name that keeps on going',
              vipLevel: 5,
              country: 'Lebanon',
            ),
            width: width,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long Arabic name is ellipsized on one line, never clipped', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          header(
            name: 'اسم عربي طويل جداً جداً جداً لاختبار القص في الواجهة',
            isArabic: true,
          ),
          width: 320,
          rtl: true,
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(
        find.text('اسم عربي طويل جداً جداً جداً لاختبار القص في الواجهة'),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('avatar shell size is fixed regardless of VIP tier', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(header(vipLevel: 0)));
      final plain = tester.getSize(find.byType(SroodProfileAvatar));

      await tester.pumpWidget(wrap(header(vipLevel: 9)));
      final vip = tester.getSize(find.byType(SroodProfileAvatar));

      expect(vip, plain, reason: 'VIP frame must not drive the shell size');
    });

    testWidgets('missing avatar renders fallback without errors', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(header()));
      expect(tester.takeException(), isNull);
      expect(find.text('ID:12345678'), findsOneWidget);
    });
  });

  group('SroodProfileStats', () {
    testWidgets('shows charm, wealth, and gender as three equal tiles', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SroodProfileStats(
            isArabic: false,
            gender: 'male',
            charmLevel: 1,
            wealthLevel: 37,
          ),
        ),
      );
      expect(find.text('Charm'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Wealth'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
    });

    testWidgets('keeps all three tiles on one row at 320px without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SroodProfileStats(
            isArabic: false,
            gender: 'female',
            charmLevel: 99,
            wealthLevel: 99,
          ),
          width: 320,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing when no data exists', (tester) async {
      await tester.pumpWidget(
        wrap(const SroodProfileStats(isArabic: false, gender: '')),
      );
      expect(find.byType(Container), findsNothing);
    });
  });

  group('SroodProfileBioCard', () {
    testWidgets('collapses long bios to 3 lines and expands on tap', (
      tester,
    ) async {
      final longBio = List.filled(30, 'A fairly long sentence.').join(' ');
      await tester.pumpWidget(
        wrap(SroodProfileBioCard(bio: longBio, isArabic: false)),
      );

      Text bioText() => tester.widget<Text>(find.text(longBio));
      expect(bioText().maxLines, 3);

      await tester.tap(find.byType(SroodProfileBioCard));
      await tester.pumpAndSettle();
      expect(bioText().maxLines, isNull);
    });

    testWidgets('missing bio shows placeholder; edit icon only for owner', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(SroodProfileBioCard(bio: '', isArabic: false, onEditTap: () {})),
      );
      expect(find.text('Add something about yourself...'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);

      await tester.pumpWidget(
        wrap(const SroodProfileBioCard(bio: 'hello', isArabic: false)),
      );
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
    });
  });

  group('SroodSocialStatsCard', () {
    testWidgets('whole columns are tappable and fire callbacks', (
      tester,
    ) async {
      String? tapped;
      await tester.pumpWidget(
        wrap(
          SroodSocialStatsCard(
            isArabic: false,
            friends: 3,
            following: 25,
            followers: 1200,
            onFriendsTap: () => tapped = 'friends',
            onFollowingTap: () => tapped = 'following',
            onFollowersTap: () => tapped = 'followers',
          ),
        ),
      );

      expect(find.text('1.2K'), findsOneWidget);

      await tester.tap(find.text('Friends'));
      expect(tapped, 'friends');
      await tester.tap(find.text('Following'));
      expect(tapped, 'following');
      await tester.tap(find.text('1.2K'));
      expect(tapped, 'followers');
    });

    testWidgets('columns meet the 44px touch target', (tester) async {
      await tester.pumpWidget(
        wrap(
          SroodSocialStatsCard(
            isArabic: false,
            friends: 0,
            following: 0,
            followers: 0,
            onFriendsTap: () {},
          ),
        ),
      );
      final size = tester.getSize(find.text('Friends').first);
      // The tappable column is taller than its label: verify via ancestor.
      final column = tester.getSize(
        find.ancestor(of: find.text('Friends'), matching: find.byType(InkWell)),
      );
      expect(column.height, greaterThanOrEqualTo(44));
      expect(size.height, greaterThan(0));
    });
  });

  group('SroodProgressCard', () {
    Widget progress(UserLevel? lvl, {bool isArabic = false}) {
      return SroodProgressCard(
        isArabic: isArabic,
        userLevel: lvl,
        vipLevel: 3,
        charmLevel: 1,
        wealthLevel: 37,
        onLevelTap: () {},
        onVipTap: () {},
        onWealthTap: () {},
      );
    }

    testWidgets('shows XP figures and remaining XP for a mid level', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(progress(level())));
      await tester.pumpAndSettle();
      expect(find.text('Level 5'), findsOneWidget);
      expect(find.text('500 / 1.0K XP'), findsOneWidget);
      expect(find.text('500 XP to the next level'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('Rising Star'), findsOneWidget);
    });

    testWidgets('max level shows a coherent message, never "0 points"', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          progress(
            level(
              lvl: 50,
              nextLevel: null,
              requiredXp: null,
              toNext: null,
              progress: 1.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Maximum current level reached'), findsOneWidget);
      expect(find.textContaining('0 points'), findsNothing);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('100% with 0 remaining shows "Ready for next level"', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(progress(level(toNext: 0, progress: 1.0))));
      await tester.pumpAndSettle();
      expect(find.text('Ready for next level'), findsOneWidget);
      expect(find.textContaining('0 XP to the next level'), findsNothing);
    });

    testWidgets('renders RTL at 320px without overflow', (tester) async {
      await tester.pumpWidget(
        wrap(progress(level(), isArabic: true), width: 320, rtl: true),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
