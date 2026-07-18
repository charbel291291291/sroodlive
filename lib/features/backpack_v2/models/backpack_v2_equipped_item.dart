import 'backpack_v2_catalog_item.dart';
import 'backpack_v2_expiration_state.dart';
import 'backpack_v2_slot_type.dart';

/// One row of `get_my_equipped_items_v2()` — the item currently occupying a
/// slot for the authenticated user.
///
/// Note: the RPC's own WHERE clause already excludes revoked/expired/inactive
/// rows server-side, so any row this parses is guaranteed current as of the
/// query. [expirationState] still re-derives from [expiresAt] defensively,
/// to protect against the (unusual) case of a long-lived cached snapshot
/// being read well after the query ran.
class BackpackV2EquippedItem {
  const BackpackV2EquippedItem({
    required this.slotType,
    required this.ownershipId,
    required this.catalogItem,
    required this.equippedAt,
    this.expiresAt,
  });

  final BackpackV2SlotType slotType;

  /// `user_backpack_items.id` this equip references.
  final String ownershipId;
  final BackpackV2CatalogItem catalogItem;
  final DateTime equippedAt;
  final DateTime? expiresAt;

  bool get isPermanent => expiresAt == null;

  BackpackV2ExpirationState get expirationState =>
      resolveExpirationState(expiresAt: expiresAt, isExpiredFlag: false);

  factory BackpackV2EquippedItem.fromJson(Map<String, dynamic> json) {
    final ownershipId = json['ownership_id']?.toString() ?? '';
    if (ownershipId.isEmpty) {
      throw const FormatException(
        'backpack_v2_equipped_item_missing_ownership_id',
      );
    }
    final equippedAtRaw = json['equipped_at']?.toString();
    final equippedAt = equippedAtRaw == null
        ? null
        : DateTime.tryParse(equippedAtRaw)?.toUtc();
    if (equippedAtRaw != null && equippedAt == null) {
      throw const FormatException(
        'backpack_v2_equipped_item_invalid_equipped_at',
      );
    }

    return BackpackV2EquippedItem(
      slotType: BackpackV2SlotType.fromValue(json['slot_type']?.toString()),
      ownershipId: ownershipId,
      catalogItem: BackpackV2CatalogItem.fromEquippedJson(json),
      equippedAt: equippedAt ?? DateTime.now().toUtc(),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.tryParse(json['expires_at'].toString())?.toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackpackV2EquippedItem &&
      other.slotType == slotType &&
      other.ownershipId == ownershipId &&
      other.catalogItem == catalogItem &&
      other.equippedAt == equippedAt &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode =>
      Object.hash(slotType, ownershipId, catalogItem, equippedAt, expiresAt);
}
