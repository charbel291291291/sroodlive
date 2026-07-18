/// Client-side hint for whether an owned item can be equipped.
///
/// This is a NECESSARY-BUT-NOT-SUFFICIENT pre-check, not a full authorization
/// decision. `get_my_backpack_v2` does not return the catalog's `is_active`,
/// `is_equip_enabled`, `equip_slot`, or `vip_level_required` columns — only
/// `is_equippable` and the computed `is_expired` flag. VIP-level gating,
/// catalog-active state, per-item equip-enable, and the item's true target
/// slot remain enforced server-side inside `equip_backpack_item_v2` and are
/// only observable via that RPC's success/error response (see
/// [BackpackV2ErrorCategory.equipEligibility] in backpack_v2_exception.dart).
/// A UI may use [eligible] to enable the equip action optimistically, but
/// must still handle a server-side rejection.
enum BackpackV2EquipEligibility {
  /// No known client-side blocker. The server remains the final authority.
  eligible,

  /// The catalog item is not equippable at all (`is_equippable == false`).
  notEquippable,

  /// The ownership row is expired.
  expired,
}

BackpackV2EquipEligibility resolveEquipEligibility({
  required bool isEquippable,
  required bool isExpired,
}) {
  if (!isEquippable) return BackpackV2EquipEligibility.notEquippable;
  if (isExpired) return BackpackV2EquipEligibility.expired;
  return BackpackV2EquipEligibility.eligible;
}
