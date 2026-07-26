// Frame System v2 registry: legacy alias mapping, entitlement mirroring,
// fallback chain, availability windows, and hydration.

import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/core/frames/frame_registry.dart';
import 'package:srood_live/core/frames/srood_frame.dart';

void main() {
  final registry = FrameRegistry.instance;

  group('legacy alias mapping', () {
    test('all pre-v2 VIP frame names map to tier codes', () {
      expect(registry.canonicalCode('vip_bronze_star'), 'vip_1');
      expect(registry.canonicalCode('vip_silver_flame'), 'vip_2');
      expect(registry.canonicalCode('vip_gold_crown'), 'vip_3');
      expect(registry.canonicalCode('vip_platinum_diamond'), 'vip_4');
      expect(registry.canonicalCode('vip_royal_king'), 'vip_5');
      expect(registry.canonicalCode('vip_elite'), 'vip_6');
      expect(registry.canonicalCode('vip_mythic'), 'vip_7');
      expect(registry.canonicalCode('vip_emperor'), 'vip_8');
      expect(registry.canonicalCode('vip_celestial'), 'vip_9');
    });

    test('painter aliases resolve', () {
      expect(registry.canonicalCode('ruby_royal'), 'luxury_ruby_royal');
      expect(
        registry.resolve('ruby_royal_dark')?.code,
        'luxury_ruby_royal_dark',
      );
    });

    test('unknown codes pass through unchanged', () {
      expect(registry.canonicalCode('some_future_frame'), 'some_future_frame');
      expect(registry.resolve('some_future_frame'), isNull);
    });
  });

  group('resolveRender fallback chain', () {
    test('no code + no VIP renders nothing', () {
      final spec = registry.resolveRender(rawCode: null, effectiveVipLevel: 0);
      expect(spec.mode, FrameRenderMode.none);
    });

    test('no code + active VIP falls back to implicit tier frame', () {
      final spec = registry.resolveRender(rawCode: null, effectiveVipLevel: 4);
      expect(spec.mode, FrameRenderMode.legacyDelegate);
      expect(spec.legacyKey, 'vip_4');
    });

    test('VIP frame above owner tier is stripped (expired VIP behavior)', () {
      // Owner selected vip_9 but VIP expired → effective 0 → no frame at all.
      final expired = registry.resolveRender(
        rawCode: 'vip_9',
        effectiveVipLevel: 0,
      );
      expect(expired.mode, FrameRenderMode.none);

      // VIP 3 wearing a VIP 5 legacy alias → stripped to implicit vip_3.
      final downgraded = registry.resolveRender(
        rawCode: 'vip_royal_king',
        effectiveVipLevel: 3,
      );
      expect(downgraded.legacyKey, 'vip_3');
    });

    test('legacy custom frames delegate to the proven pipeline', () {
      final spec = registry.resolveRender(
        rawCode: 'custom_srood_live',
        effectiveVipLevel: 0,
      );
      expect(spec.mode, FrameRenderMode.legacyDelegate);
      expect(spec.legacyKey, 'custom_srood_live');
      expect(spec.animated, isTrue);
    });

    test('unknown legacy id delegates as-is instead of guessing', () {
      final spec = registry.resolveRender(
        rawCode: 'mystery_key_from_2025',
        effectiveVipLevel: 2,
      );
      expect(spec.mode, FrameRenderMode.legacyDelegate);
      expect(spec.legacyKey, 'mystery_key_from_2025');
    });

    test('preferV2TierArt switches VIP tiers to the placeholder painter', () {
      final spec = registry.resolveRender(
        rawCode: 'vip_7',
        effectiveVipLevel: 7,
        preferV2TierArt: true,
      );
      expect(spec.mode, FrameRenderMode.tierPainter);
      expect(spec.vipTier, 7);
      expect(spec.animated, isTrue, reason: 'VIP 6+ carries animated accents');

      final low = registry.resolveRender(
        rawCode: 'vip_2',
        effectiveVipLevel: 2,
        preferV2TierArt: true,
      );
      expect(low.animated, isFalse, reason: 'VIP 1-5 are static');
    });
  });

  group('availability windows and hydration', () {
    test('expired catalog frame falls back to implicit VIP frame', () {
      registry.hydrate([
        SroodFrame(
          id: 'seasonal_test',
          code: 'seasonal_test',
          name: 'Expired Seasonal',
          category: SroodFrameCategory.seasonal,
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ]);
      final spec = registry.resolveRender(
        rawCode: 'seasonal_test',
        effectiveVipLevel: 2,
      );
      expect(spec.legacyKey, 'vip_2', reason: 'expired frame → implicit VIP');
    });

    test('hydrated rows override built-ins without breaking codes', () {
      registry.hydrate([
        const SroodFrame(
          id: 'vip_1',
          code: 'vip_1',
          name: 'Bronze Sentinel — DB',
          category: SroodFrameCategory.vip,
          vipLevel: 1,
          requiredVipLevel: 1,
          unlockType: SroodFrameUnlock.vipLevel,
          assetType: SroodFrameAssetType.bundled,
          assetUrl: 'assets/images/vip_frames/11.png',
        ),
      ]);
      expect(registry.resolve('vip_1')?.name, 'Bronze Sentinel — DB');
      expect(
        registry.resolveRender(rawCode: 'vip_1', effectiveVipLevel: 1).mode,
        FrameRenderMode.legacyDelegate,
      );
    });

    test('vip tier frames exist for all nine tiers', () {
      for (var level = 1; level <= 9; level++) {
        final frame = registry.vipTierFrame(level);
        expect(frame, isNotNull, reason: 'vip_$level missing');
        expect(frame!.requiredVipLevel, level);
        expect(frame.category, SroodFrameCategory.vip);
        expect(frame.nameFor('ar'), isNotEmpty);
      }
    });
  });
}
