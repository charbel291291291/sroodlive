import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/backpack_v2/controllers/backpack_v2_controller.dart';
import 'package:srood_live/features/backpack_v2/controllers/backpack_v2_state.dart';
import 'package:srood_live/features/backpack_v2/exceptions/backpack_v2_exception.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_equip_result.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_equipped_item.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_inventory_snapshot.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_owned_item.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_slot_type.dart';
import 'package:srood_live/features/backpack_v2/repositories/backpack_v2_repository.dart';

BackpackV2OwnedItem _ownedItem(String ownershipId) =>
    BackpackV2OwnedItem.fromJson({
      'ownership_id': ownershipId,
      'item_id': 'item-1',
      'code': 'gold_frame',
      'item_type': 'avatar_frame',
      'rarity': 'legendary',
      'acquired_at': '2026-07-01T10:00:00Z',
      'is_equippable': true,
    });

BackpackV2EquippedItem _equippedItem() => BackpackV2EquippedItem.fromJson({
  'slot_type': 'avatar_frame',
  'ownership_id': 'ownership-1',
  'item_id': 'item-1',
  'code': 'gold_frame',
  'rarity': 'legendary',
  'equipped_at': '2026-07-02T10:00:00Z',
});

class FakeBackpackV2Repository implements BackpackV2Repository {
  int loadInventoryCalls = 0;
  int equipCalls = 0;
  int unequipCalls = 0;

  /// Set to control what [loadInventory]/[refreshInventory] return next.
  BackpackV2InventorySnapshot nextSnapshot =
      const BackpackV2InventorySnapshot();
  Object? nextLoadError;
  Object? nextEquipError;
  Object? nextUnequipError;

  /// When set, load blocks until this completer resolves — used to test
  /// concurrent-refresh coalescing.
  Completer<void>? loadGate;

  @override
  Future<List<BackpackV2OwnedItem>> loadOwnedItems() async =>
      nextSnapshot.ownedItems;

  @override
  Future<List<BackpackV2EquippedItem>> loadEquippedItems() async =>
      nextSnapshot.equippedBySlot.values.toList();

  @override
  Future<BackpackV2InventorySnapshot> loadInventory() async {
    loadInventoryCalls++;
    if (loadGate != null) await loadGate!.future;
    if (nextLoadError != null) throw nextLoadError!;
    return nextSnapshot;
  }

  @override
  Future<BackpackV2InventorySnapshot> refreshInventory() => loadInventory();

  @override
  Future<BackpackV2EquipResult> equipItem(String ownershipId) async {
    equipCalls++;
    if (nextEquipError != null) throw nextEquipError!;
    return const BackpackV2EquipResult(
      slotType: BackpackV2SlotType.avatarFrame,
      code: 'gold_frame',
    );
  }

  @override
  Future<bool> unequipSlot(BackpackV2SlotType slot) async {
    unequipCalls++;
    if (nextUnequipError != null) throw nextUnequipError!;
    return true;
  }
}

