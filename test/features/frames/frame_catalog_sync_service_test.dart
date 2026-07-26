/// Catalog → registry hydration.
///
/// `FrameRegistry.hydrate` had no callers in `lib/`, so a frame an admin created
/// was stored, entitled and equippable — and then rendered as nothing, because
/// the renderer could not find a row for its code. These tests pin the service
/// that closes that gap, and the two properties that make it safe to call on
/// every app start: it never throws, and it never leaves a deactivated frame
/// behind.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/core/frames/frame_catalog_sync_service.dart';
import 'package:srood_live/core/frames/frame_registry.dart';

Map<String, dynamic> row({
  required String code,
  String name = 'Test Frame',
  String category = 'luxury',
  String assetType = 'network',
  String? assetUrl = 'https://cdn.test/luxury/test/v1.webp',
  bool isAnimated = false,
  int sortOrder = 300,
}) {
  return <String, dynamic>{
    'id': 'id-$code',
    'code': code,
    'name': name,
    'category': category,
    'rarity': 'legendary',
    'asset_type': assetType,
    'asset_url': assetUrl,
    'is_animated': isAnimated,
    'is_active': true,
    'sort_order': sortOrder,
    'unlock_type': 'free',
  };
}

void main() {
  final registry = FrameRegistry.instance;

  // The registry is a process-wide singleton; hand it back untouched.
  tearDown(registry.resetToBuiltIns);

  group('hydration', () {
    test('loads catalog rows into the registry', () async {
      final service = FrameCatalogSyncService(
        rpcCall: () async => [
          row(code: 'luxury_celestial_crown', name: 'Celestial Crown'),
          row(code: 'event_summer_halo', category: 'event'),
        ],
      );

      expect(await service.load(), 2);
      expect(service.status, FrameCatalogSyncStatus.loaded);
      expect(service.rowCount, 2);
      expect(
        registry.resolve('luxury_celestial_crown')?.name,
        'Celestial Crown',
      );
      expect(registry.resolve('event_summer_halo'), isNotNull);
    });

    test('an uploaded network frame becomes renderable', () async {
      final service = FrameCatalogSyncService(
        rpcCall: () async => [
          row(
            code: 'luxury_celestial_crown',
            assetUrl: 'https://cdn.test/luxury/luxury_celestial_crown/v1.webp',
            isAnimated: true,
          ),
        ],
      );
      await service.load();

      // This is the whole point of the wiring: before it, networkAsset was
      // dead code and admin-uploaded artwork rendered as nothing.
      final spec = registry.resolveRender(
        rawCode: 'luxury_celestial_crown',
        effectiveVipLevel: 0,
      );
      expect(spec.mode, FrameRenderMode.networkAsset);
      expect(
        spec.assetUrl,
        'https://cdn.test/luxury/luxury_celestial_crown/v1.webp',
      );
      expect(spec.animated, isTrue);
    });

    test('keeps the built-ins alongside hydrated rows', () async {
      final service = FrameCatalogSyncService(
        rpcCall: () async => [row(code: 'luxury_celestial_crown')],
      );
      await service.load();

      expect(registry.vipTierFrame(4), isNotNull);
      expect(registry.resolve('vip_platinum_diamond')?.code, 'vip_4');
    });

    test('a deactivated frame leaves the registry on the next load', () async {
      var payload = <Map<String, dynamic>>[
        row(code: 'event_summer_halo', category: 'event'),
      ];
      final service = FrameCatalogSyncService(rpcCall: () async => payload);

      await service.load();
      expect(registry.resolve('event_summer_halo'), isNotNull);

      // `is_active = false` rows are filtered out by the RPC, so the frame is
      // simply absent. `hydrate` merges, so without resetToBuiltIns it would
      // linger forever — there was no invalidation path at all before.
      payload = <Map<String, dynamic>>[];
      expect(await service.load(forceRefresh: true), 0);
      expect(registry.resolve('event_summer_halo'), isNull);
      expect(registry.vipTierFrame(4), isNotNull, reason: 'built-ins survive');
    });

    test('one unparseable row does not cost the whole catalog', () async {
      final service = FrameCatalogSyncService(
        rpcCall: () async => [
          row(code: 'luxury_celestial_crown'),
          // vip_level is cast to num — a string there throws mid-parse.
          <String, dynamic>{
            'code': 'broken_row',
            'name': 'Broken',
            'vip_level': 'four',
          },
          'not even a map',
          row(code: 'event_summer_halo', category: 'event'),
        ],
      );

      expect(await service.load(), 2);
      expect(service.status, FrameCatalogSyncStatus.loaded);
      expect(registry.resolve('luxury_celestial_crown'), isNotNull);
      expect(registry.resolve('event_summer_halo'), isNotNull);
      expect(registry.resolve('broken_row'), isNull);
    });
  });

  group('failure degrades to the built-ins', () {
    test('an RPC error never throws and never breaks rendering', () async {
      final service = FrameCatalogSyncService(
        rpcCall: () async => throw Exception('permission denied'),
      );

      expect(await service.load(), 0);
      expect(service.status, FrameCatalogSyncStatus.loadingError);
      expect(service.rowCount, 0);
      // Avatars must keep rendering: the built-ins are still there.
      expect(registry.vipTierFrame(9), isNotNull);
      expect(
        registry.resolveRender(rawCode: 'vip_9', effectiveVipLevel: 9).mode,
        isNot(FrameRenderMode.none),
      );
    });

    test('a non-list result is reported as missing, not an error', () async {
      final service = FrameCatalogSyncService(rpcCall: () async => null);

      expect(await service.load(), 0);
      expect(service.status, FrameCatalogSyncStatus.missing);
      expect(registry.vipTierFrame(1), isNotNull);
    });

    test('an empty catalog is a successful load of zero rows', () async {
      final service = FrameCatalogSyncService(rpcCall: () async => const []);

      expect(await service.load(), 0);
      expect(service.status, FrameCatalogSyncStatus.loaded);
    });
  });

  group('caching', () {
    test('a second load inside the TTL does not hit the RPC again', () async {
      var calls = 0;
      final service = FrameCatalogSyncService(
        cacheTtl: const Duration(minutes: 10),
        rpcCall: () async {
          calls++;
          return [row(code: 'luxury_celestial_crown')];
        },
      );

      await service.load();
      await service.load();
      await service.load();
      expect(calls, 1);
    });

    test(
      'forceRefresh always refetches — admins see their own write',
      () async {
        var calls = 0;
        final service = FrameCatalogSyncService(
          rpcCall: () async {
            calls++;
            return [row(code: 'luxury_celestial_crown')];
          },
        );

        await service.load();
        await service.load(forceRefresh: true);
        expect(calls, 2);
      },
    );

    test('an expired TTL refetches', () async {
      var calls = 0;
      final service = FrameCatalogSyncService(
        // Real elapsed time, not Duration.zero: staleness is `elapsed > ttl`,
        // and on Windows two back-to-back DateTime.now() calls can land on the
        // same clock tick, which would make a zero TTL look fresh.
        cacheTtl: const Duration(milliseconds: 5),
        rpcCall: () async {
          calls++;
          return [row(code: 'luxury_celestial_crown')];
        },
      );

      await service.load();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await service.load();
      expect(calls, 2);
    });

    test('concurrent loads share one in-flight fetch', () async {
      var calls = 0;
      final service = FrameCatalogSyncService(
        rpcCall: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return [row(code: 'luxury_celestial_crown')];
        },
      );

      final results = await Future.wait([
        service.load(),
        service.load(),
        service.load(),
      ]);

      expect(calls, 1);
      expect(results, [1, 1, 1]);
    });

    test('a failed load is retried rather than cached as empty', () async {
      var calls = 0;
      final service = FrameCatalogSyncService(
        rpcCall: () async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return [row(code: 'luxury_celestial_crown')];
        },
      );

      expect(await service.load(), 0);
      expect(await service.load(forceRefresh: true), 1);
      expect(service.status, FrameCatalogSyncStatus.loaded);
    });

    test('resetForTest returns the service to unloaded', () async {
      var calls = 0;
      final service = FrameCatalogSyncService(
        rpcCall: () async {
          calls++;
          return [row(code: 'luxury_celestial_crown')];
        },
      );

      await service.load();
      service.resetForTest();
      expect(service.status, FrameCatalogSyncStatus.unloaded);
      expect(service.rowCount, 0);

      await service.load();
      expect(calls, 2);
    });
  });

  group('the shared instance', () {
    test('exists and starts unloaded before anything calls load', () {
      // Guards against a future refactor making the singleton fetch eagerly at
      // construction, which would fire an unauthenticated RPC at app start.
      expect(FrameCatalogSyncService.instance, isNotNull);
      expect(
        FrameCatalogSyncService.instance.status,
        FrameCatalogSyncStatus.unloaded,
      );
    });
  });
}
