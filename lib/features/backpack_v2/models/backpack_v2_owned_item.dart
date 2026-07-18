import 'package:flutter/foundation.dart' show mapEquals;

import 'backpack_v2_catalog_item.dart';
import 'backpack_v2_equip_eligibility.dart';
import 'backpack_v2_expiration_state.dart';
import 'backpack_v2_ownership_source.dart';

/// One row of `get_my_backpack_v2()` — an item the authenticated user owns.
class BackpackV2OwnedItem {
  const BackpackV2OwnedItem({
    required this.ownershipId,
    required this.catalogItem,
    required this.quantity,
    required this.sourceType,
    required this.acquiredAt,
    this.expiresAt,
    required this.isEquippable,
    required this.isConsumable,
    required this.isStackable,
    required this.isExpiredFlag,
    this.metadata = const {},
  });

  /// `user_backpack_items.id` — stable identifier for equip/consume calls.
  final String ownershipId;
  final BackpackV2CatalogItem catalogItem;
  final int quantity;
  final BackpackV2OwnershipSource sourceType;
  final DateTime acquiredAt;
  final DateTime? expiresAt;
  final bool isEquippable;
  final bool isConsumable;
  final bool isStackable;

  /// Server-computed `is_expired` from `get_my_backpack_v2` (evaluated
  /// against `now()` at query time — see [resolveExpirationState]).
  final bool isExpiredFlag;
  final Map<String, dynamic> metadata;

  /// Stable identifier for list diffing / equip calls.
  String get stableId => ownershipId;

  BackpackV2ExpirationState get expirationState => resolveExpirationState(
    expiresAt: expiresAt,
    isExpiredFlag: isExpiredFlag,
  );

  bool get isActive => expirationState != BackpackV2ExpirationState.expired;

  BackpackV2EquipEligibility get equipEligibility => resolveEquipEligibility(
    isEquippable: isEquippable,
    isExpired: expirationState == BackpackV2ExpirationState.expired,
  );

  bool get canEquip => equipEligibility == BackpackV2EquipEligibility.eligible;

  factory BackpackV2OwnedItem.fromJson(Map<String, dynamic> json) {
    final ownershipId = json['ownership_id']?.toString() ?? '';
    if (ownershipId.isEmpty) {
      throw const FormatException(
        'backpack_v2_owned_item_missing_ownership_id',
      );
    }
    final quantityRaw = json['quantity'];
    if (quantityRaw != null && quantityRaw is! num) {
      throw const FormatException('backpack_v2_owned_item_invalid_quantity');
    }
    final acquiredAtRaw = json['acquired_at']?.toString();
    final acquiredAt = acquiredAtRaw == null
        ? null
        : DateTime.tryParse(acquiredAtRaw)?.toUtc();
    if (acquiredAtRaw != null && acquiredAt == null) {
      throw const FormatException('backpack_v2_owned_item_invalid_acquired_at');
    }

    return BackpackV2OwnedItem(
      ownershipId: ownershipId,
      catalogItem: BackpackV2CatalogItem.fromOwnedJson(json),
      quantity: (quantityRaw as num?)?.toInt() ?? 1,
      sourceType: BackpackV2OwnershipSource.fromValue(
        json['source_type']?.toString(),
      ),
      acquiredAt: acquiredAt ?? DateTime.now().toUtc(),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.tryParse(json['expires_at'].toString())?.toUtc(),
      isEquippable: json['is_equippable'] == true,
      isConsumable: json['is_consumable'] == true,
      isStackable: json['is_stackable'] == true,
      isExpiredFlag: json['is_expired'] == true,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackpackV2OwnedItem &&
      other.ownershipId == ownershipId &&
      other.catalogItem == catalogItem &&
      other.quantity == quantity &&
      other.sourceType == sourceType &&
      other.acquiredAt == acquiredAt &&
      other.expiresAt == expiresAt &&
      other.isEquippable == isEquippable &&
      other.isConsumable == isConsumable &&
      other.isStackable == isStackable &&
      other.isExpiredFlag == isExpiredFlag &&
      mapEquals(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(
    ownershipId,
    catalogItem,
    quantity,
    sourceType,
    acquiredAt,
    expiresAt,
    isEquippable,
    isConsumable,
    isStackable,
    isExpiredFlag,
  );
}
