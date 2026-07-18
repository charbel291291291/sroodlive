import '../models/backpack_v2_equip_result.dart';
import '../models/backpack_v2_equipped_item.dart';
import '../models/backpack_v2_inventory_snapshot.dart';
import '../models/backpack_v2_owned_item.dart';
import '../models/backpack_v2_slot_type.dart';

/// Read/mutate contract for the authenticated user's Backpack V2 inventory.
///
/// Covers only operations backed by an approved, currently-active RPC in
/// `20261120000001_backpack_v2_rpcs.sql` / `20261120000002_backpack_v2_hardening.sql`.
/// Every implementation must resolve "who am I" from the server-side
/// authenticated session — never from a caller-supplied user id — and must
/// never read `backpack_catalog_items` / `user_backpack_items` /
/// `user_equipped_items` directly (writes on those tables have no RLS
/// policy at all; reads go through these RPCs so business rules — expiry,
/// revocation, active-state — are enforced consistently in one place).
///
/// Known gap — "Load catalog metadata" (an explicit M4 scope item): there is
/// no standalone catalog-browse RPC in the approved surface. Catalog fields
/// are only available embedded in [loadOwnedItems] / [loadEquippedItems]
/// rows (see [BackpackV2CatalogItem]). A separate `loadCatalog()` operation
/// is deliberately NOT implemented — inventing a direct `backpack_catalog_items`
/// table read would bypass the RPC boundary this interface exists to
/// enforce. Documented in M4_FLUTTER_DOMAIN_REPORT.md as a required
/// database follow-up before any catalog-browsing UI (e.g. a store/shop
/// screen) is built.
///
/// Known gap — "Resolve current equipped item by slot" is implemented as a
/// pure lookup on an already-loaded [BackpackV2InventorySnapshot]
/// ([BackpackV2InventorySnapshot.equippedItemFor]) rather than a repository
/// method here, since equipped items are always loaded together with owned
/// items in one [loadInventory] call — a second network operation would be
/// a duplicate request for data already in hand.
abstract class BackpackV2Repository {
  /// Calls `get_my_backpack_v2()`. Returns an empty list for a genuinely
  /// empty inventory (not an error).
  Future<List<BackpackV2OwnedItem>> loadOwnedItems();

  /// Calls `get_my_equipped_items_v2()`. Returns an empty list when no slot
  /// is currently equipped (not an error).
  Future<List<BackpackV2EquippedItem>> loadEquippedItems();

  /// Loads owned + equipped items and combines them into one snapshot.
  Future<BackpackV2InventorySnapshot> loadInventory();

  /// Semantically identical to [loadInventory] — provided as a distinctly
  /// named operation per the M4 spec ("Refresh inventory" as its own
  /// repository operation, separate from the initial "Load" operation) even
  /// though the underlying RPC calls are the same.
  Future<BackpackV2InventorySnapshot> refreshInventory();

  /// Calls `equip_backpack_item_v2(p_user_backpack_item_id)` for the given
  /// `user_backpack_items.id`. Throws [BackpackV2Exception] on any rejection
  /// (not found, revoked, expired, inactive, not equippable, equip-disabled,
  /// VIP-gated, unauthenticated). Callers must re-[loadInventory] /
  /// [refreshInventory] afterward — this method does not itself refresh
  /// local state.
  Future<BackpackV2EquipResult> equipItem(String ownershipId);

  /// Calls `unequip_backpack_slot_v2(p_slot_type)`. Returns `true` if a slot
  /// was actually cleared, `false` if the slot was already empty (both are
  /// successful outcomes — only a genuine RPC failure throws).
  Future<bool> unequipSlot(BackpackV2SlotType slot);
}
