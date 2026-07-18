import 'backpack_v2_item_type.dart';
import 'backpack_v2_rarity.dart';

/// Catalog metadata embedded in an owned or equipped item row.
///
/// There is no standalone "load catalog" RPC in the approved Backpack V2
/// surface (see backpack_v2_repository.dart doc comment) — catalog fields
/// are only ever available joined onto `get_my_backpack_v2` /
/// `get_my_equipped_items_v2` rows, so this type is always constructed via
/// one of the two factories below rather than parsed standalone.
class BackpackV2CatalogItem {
  const BackpackV2CatalogItem({
    required this.itemId,
    required this.code,
    required this.name,
    this.nameAr,
    this.nameFr,
    this.itemType,
    required this.rarity,
    this.assetKey,
    this.previewAssetKey,
  });

  final String itemId;
  final String code;
  final String name;
  final String? nameAr;
  final String? nameFr;

  /// Null when built from an equipped-item projection: `get_my_equipped_items_v2`
  /// does not return `item_type` (only `slot_type`, exposed separately on
  /// `BackpackV2EquippedItem.slotType`). Not derived/guessed from `slot_type`
  /// here, since a catalog item's `equip_slot` is not guaranteed to equal its
  /// `item_type` for future rows (see repository doc comment).
  final BackpackV2ItemType? itemType;

  final BackpackV2Rarity rarity;
  final String? assetKey;
  final String? previewAssetKey;

  /// Parses the catalog columns joined onto a `get_my_backpack_v2` row.
  factory BackpackV2CatalogItem.fromOwnedJson(Map<String, dynamic> json) {
    final itemId = json['item_id']?.toString() ?? '';
    final code = json['code']?.toString() ?? '';
    if (itemId.isEmpty || code.isEmpty) {
      throw const FormatException(
        'backpack_v2_owned_item_missing_catalog_identity',
      );
    }
    return BackpackV2CatalogItem(
      itemId: itemId,
      code: code,
      name: json['name']?.toString() ?? '',
      nameAr: json['name_ar']?.toString(),
      nameFr: json['name_fr']?.toString(),
      itemType: BackpackV2ItemType.fromValue(json['item_type']?.toString()),
      rarity: BackpackV2Rarity.fromValue(json['rarity']?.toString()),
      assetKey: json['asset_key']?.toString(),
      previewAssetKey: json['preview_asset_key']?.toString(),
    );
  }

  /// Parses the catalog columns joined onto a `get_my_equipped_items_v2` row.
  factory BackpackV2CatalogItem.fromEquippedJson(Map<String, dynamic> json) {
    final itemId = json['item_id']?.toString() ?? '';
    final code = json['code']?.toString() ?? '';
    if (itemId.isEmpty || code.isEmpty) {
      throw const FormatException(
        'backpack_v2_equipped_item_missing_catalog_identity',
      );
    }
    return BackpackV2CatalogItem(
      itemId: itemId,
      code: code,
      name: json['name']?.toString() ?? '',
      nameAr: json['name_ar']?.toString(),
      nameFr: json['name_fr']?.toString(),
      rarity: BackpackV2Rarity.fromValue(json['rarity']?.toString()),
      assetKey: json['asset_key']?.toString(),
      previewAssetKey: json['preview_asset_key']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackpackV2CatalogItem &&
      other.itemId == itemId &&
      other.code == code &&
      other.name == name &&
      other.nameAr == nameAr &&
      other.nameFr == nameFr &&
      other.itemType == itemType &&
      other.rarity == rarity &&
      other.assetKey == assetKey &&
      other.previewAssetKey == previewAssetKey;

  @override
  int get hashCode => Object.hash(
    itemId,
    code,
    name,
    nameAr,
    nameFr,
    itemType,
    rarity,
    assetKey,
    previewAssetKey,
  );
}
