// SroodAvatarFrame widget: VIP 1-9 rendering, size presets, fallbacks,
// RTL, reduced motion, animated controller lifecycle/disposal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/core/frames/frame_tier_painter.dart';
import 'package:srood_live/core/frames/frames_v2_rendering_flag_service.dart';
import 'package:srood_live/shared/widgets/avatar_with_frame.dart';
import 'package:srood_live/shared/widgets/srood_avatar_frame.dart';

Widget wrap(Widget child, {bool rtl = false, bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: const Color(0xFF07030D),
          body: Center(child: child),
        ),
      ),
    ),
  );
}

bool hasTierPaint(WidgetTester tester, int tier) {
  return tester.widgetList<CustomPaint>(find.byType(CustomPaint)).any((w) {
    final p = w.painter ?? w.foregroundPainter;
    return p is SroodTierFramePainter && p.tier == tier;
  });
}

void main() {
  group('VIP tier rendering', () {
    for (var tier = 1; tier <= 9; tier++) {
      testWidgets('VIP $tier renders v2 placeholder art without errors', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            SroodAvatarFrame(
              frameCode: 'vip_$tier',
              vipLevel: tier,
              sizePreset: SroodAvatarFrameSize.medium,
              preferV2TierArt: true,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(hasTierPaint(tester, tier), isTrue);
      });
    }

    testWidgets('legacy path renders through AvatarWithFrame', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'vip_3',
            vipLevel: 3,
            sizePreset: SroodAvatarFrameSize.medium,
          ),
        ),
      );
      expect(find.byType(AvatarWithFrame), findsOneWidget);
      final legacy = tester.widget<AvatarWithFrame>(
        find.byType(AvatarWithFrame),
      );
      expect(legacy.frameKey, 'vip_3');
    });
  });

  group('fallbacks', () {
    testWidgets('expired VIP shows no frame', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'vip_9',
            vipLevel: 0, // caller passes EFFECTIVE level; expired → 0
            sizePreset: SroodAvatarFrameSize.medium,
          ),
        ),
      );
      final legacy = tester.widget<AvatarWithFrame>(
        find.byType(AvatarWithFrame),
      );
      expect(legacy.frameKey, isNull);
    });

    testWidgets('legacy alias resolves to owned tier', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'vip_royal_king', // legacy VIP-5 name
            vipLevel: 5,
            sizePreset: SroodAvatarFrameSize.small,
          ),
        ),
      );
      final legacy = tester.widget<AvatarWithFrame>(
        find.byType(AvatarWithFrame),
      );
      expect(legacy.frameKey, 'vip_5');
    });

    testWidgets('unknown legacy id renders without crashing', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'totally_unknown_frame',
            vipLevel: 0,
            sizePreset: SroodAvatarFrameSize.medium,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading state shows placeholder circle', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            isLoading: true,
            sizePreset: SroodAvatarFrameSize.large,
          ),
        ),
      );
      expect(find.byType(AvatarWithFrame), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('sizes and RTL', () {
    testWidgets('all presets and custom sizes lay out without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SroodAvatarFrame(
                frameCode: 'vip_9',
                vipLevel: 9,
                sizePreset: SroodAvatarFrameSize.small,
                preferV2TierArt: true,
              ),
              SroodAvatarFrame(
                frameCode: 'vip_9',
                vipLevel: 9,
                sizePreset: SroodAvatarFrameSize.medium,
                preferV2TierArt: true,
              ),
              SroodAvatarFrame(
                frameCode: 'vip_9',
                vipLevel: 9,
                size: 120,
                preferV2TierArt: true,
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Frame boxes are 1.35× the avatar diameter.
      final boxes = tester
          .widgetList<SroodAvatarFrame>(find.byType(SroodAvatarFrame))
          .toList();
      expect(boxes.length, 3);
      final firstSize = tester.getSize(find.byType(SroodAvatarFrame).first);
      expect(firstSize.width, closeTo(36 * 1.35, 0.01));
    });

    testWidgets('renders identically under RTL without errors', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'vip_7',
            vipLevel: 7,
            sizePreset: SroodAvatarFrameSize.medium,
            preferV2TierArt: true,
          ),
          rtl: true,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(hasTierPaint(tester, 7), isTrue);
    });
  });

  group('animation lifecycle', () {
    testWidgets('animated tier runs a ticker and disposes cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'vip_8',
            vipLevel: 8,
            sizePreset: SroodAvatarFrameSize.medium,
            preferV2TierArt: true,
            animate: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // Remove the widget — the controller must be disposed (a leaked ticker
      // fails the test automatically) and no callbacks may remain.
      await tester.pumpWidget(wrap(const SizedBox.shrink()));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced motion forces a static frame (no ticker)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'vip_9',
            vipLevel: 9,
            sizePreset: SroodAvatarFrameSize.medium,
            preferV2TierArt: true,
            animate: true,
          ),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.transientCallbackCount, 0);
      expect(
        hasTierPaint(tester, 9),
        isTrue,
        reason: 'static frame still drawn',
      );
    });

    testWidgets('static tiers never create a controller even when animate', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SroodAvatarFrame(
            frameCode: 'vip_2',
            vipLevel: 2,
            sizePreset: SroodAvatarFrameSize.medium,
            preferV2TierArt: true,
            animate: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('frames_v2_rendering_enabled default wiring', () {
    tearDown(() => FramesV2RenderingFlagService.instance.resetForTest());

    testWidgets(
      'omitting preferV2TierArt follows a disabled DB flag (legacy path)',
      (tester) async {
        FramesV2RenderingFlagService.instance.seedForTest(false);
        await tester.pumpWidget(
          wrap(
            const SroodAvatarFrame(
              frameCode: 'vip_3',
              vipLevel: 3,
              sizePreset: SroodAvatarFrameSize.medium,
            ),
          ),
        );
        expect(find.byType(AvatarWithFrame), findsOneWidget);
        final legacy = tester.widget<AvatarWithFrame>(
          find.byType(AvatarWithFrame),
        );
        expect(legacy.frameKey, 'vip_3');
      },
    );

    testWidgets(
      'omitting preferV2TierArt follows an enabled DB flag (v2 painter)',
      (tester) async {
        FramesV2RenderingFlagService.instance.seedForTest(true);
        await tester.pumpWidget(
          wrap(
            const SroodAvatarFrame(
              frameCode: 'vip_3',
              vipLevel: 3,
              sizePreset: SroodAvatarFrameSize.medium,
            ),
          ),
        );
        expect(hasTierPaint(tester, 3), isTrue);
      },
    );

    testWidgets(
      'an explicit preferV2TierArt always overrides an enabled DB flag',
      (tester) async {
        FramesV2RenderingFlagService.instance.seedForTest(true);
        await tester.pumpWidget(
          wrap(
            const SroodAvatarFrame(
              frameCode: 'vip_3',
              vipLevel: 3,
              sizePreset: SroodAvatarFrameSize.medium,
              preferV2TierArt: false,
            ),
          ),
        );
        expect(find.byType(AvatarWithFrame), findsOneWidget);
        final legacy = tester.widget<AvatarWithFrame>(
          find.byType(AvatarWithFrame),
        );
        expect(legacy.frameKey, 'vip_3');
      },
    );

    testWidgets(
      'unloaded flag (default state, e.g. missing/error) uses the legacy path',
      (tester) async {
        // No load()/seedForTest() call — mirrors "missing" and
        // "loading-error" outcomes, both of which leave the service
        // unloaded/false. Covered directly in
        // frames_v2_rendering_flag_service_test.dart; this confirms the
        // widget-level consequence.
        await tester.pumpWidget(
          wrap(
            const SroodAvatarFrame(
              frameCode: 'vip_3',
              vipLevel: 3,
              sizePreset: SroodAvatarFrameSize.medium,
            ),
          ),
        );
        expect(find.byType(AvatarWithFrame), findsOneWidget);
        final legacy = tester.widget<AvatarWithFrame>(
          find.byType(AvatarWithFrame),
        );
        expect(legacy.frameKey, 'vip_3');
      },
    );
  });
}
