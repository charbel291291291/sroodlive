// backpack_v2_ui_enabled DB flag: typed loading and safe-false fallback for
// enabled/disabled/missing/error states. Mirrors
// frames_v2_rendering_flag_service_test.dart's structure since the service
// itself is a deliberate structural mirror of FramesV2RenderingFlagService.

import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/features/backpack_v2/backpack_v2_ui_flag_service.dart';

void main() {
  // Scenario 1: flag enabled
  test('a true RPC result caches as enabled', () async {
    final service = BackpackV2UiFlagService(rpcCall: () async => true);

    final result = await service.load();

    expect(result, isTrue);
    expect(service.value, isTrue);
    expect(service.status, BackpackV2UiFlagStatus.enabled);
  });

  // Scenario 2: flag disabled
  test('a false RPC result caches as disabled', () async {
    final service = BackpackV2UiFlagService(rpcCall: () async => false);

    final result = await service.load();

    expect(result, isFalse);
    expect(service.value, isFalse);
    expect(service.status, BackpackV2UiFlagStatus.disabled);
  });

  test('value is false before any load has completed', () {
    final service = BackpackV2UiFlagService(rpcCall: () async => true);
    expect(service.value, isFalse);
    expect(service.status, BackpackV2UiFlagStatus.unloaded);
  });

  // Scenario 3: flag failure (missing/malformed/exception) falls back to
  // disabled and never throws — the screen must stay unreachable in every
  // failure case.
  test('a null RPC result (missing row/column) falls back to false', () async {
    final service = BackpackV2UiFlagService(rpcCall: () async => null);

    final result = await service.load();

    expect(result, isFalse);
    expect(service.value, isFalse);
    expect(service.status, BackpackV2UiFlagStatus.missing);
  });

  test('an RPC exception is caught and falls back to false', () async {
    final service = BackpackV2UiFlagService(
      rpcCall: () async => throw Exception('network unreachable'),
    );

    final result = await service.load();

    expect(result, isFalse);
    expect(service.value, isFalse);
    expect(service.status, BackpackV2UiFlagStatus.loadingError);
  });

  test('never throws out of load()', () async {
    final service = BackpackV2UiFlagService(
      rpcCall: () async => throw StateError('boom'),
    );

    await expectLater(service.load(), completes);
  });

  test('repeated calls within the TTL do not re-invoke the fetcher', () async {
    var callCount = 0;
    final service = BackpackV2UiFlagService(
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
  });

  test('concurrent load() calls share a single in-flight fetch', () async {
    var callCount = 0;
    final service = BackpackV2UiFlagService(
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

  test(
    'resetForTest returns the service to its initial unloaded state',
    () async {
      final service = BackpackV2UiFlagService(rpcCall: () async => true);
      await service.load();
      expect(service.value, isTrue);

      service.resetForTest();

      expect(service.value, isFalse);
      expect(service.status, BackpackV2UiFlagStatus.unloaded);
    },
  );

  test('seedForTest sets the cache without invoking the fetcher', () async {
    var called = false;
    final service = BackpackV2UiFlagService(
      rpcCall: () async {
        called = true;
        return true;
      },
    );

    service.seedForTest(true);

    expect(service.value, isTrue);
    expect(service.status, BackpackV2UiFlagStatus.enabled);
    expect(called, isFalse);
  });
}
