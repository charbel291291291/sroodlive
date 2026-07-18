import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/backpack_v2/exceptions/backpack_v2_exception.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_slot_type.dart';
import 'package:srood_live/features/backpack_v2/repositories/supabase_backpack_v2_repository.dart';
import 'package:srood_live/features/gamification/models/backpack_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _ownedRow({
  String ownershipId = 'ownership-1',
  String slotOrType = 'avatar_frame',
}) => {
  'ownership_id': ownershipId,
  'item_id': 'item-1',
  'code': 'gold_frame',
  'name': 'Gold Frame',
  'item_type': slotOrType,
  'rarity': 'legendary',
  'quantity': 1,
  'source_type': 'purchase',
  'acquired_at': '2026-07-01T10:00:00Z',
  'is_equippable': true,
  'is_consumable': false,
  'is_stackable': false,
  'is_expired': false,
  'metadata': <String, dynamic>{},
};

Map<String, dynamic> _equippedRow({
  String slotType = 'avatar_frame',
  String ownershipId = 'ownership-1',
}) => {
  'slot_type': slotType,
  'ownership_id': ownershipId,
  'item_id': 'item-1',
  'code': 'gold_frame',
  'name': 'Gold Frame',
  'rarity': 'legendary',
  'equipped_at': '2026-07-02T10:00:00Z',
};

void main() {
  group('SupabaseBackpackV2Repository.loadOwnedItems', () {
    // Scenario: empty inventory
    test(
      'returns an empty list for an empty inventory, not an error',
      () async {
        final repo = SupabaseBackpackV2Repository(
          rpcCaller: (fn, {params}) async => <dynamic>[],
        );
        expect(await repo.loadOwnedItems(), isEmpty);
      },
    );

    // Scenario: RPC failure
    test('wraps a raw PostgrestException via mapBackpackV2Error', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async => throw const PostgrestException(
          message: 'not_authenticated',
          code: '28000',
        ),
      );

      await expectLater(
        repo.loadOwnedItems(),
        throwsA(
          isA<BackpackV2Exception>().having(
            (e) => e.category,
            'category',
            BackpackV2ErrorCategory.authentication,
          ),
        ),
      );
    });

    // Scenario: malformed RPC response
    test('non-list response throws invalidResponse', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async => {'unexpected': 'shape'},
      );

      await expectLater(
        repo.loadOwnedItems(),
        throwsA(
          isA<BackpackV2Exception>().having(
            (e) => e.category,
            'category',
            BackpackV2ErrorCategory.invalidResponse,
          ),
        ),
      );
    });

    test('calls exactly get_my_backpack_v2 with no params', () async {
      String? calledFn;
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async {
          calledFn = fn;
          return <dynamic>[];
        },
      );
      await repo.loadOwnedItems();
      expect(calledFn, 'get_my_backpack_v2');
    });
  });

  group('SupabaseBackpackV2Repository.loadEquippedItems', () {
    test('calls exactly get_my_equipped_items_v2', () async {
      String? calledFn;
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async {
          calledFn = fn;
          return <dynamic>[];
        },
      );
      await repo.loadEquippedItems();
      expect(calledFn, 'get_my_equipped_items_v2');
    });

    // Scenario: permission failure
    test('42501 maps to permission', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async => throw const PostgrestException(
          message: 'permission denied',
          code: '42501',
        ),
      );

      await expectLater(
        repo.loadEquippedItems(),
        throwsA(
          isA<BackpackV2Exception>().having(
            (e) => e.category,
            'category',
            BackpackV2ErrorCategory.permission,
          ),
        ),
      );
    });
  });

  group('SupabaseBackpackV2Repository.loadInventory', () {
    test('calls both RPCs exactly once each and combines results', () async {
      final calls = <String>[];
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async {
          calls.add(fn);
          if (fn == 'get_my_backpack_v2') return [_ownedRow()];
          if (fn == 'get_my_equipped_items_v2') return [_equippedRow()];
          throw StateError('unexpected rpc $fn');
        },
      );

      final snapshot = await repo.loadInventory();

      expect(
        calls,
        unorderedEquals(['get_my_backpack_v2', 'get_my_equipped_items_v2']),
      );
      expect(snapshot.ownedItems, hasLength(1));
      expect(
        snapshot.equippedItemFor(BackpackV2SlotType.avatarFrame),
        isNotNull,
      );
    });
  });

  group('SupabaseBackpackV2Repository.equipItem', () {
    // Scenario: successful equip
    test('parses a confirmed equip response', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async {
          expect(fn, 'equip_backpack_item_v2');
          expect(params, {'p_user_backpack_item_id': 'ownership-1'});
          return {
            'equipped': true,
            'slot_type': 'avatar_frame',
            'code': 'gold_frame',
          };
        },
      );

      final result = await repo.equipItem('ownership-1');
      expect(result.code, 'gold_frame');
    });

    // Scenario: failed equip
    test('item_expired failure maps to expiredOwnership', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async => throw const PostgrestException(
          message: 'item_expired',
          code: '22023',
        ),
      );

      await expectLater(
        repo.equipItem('ownership-1'),
        throwsA(
          isA<BackpackV2Exception>().having(
            (e) => e.category,
            'category',
            BackpackV2ErrorCategory.expiredOwnership,
          ),
        ),
      );
    });
  });

  group('SupabaseBackpackV2Repository.unequipSlot', () {
    // Scenario: successful unequip
    test('returns true when a slot was cleared', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async {
          expect(fn, 'unequip_backpack_slot_v2');
          expect(params, {'p_slot_type': 'avatar_frame'});
          return true;
        },
      );

      expect(await repo.unequipSlot(BackpackV2SlotType.avatarFrame), isTrue);
    });

    test('returns false when nothing was equipped (not an error)', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async => false,
      );

      expect(await repo.unequipSlot(BackpackV2SlotType.badge), isFalse);
    });

    // Scenario: failed unequip
    test('invalid_slot_type failure maps to unsupportedItemType', () async {
      final repo = SupabaseBackpackV2Repository(
        rpcCaller: (fn, {params}) async => throw const PostgrestException(
          message: 'invalid_slot_type',
          code: '22023',
        ),
      );

      await expectLater(
        repo.unequipSlot(BackpackV2SlotType.vehicle),
        throwsA(
          isA<BackpackV2Exception>().having(
            (e) => e.category,
            'category',
            BackpackV2ErrorCategory.unsupportedItemType,
          ),
        ),
      );
    });
  });

  group('Legacy state remains untouched', () {
    // Scenario: existing legacy state remains untouched
    test('legacy BackpackItem model still parses exactly as before', () {
      final legacy = BackpackItem.fromJson({
        'id': 'legacy-ownership-1',
        'item_id': 'legacy-item-1',
        'item_type': 'avatar_frame',
        'equipped': true,
        'acquired_at': '2026-07-01T10:00:00Z',
        'item': {'id': 'legacy-item-1', 'name': 'Legacy Gold Frame'},
      });

      expect(legacy.id, 'legacy-ownership-1');
      expect(legacy.isFrame, isTrue);
      expect(legacy.item.name, 'Legacy Gold Frame');
    });
  });
}
