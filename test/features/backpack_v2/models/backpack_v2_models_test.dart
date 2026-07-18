import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_equip_eligibility.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_equip_result.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_equipped_item.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_expiration_state.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_inventory_snapshot.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_item_type.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_owned_item.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_ownership_source.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_rarity.dart';
import 'package:srood_live/features/backpack_v2/models/backpack_v2_slot_type.dart';

Map<String, dynamic> ownedItemFixture({
  String ownershipId = 'ownership-1',
  String itemId = 'item-1',
  String code = 'gold_frame',
  String itemType = 'avatar_frame',
  String? expiresAt,
  bool isExpired = false,
  bool isEquippable = true,
}) => {
  'ownership_id': ownershipId,
  'item_id': itemId,
  'code': code,
  'name': 'Gold Frame',
  'name_ar': 'إطار ذهبي',
  'name_fr': null,
  'item_type': itemType,
  'rarity': 'legendary',
  'asset_key': 'frames/gold.png',
  'preview_asset_key': 'frames/gold_preview.png',
  'quantity': 1,
  'source_type': 'purchase',
  'acquired_at': '2026-07-01T10:00:00Z',
  'expires_at': expiresAt,
  'is_equippable': isEquippable,
  'is_consumable': false,
  'is_stackable': false,
  'is_expired': isExpired,
  'metadata': <String, dynamic>{'tier': 3},
};

Map<String, dynamic> equippedItemFixture({
  String slotType = 'avatar_frame',
  String ownershipId = 'ownership-1',
  String? expiresAt,
}) => {
  'slot_type': slotType,
  'ownership_id': ownershipId,
  'item_id': 'item-1',
  'code': 'gold_frame',
  'name': 'Gold Frame',
  'name_ar': null,
  'name_fr': null,
  'rarity': 'legendary',
  'asset_key': 'frames/gold.png',
  'preview_asset_key': 'frames/gold_preview.png',
  'equipped_at': '2026-07-02T10:00:00Z',
  'expires_at': expiresAt,
};