void main() {
  group('BackpackV2Controller.refresh', () {
    // Scenario: server-authoritative refresh (initial load path)
    test('loads inventory and transitions idle -> loading -> loaded', () async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('ownership-1')],
          equippedItems: const [],
        );
      final controller = BackpackV2Controller(repository: repo);

      expect(controller.state.status, BackpackV2Status.idle);
      await controller.refresh();

      expect(controller.state.status, BackpackV2Status.loaded);
      expect(controller.state.snapshot?.ownedItems, hasLength(1));
    });

    // Scenario: empty inventory
    test('empty inventory transitions to empty, not loaded', () async {
      final repo = FakeBackpackV2Repository();
      final controller = BackpackV2Controller(repository: repo);

      await controller.refresh();

      expect(controller.state.status, BackpackV2Status.empty);
    });

    // Scenario: concurrent refresh prevention
    test(
      'concurrent refresh calls coalesce into a single repository load',
      () async {
        final repo = FakeBackpackV2Repository()..loadGate = Completer<void>();
        final controller = BackpackV2Controller(repository: repo);

        final first = controller.refresh();
        final second = controller.refresh();

        expect(controller.state.status, BackpackV2Status.loading);
        repo.loadGate!.complete();
        await Future.wait([first, second]);

        expect(repo.loadInventoryCalls, 1);
      },
    );

    // Scenario: state preservation during refresh
    test(
      'preserves last valid snapshot while a subsequent refresh runs',
      () async {
        final repo = FakeBackpackV2Repository()
          ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
            ownedItems: [_ownedItem('ownership-1')],
            equippedItems: const [],
          );
        final controller = BackpackV2Controller(repository: repo);
        await controller.refresh();
        expect(controller.state.snapshot?.ownedItems, hasLength(1));

        repo.loadGate = Completer<void>();
        final refreshFuture = controller.refresh();

        expect(controller.state.status, BackpackV2Status.refreshing);
        expect(controller.state.snapshot?.ownedItems, hasLength(1));

        repo.loadGate!.complete();
        await refreshFuture;
      },
    );

    // Scenario: authentication error
    test('authentication failure transitions to authError', () async {
      final repo = FakeBackpackV2Repository()
        ..nextLoadError = const BackpackV2Exception(
          BackpackV2ErrorCategory.authentication,
          'not_authenticated',
        );
      final controller = BackpackV2Controller(repository: repo);

      await controller.refresh();

      expect(controller.state.status, BackpackV2Status.authError);
      expect(
        controller.state.errorCategory,
        BackpackV2ErrorCategory.authentication,
      );
    });

    // Scenario: permission error
    test('permission failure transitions to permissionError', () async {
      final repo = FakeBackpackV2Repository()
        ..nextLoadError = const BackpackV2Exception(
          BackpackV2ErrorCategory.permission,
          'permission_denied',
        );
      final controller = BackpackV2Controller(repository: repo);

      await controller.refresh();

      expect(controller.state.status, BackpackV2Status.permissionError);
    });

    // Scenario: recoverable error
    test('network failure transitions to a recoverable error state', () async {
      final repo = FakeBackpackV2Repository()
        ..nextLoadError = const BackpackV2Exception(
          BackpackV2ErrorCategory.network,
          'socketexception',
        );
      final controller = BackpackV2Controller(repository: repo);

      await controller.refresh();

      expect(controller.state.status, BackpackV2Status.error);
    });
  });

  group('BackpackV2Controller.equip', () {
    // Scenario: server-authoritative refresh after mutation
    test('equip success triggers an authoritative refresh afterward', () async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: [_ownedItem('ownership-1')],
          equippedItems: [_equippedItem()],
        );
      final controller = BackpackV2Controller(repository: repo);

      await controller.equip('ownership-1');

      expect(repo.equipCalls, 1);
      expect(repo.loadInventoryCalls, 1);
      expect(controller.state.status, BackpackV2Status.loaded);
      expect(
        controller.equippedItemForSlot(BackpackV2SlotType.avatarFrame),
        isNotNull,
      );
    });

    // Scenario: local state never marks equipped before server confirms
    test(
      'a failed equip does not synthesize an equipped entry locally',
      () async {
        final repo = FakeBackpackV2Repository()
          ..nextEquipError = const BackpackV2Exception(
            BackpackV2ErrorCategory.equipEligibility,
            'item_not_equippable',
          );
        final controller = BackpackV2Controller(repository: repo);

        await controller.equip('ownership-1');

        expect(repo.loadInventoryCalls, 0);
        expect(controller.state.snapshot, isNull);
        expect(controller.state.status, BackpackV2Status.error);
      },
    );

    // Scenario: concurrent equip prevention
    test(
      'a second equip call for the same item while pending is a no-op',
      () async {
        final repo = FakeBackpackV2Repository();
        final controller = BackpackV2Controller(repository: repo);

        final first = controller.equip('ownership-1');
        final second = controller.equip('ownership-1');
        await Future.wait([first, second]);

        expect(repo.equipCalls, 1);
      },
    );

    test(
      'equip for a different item is not blocked by a pending one',
      () async {
        final repo = FakeBackpackV2Repository();
        final controller = BackpackV2Controller(repository: repo);

        await Future.wait([
          controller.equip('ownership-1'),
          controller.equip('ownership-2'),
        ]);

        expect(repo.equipCalls, 2);
      },
    );
  });

  group('BackpackV2Controller.unequip', () {
    test(
      'unequip success triggers an authoritative refresh afterward',
      () async {
        final repo = FakeBackpackV2Repository();
        final controller = BackpackV2Controller(repository: repo);

        await controller.unequip(BackpackV2SlotType.avatarFrame);

        expect(repo.unequipCalls, 1);
        expect(repo.loadInventoryCalls, 1);
      },
    );

    test(
      'a second unequip call for the same slot while pending is a no-op',
      () async {
        final repo = FakeBackpackV2Repository();
        final controller = BackpackV2Controller(repository: repo);

        await Future.wait([
          controller.unequip(BackpackV2SlotType.avatarFrame),
          controller.unequip(BackpackV2SlotType.avatarFrame),
        ]);

        expect(repo.unequipCalls, 1);
      },
    );
  });

  group('BackpackV2Controller.equippedItemForSlot', () {
    test('resolves via the current snapshot without a network call', () async {
      final repo = FakeBackpackV2Repository()
        ..nextSnapshot = BackpackV2InventorySnapshot.fromParts(
          ownedItems: const [],
          equippedItems: [_equippedItem()],
        );
      final controller = BackpackV2Controller(repository: repo);
      await controller.refresh();

      expect(
        controller
            .equippedItemForSlot(BackpackV2SlotType.avatarFrame)
            ?.ownershipId,
        'ownership-1',
      );
      expect(controller.equippedItemForSlot(BackpackV2SlotType.badge), isNull);
    });
  });

  group('BackpackV2Controller.dispose', () {
    test('disposing prevents further state updates without throwing', () async {
      final repo = FakeBackpackV2Repository()..loadGate = Completer<void>();
      final controller = BackpackV2Controller(repository: repo);

      final refreshFuture = controller.refresh();
      controller.dispose();
      repo.loadGate!.complete();

      await refreshFuture;
      expect(controller.state.status, BackpackV2Status.loading);
    });
  });
}
