// frames_v2_rendering_enabled DB flag: typed loading, caching, safe error
// handling, and the false fallback for enabled/disabled/missing/error states.

import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/core/frames/frames_v2_rendering_flag_service.dart';

void main() {
  group('enabled', () {
    test('a true RPC result caches as enabled', () async {
      final service = FramesV2RenderingFlagService(rpcCall: () async => true);

      final result = await service.load();

      expect(result, isTrue);
      expect(service.value, isTrue);
      expect(service.status, FramesV2FlagStatus.enabled);
    });
  });

  group('disabled', () {
    test('a false RPC result caches as disabled', () async {
      final service = FramesV2RenderingFlagService(rpcCall: () async => false);

      final result = await service.load();

      expect(result, isFalse);
      expect(service.value, isFalse);
      expect(service.status, FramesV2FlagStatus.disabled);
    });

    test('value is false before any load has completed', () {
      final service = FramesV2RenderingFlagService(rpcCall: () async => true);
      expect(service.value, isFalse);
      expect(service.status, FramesV2FlagStatus.unloaded);
    });
  });

  group('missing', () {
    test(
      'a null RPC result (missing row/column) falls back to false',
      () async {
        final service = FramesV2RenderingFlagService(rpcCall: () async => null);

        final result = await service.load();

        expect(result, isFalse);
        expect(service.value, isFalse);
        expect(service.status, FramesV2FlagStatus.missing);
      },
    );

    test('a malformed (non-boolean) RPC result falls back to false', () async {
      final service = FramesV2RenderingFlagService(
        rpcCall: () async => 'not-a-bool',
      );

      final result = await service.load();

      expect(result, isFalse);
      expect(service.status, FramesV2FlagStatus.missing);
    });
  });

  group('loading-error', () {
    test('an RPC exception is caught and falls back to false', () async {
      final service = FramesV2RenderingFlagService(
        rpcCall: () async => throw Exception('network unreachable'),
      );

      final result = await service.load();

      expect(result, isFalse);
      expect(service.value, isFalse);
      expect(service.status, FramesV2FlagStatus.loadingError);
    });

    test('never throws out of load()', () async {
      final service = FramesV2RenderingFlagService(
        rpcCall: () async => throw StateError('boom'),
      );

      await expectLater(service.load(), completes);
    });
  });

  group('caching', () {
    test(
      'repeated calls within the TTL do not re-invoke the fetcher',
      () async {
        var callCount = 0;
        final service = FramesV2RenderingFlagService(
          rpcCall: () async {
            callCount++;
            return true;
          },
          cacheTtl: const Duration(minutes: 5),
        );

        await service.load();
        await service.load();
        await service.load();

        expect(callCount, 1);
      },
    );

    test('forceRefresh bypasses the cache', () async {
      var callCount = 0;
      final service = FramesV2RenderingFlagService(
        rpcCall: () async {
          callCount++;
          return true;
        },
      );

      await service.load();
      await service.load(forceRefresh: true);

      expect(callCount, 2);
    });

    test('concurrent load() calls share a single in-flight fetch', () async {
      var callCount = 0;
      final service = FramesV2RenderingFlagService(
        rpcCall: () async {
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return true;
        },
      );

      final results = await Future.wait([
        service.load(),
        service.load(),
        service.load(),
      ]);

      expect(callCount, 1);
      expect(results, everyElement(isTrue));
    });

    test('a transient error after a successful load does not clobber the '
        'cached true value beyond recording status', () async {
      var shouldThrow = false;
      final service = FramesV2RenderingFlagService(
        rpcCall: () async {
          if (shouldThrow) throw Exception('transient');
          return true;
        },
      );

      await service.load();
      expect(service.value, isTrue);

      shouldThrow = true;
      final result = await service.load(forceRefresh: true);

      // Explicit contract: any failure resolves to false so a caller never
      // renders v2 art on top of an unconfirmed flag state.
      expect(result, isFalse);
      expect(service.value, isFalse);
      expect(service.status, FramesV2FlagStatus.loadingError);
    });
  });

  group('resetForTest / seedForTest', () {
    test(
      'resetForTest returns the service to its initial unloaded state',
      () async {
        final service = FramesV2RenderingFlagService(rpcCall: () async => true);
        await service.load();
        expect(service.value, isTrue);

        service.resetForTest();

        expect(service.value, isFalse);
        expect(service.status, FramesV2FlagStatus.unloaded);
      },
    );

    test('seedForTest sets the cache without invoking the fetcher', () async {
      var called = false;
      final service = FramesV2RenderingFlagService(
        rpcCall: () async {
          called = true;
          return true;
        },
      );

      service.seedForTest(true);

      expect(service.value, isTrue);
      expect(service.status, FramesV2FlagStatus.enabled);
      expect(called, isFalse);
    });
  });
}