void main() {
  group('BackpackV2OwnedItem.fromJson', () {
    // Scenario: valid ownership parsing
    test('parses a full valid ownership row', () {
      final item = BackpackV2OwnedItem.fromJson(ownedItemFixture());

      expect(item.ownershipId, 'ownership-1');
      expect(item.stableId, 'ownership-1');
      expect(item.catalogItem.itemId, 'item-1');
      expect(item.catalogItem.code, 'gold_frame');
      expect(item.catalogItem.itemType, BackpackV2ItemType.avatarFrame);
      expect(item.catalogItem.rarity, BackpackV2Rarity.legendary);
      expect(item.sourceType, BackpackV2OwnershipSource.purchase);
      expect(item.acquiredAt, DateTime.utc(2026, 7, 1, 10));
      expect(item.metadata, {'tier': 3});
    });

    // Scenario: missing optional fields
    test('missing optional fields fall back safely', () {
      final item = BackpackV2OwnedItem.fromJson({
        'ownership_id': 'ownership-2',
        'item_id': 'item-2',
        'code': 'plain_badge',
        'acquired_at': '2026-07-01T10:00:00Z',
      });

      expect(item.catalogItem.name, isEmpty);
      expect(item.catalogItem.nameAr, isNull);
      expect(item.expiresAt, isNull);
      expect(item.isEquippable, isFalse);
      expect(item.metadata, isEmpty);
      expect(item.quantity, 1);
    });

    // Scenario: unknown enum values map to explicit unknown state
    test(
      'unknown item_type/rarity/source_type map to unknown, not a guess',
      () {
        final item = BackpackV2OwnedItem.fromJson(
          ownedItemFixture(itemType: 'some_future_type')
            ..['rarity'] = 'ultra_rare'
            ..['source_type'] = 'airdrop',
        );

        expect(item.catalogItem.itemType, BackpackV2ItemType.unknown);
        expect(item.catalogItem.rarity, BackpackV2Rarity.unknown);
        expect(item.sourceType, BackpackV2OwnershipSource.unknown);
      },
    );

    // Scenario: invalid required fields fail safely (not silently defaulted)
    test('missing ownership_id throws FormatException', () {
      expect(
        () => BackpackV2OwnedItem.fromJson({
          'item_id': 'item-1',
          'code': 'gold_frame',
        }),
        throwsFormatException,
      );
    });

    test('missing catalog identity (item_id/code) throws FormatException', () {
      expect(
        () => BackpackV2OwnedItem.fromJson({
          'ownership_id': 'ownership-1',
          'acquired_at': '2026-07-01T10:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('non-numeric quantity throws FormatException', () {
      expect(
        () => BackpackV2OwnedItem.fromJson({
          ...ownedItemFixture(),
          'quantity': 'lots',
        }),
        throwsFormatException,
      );
    });

    // Scenario: expired ownership
    test('expired ownership resolves expirationState/canEquip correctly', () {
      final item = BackpackV2OwnedItem.fromJson(
        ownedItemFixture(expiresAt: '2020-01-01T00:00:00Z', isExpired: true),
      );

      expect(item.expirationState, BackpackV2ExpirationState.expired);
      expect(item.isActive, isFalse);
      expect(item.equipEligibility, BackpackV2EquipEligibility.expired);
      expect(item.canEquip, isFalse);
    });

    // Scenario: permanent ownership
    test('permanent ownership (null expires_at) is always active', () {
      final item = BackpackV2OwnedItem.fromJson(ownedItemFixture());

      expect(item.expiresAt, isNull);
      expect(item.expirationState, BackpackV2ExpirationState.permanent);
      expect(item.isActive, isTrue);
      expect(item.canEquip, isTrue);
    });

    test('not-equippable item resolves notEquippable eligibility', () {
      final item = BackpackV2OwnedItem.fromJson(
        ownedItemFixture(isEquippable: false),
      );

      expect(item.equipEligibility, BackpackV2EquipEligibility.notEquippable);
      expect(item.canEquip, isFalse);
    });
  });

  group('BackpackV2EquippedItem.fromJson', () {
    // Scenario: valid equipped-item parsing
    test('parses a full valid equipped row (item_type absent by design)', () {
      final item = BackpackV2EquippedItem.fromJson(equippedItemFixture());

      expect(item.slotType, BackpackV2SlotType.avatarFrame);
      expect(item.ownershipId, 'ownership-1');
      expect(item.catalogItem.itemType, isNull);
      expect(item.equippedAt, DateTime.utc(2026, 7, 2, 10));
      expect(item.isPermanent, isTrue);
    });

    test('missing ownership_id throws FormatException', () {
      expect(
        () => BackpackV2EquippedItem.fromJson({
          'slot_type': 'avatar_frame',
          'item_id': 'item-1',
          'code': 'gold_frame',
          'equipped_at': '2026-07-02T10:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('invalid equipped_at throws FormatException', () {
      expect(
        () => BackpackV2EquippedItem.fromJson({
          ...equippedItemFixture(),
          'equipped_at': 'not-a-date',
        }),
        throwsFormatException,
      );
    });

    test('unknown slot_type maps to unknown, not a guess', () {
      final item = BackpackV2EquippedItem.fromJson(
        equippedItemFixture(slotType: 'future_slot'),
      );
      expect(item.slotType, BackpackV2SlotType.unknown);
    });
  });

  group('BackpackV2InventorySnapshot', () {
    // Scenario: empty inventory
    test('empty inventory reports isEmpty and no equipped slots', () {
      final snapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: const [],
        equippedItems: const [],
      );

      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.equippedItemFor(BackpackV2SlotType.avatarFrame), isNull);
    });

    // Scenario: multiple cosmetic slots equipped simultaneously
    test('multiple cosmetic slots resolve independently', () {
      final frame = BackpackV2EquippedItem.fromJson(equippedItemFixture());
      final badge = BackpackV2EquippedItem.fromJson(
        equippedItemFixture(slotType: 'badge', ownershipId: 'ownership-2'),
      );

      final snapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: const [],
        equippedItems: [frame, badge],
      );

      expect(snapshot.equippedItemFor(BackpackV2SlotType.avatarFrame), frame);
      expect(snapshot.equippedItemFor(BackpackV2SlotType.badge), badge);
      expect(
        snapshot.equippedItemFor(BackpackV2SlotType.roomBackground),
        isNull,
      );
    });

    // Scenario: duplicate item rows (same slot equipped twice — last wins,
    // matching the DB's own (user_id, slot_type) primary key semantics)
    test('duplicate equipped rows for the same slot: last one wins', () {
      final first = BackpackV2EquippedItem.fromJson(equippedItemFixture());
      final second = BackpackV2EquippedItem.fromJson(
        equippedItemFixture(ownershipId: 'ownership-99'),
      );

      final snapshot = BackpackV2InventorySnapshot.fromParts(
        ownedItems: const [],
        equippedItems: [first, second],
      );

      expect(
        snapshot.equippedItemFor(BackpackV2SlotType.avatarFrame)?.ownershipId,
        'ownership-99',
      );
    });
  });

  group('BackpackV2EquipResult.fromJson', () {
    test('parses a confirmed equip response', () {
      final result = BackpackV2EquipResult.fromJson({
        'equipped': true,
        'slot_type': 'avatar_frame',
        'code': 'gold_frame',
      });

      expect(result.slotType, BackpackV2SlotType.avatarFrame);
      expect(result.code, 'gold_frame');
    });

    test('unconfirmed equip response throws FormatException', () {
      expect(
        () => BackpackV2EquipResult.fromJson({'equipped': false}),
        throwsFormatException,
      );
    });
  });

  group('resolveExpirationState', () {
    test(
      'server is_expired flag is authoritative over a future expires_at',
      () {
        final state = resolveExpirationState(
          expiresAt: DateTime.utc(2099),
          isExpiredFlag: true,
        );
        expect(state, BackpackV2ExpirationState.expired);
      },
    );
  });
}
