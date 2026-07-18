# M4 — Backpack V2 Flutter Domain Layer

Status: **complete**, scoped strictly to the domain layer. No UI, no existing-screen wiring, no global registration.

## 1. Architecture reused (no new architecture introduced)

- **Supabase access**: `SupabaseService.requiredClient` (`lib/core/supabase/supabase_service.dart`) — same static-wrapper pattern used by `GamificationService`, `WealthService`, `RestrictionsService`.
- **RPC call shape**: `client.rpc(name, params: {...})`, matching `GamificationService`'s existing backpack/store/task calls verbatim.
- **Controller pattern**: plain `ChangeNotifier` with an immutable state object and a `copyWith(..., bool clearError = false)` method — the same shape as `CrashV3Controller`/its state class.
- **Constructor injection**: `BackpackV2Controller({this._repository = const SupabaseBackpackV2Repository()})` and `SupabaseBackpackV2Repository({BackpackV2RpcCaller rpcCaller = _defaultRpcCaller})` mirror the existing `CrashV3Controller({this._service = const CrashV3Service()})` idiom — the only way this codebase achieves testability without a mocking library, applied one layer lower (RPC-call seam instead of service seam) since no repository-interface split existed before.
- **Error convention**: mirrors the repo's existing "short machine code" convention (e.g. `FollowService`'s `StateError('follow_blocked_by_vip')`), but typed as `BackpackV2Exception(category, code)` instead of `StateError`, since the M4 spec explicitly requires a differentiated category enum that `StateError` can't carry.
- **Test style**: plain `flutter_test` + `group`/`test`, fixture-builder functions, hand-rolled fakes — matches `test/features/gamification/gamification_models_test.dart` and `test/features/frames/*`. No mocking library was introduced.

No second DI system, networking layer, or state-management framework was added. No Riverpod/Provider/GetIt — none exist in this repo and none were introduced.

## 2. Files added

```
lib/features/backpack_v2/
  models/
    backpack_v2_item_type.dart
    backpack_v2_slot_type.dart
    backpack_v2_ownership_source.dart
    backpack_v2_rarity.dart
    backpack_v2_expiration_state.dart
    backpack_v2_equip_eligibility.dart
    backpack_v2_catalog_item.dart
    backpack_v2_owned_item.dart
    backpack_v2_equipped_item.dart
    backpack_v2_inventory_snapshot.dart
    backpack_v2_equip_result.dart
  exceptions/
    backpack_v2_exception.dart
  repositories/
    backpack_v2_repository.dart              (abstract interface)
    supabase_backpack_v2_repository.dart      (concrete implementation)
  controllers/
    backpack_v2_state.dart
    backpack_v2_controller.dart

test/features/backpack_v2/
  models/backpack_v2_models_test.dart
  backpack_v2_exception_mapping_test.dart
  repositories/supabase_backpack_v2_repository_test.dart
  controllers/backpack_v2_controller_test.dart

docs/backpack_v2/M4_FLUTTER_DOMAIN_REPORT.md   (this file)
```

**Total: 21 files** (16 under `lib/features/backpack_v2/` — 11 models, 1 exceptions, 2 repositories, 2 controllers — plus 4 under `test/features/backpack_v2/` and this report). Matches `git show --stat --oneline 67522c0` / `git diff-tree --no-commit-id --name-status -r 67522c0`: `21 files changed, 2384 insertions(+)`. An earlier draft of this report undercounted the breakdown as 20; corrected here.

No existing file was modified. No migration was touched.

## 3. Domain models

| Model | Purpose |
|---|---|
| `BackpackV2ItemType` | catalog `item_type` enum (9 values + `unknown` fallback) |
| `BackpackV2SlotType` | equip-slot enum — same 9 values as item type but modeled distinctly, since a catalog item's `equip_slot` is not guaranteed to equal its `item_type` |
| `BackpackV2OwnershipSource` | `source_type` enum (`purchase`, `admin_grant`, `event_reward`, `vip_reward`, `legacy_migration`, `unknown`) |
| `BackpackV2Rarity` | `rarity` enum (`common`…`mythic`, `unknown`) — added beyond the user's minimum list because it's a real CHECK-constrained catalog column |
| `BackpackV2ExpirationState` | `permanent` / `active` / `expired`, resolved via `resolveExpirationState()` |
| `BackpackV2EquipEligibility` | `eligible` / `notEquippable` / `expired` — explicitly documented as a client-side *hint*, not authorization (see §6) |
| `BackpackV2CatalogItem` | catalog metadata embedded in owned/equipped rows; `itemType` nullable (absent on equipped rows) |
| `BackpackV2OwnedItem` | one `get_my_backpack_v2()` row; `stableId`, `expirationState`, `isActive`, `equipEligibility`, `canEquip` getters |
| `BackpackV2EquippedItem` | one `get_my_equipped_items_v2()` row |
| `BackpackV2InventorySnapshot` | combined owned + equipped view; `equippedItemFor(slot)` pure lookup |
| `BackpackV2EquipResult` | parsed `equip_backpack_item_v2` response |

All enum `fromValue()` parsers fail safe to an explicit `unknown` member — no unknown DB value is ever guessed into a known enum value. All required-field parsing (`ownership_id`, `item_id`, `code`, timestamps) throws `FormatException` rather than silently defaulting. All models with mutable-looking fields (`List`/`Map`) implement full `==`/`hashCode` using `listEquals`/`mapEquals`. No UI formatting, colors, widgets, icons, or localized strings appear in any model.

## 4. Repository operations

`BackpackV2Repository` (interface) / `SupabaseBackpackV2Repository` (implementation):

| Method | RPC | Notes |
|---|---|---|
| `loadOwnedItems()` | `get_my_backpack_v2()` | empty list ≠ error |
| `loadEquippedItems()` | `get_my_equipped_items_v2()` | empty list ≠ error |
| `loadInventory()` | both, concurrently | futures started before either is awaited — one request per RPC, no duplication |
| `refreshInventory()` | same as `loadInventory()` | distinct method name per spec; identical body |
| `equipItem(ownershipId)` | `equip_backpack_item_v2(p_user_backpack_item_id)` | does not self-refresh; caller re-loads |
| `unequipSlot(slot)` | `unequip_backpack_slot_v2(p_slot_type)` | returns `false` (not an exception) when nothing was equipped |

Deliberately **not implemented** (per explicit scope): `get_public_equipped_items_v2` (M6 rendering), `consume_backpack_item_v2`, `cleanup_my_expired_equipped_items_v2`, and both admin grant/revoke RPCs — none were in the user's 8-operation approved list.

"Load catalog metadata" and "resolve equipped item by slot" are documented in `backpack_v2_repository.dart`'s doc comment as intentionally *not* separate repository methods (see §6 and §9).

Every call is wrapped in try/catch and passed through `mapBackpackV2Error()`; nothing reads `backpack_catalog_items` / `user_backpack_items` / `user_equipped_items` directly.

## 5. RPCs consumed

`get_my_backpack_v2`, `get_my_equipped_items_v2`, `equip_backpack_item_v2`, `unequip_backpack_slot_v2` — all four already exist and are `GRANT EXECUTE`'d to `authenticated` per the M2/M2.1 migrations. No new RPC was created.

## 6. Error mapping

`BackpackV2ErrorCategory` (10 values) + `mapBackpackV2Error(Object)`:

| Source | Category |
|---|---|
| `PostgrestException.code == '28000'` | `authentication` |
| `PostgrestException.code == '42501'` | `permission` |
| `PostgrestException.code == 'P0002'` (`backpack_item_not_found`) | `missingOwnership` |
| `22023` + `message == 'item_expired'` | `expiredOwnership` |
| `22023` + `message == 'item_revoked'` | `missingOwnership` |
| `22023` + `item_not_active` / `item_not_equippable` / `item_equip_disabled` / `vip_level_required` / `item_not_consumable` | `equipEligibility` |
| `22023` + `invalid_slot_type` | `unsupportedItemType` |
| `22023` (unrecognized message) | `databaseConstraint` |
| `23505`/`23503`/`23514`/`23502` | `databaseConstraint` |
| any other Postgres code | `invalidResponse` |
| `AuthException` | `authentication` |
| `FormatException` (malformed response) | `invalidResponse` |
| message contains socket/timeout/network/connection/handshake/unreachable | `network` |
| anything else | `unknown` |

Field names (`PostgrestException.message`/`.code`) verified directly against the installed `postgrest-2.7.0` source, not assumed.

## 7. Controller states

`BackpackV2Status`: `idle`, `loading`, `loaded`, `empty`, `refreshing`, `equipping`, `unequipping`, `error`, `authError`, `permissionError` — exactly the 10 states listed in the spec.

Behavioral guarantees, all covered by tests:
- **Coalescing refresh**: concurrent `refresh()` callers share one in-flight `Future`, never dropped, never double-fired (`_inFlightRefresh`).
- **Duplicate equip/unequip guard**: `pendingOwnershipIds` / `pendingSlots` sets block a second request for the same item/slot while one is in flight; a different item/slot is never blocked.
- **No optimistic equip**: local state is never mutated to show an item as equipped before `equipItem()`/`unequipSlot()` succeeds — the only pre-confirmation signal is the pending-set membership.
- **Server-authoritative refresh**: both `equip()` and `unequip()` call `refresh()` after a successful mutation; a failed mutation does not refresh.
- **State preservation**: `refresh()`/`equip()`/`unequip()` never clear `snapshot` — the last-known-good inventory stays visible through `refreshing`/`equipping`/`unequipping`/error transitions.
- **Slot lookup**: `equippedItemForSlot(slot)` is a pure read off the current snapshot (no network call).
- **Disposal**: `dispose()` sets an internal flag that suppresses any further `notifyListeners()`, so an in-flight request completing after disposal is a safe no-op.
- No `flutter/widgets.dart` import — only `flutter/foundation.dart` (for `ChangeNotifier`).

## 8. Tests added — 24 scenarios, all passing

61 total assertions across 4 files (`flutter test test/features/backpack_v2` → all green). Named scenarios and their location:

| # | Scenario | File |
|---|---|---|
| 1 | Valid ownership row parsing | models test |
| 2 | Valid equipped row parsing (item_type absent by design) | models test |
| 3 | Missing optional fields fall back safely | models test |
| 4 | Unknown enum values map to explicit `unknown` | models test |
| 5 | Invalid required fields throw `FormatException` (ownership_id, catalog identity, quantity, equipped_at) | models test |
| 6 | Expired ownership | models test |
| 7 | Permanent ownership | models test |
| 8 | Empty inventory | models + controller test |
| 9 | Multiple cosmetic slots equipped simultaneously | models test |
| 10 | Duplicate item rows (same slot — last wins) | models test |
| 11 | Auth failure | exception-mapping + repository test |
| 12 | Permission failure | exception-mapping + repository test |
| 13 | RPC failure (generic Postgrest error) | repository test |
| 14 | Malformed RPC response | exception-mapping + repository test |
| 15 | Successful equip | repository + controller test |
| 16 | Failed equip | repository + controller test |
| 17 | Successful unequip | repository + controller test |
| 18 | Failed unequip | repository test |
| 19 | Concurrent refresh prevention | controller test |
| 20 | Concurrent equip prevention | controller test |
| 21 | State preservation during refresh | controller test |
| 22 | Server-authoritative refresh after mutation | controller test |
| 23 | Existing legacy state remains untouched | repository test (parses legacy `BackpackItem` model unchanged) |
| 24 | Controller disposal safety | controller test |

No mocking library — all doubles are hand-rolled (`FakeBackpackV2Repository implements BackpackV2Repository`, and an injectable `BackpackV2RpcCaller` function for the Supabase-calling repository). No production/staging connectivity required for any test.

## 9. Validation commands run

```
dart format lib/features/backpack_v2 test/features/backpack_v2      # 0 changed on final pass
flutter analyze lib/features/backpack_v2 test/features/backpack_v2  # No issues found!
flutter test test/features/backpack_v2                              # 61/61 passed
flutter test test/features/gamification test/features/frames        # 52/52 passed (no regressions)
```

Static-analysis results: 0 issues. Two `info`-level lints (`prefer_initializing_formals`, `curly_braces_in_flow_control_structures`) and one `unused_import` warning were found and fixed during development; final `flutter analyze` run is clean.

Required searches (all executed via `Grep`, not assumed):
- **No existing screen imports the new controller/repository/module**: `grep -i "backpack_v2" lib/` returns matches only inside `lib/features/backpack_v2/` itself — 14 files, all new.
- **No legacy reader was replaced**: `grep "get_my_backpack\b|equip_backpack_item\b" lib/` still resolves only inside `lib/features/gamification/services/gamification_service.dart` (the pre-existing legacy service), unchanged.
- **No service-role credential was introduced**: `grep -i "service_role"` under `lib/features/backpack_v2/` returns no matches.

## 10. Security review

- **No caller-supplied user ID accepted anywhere.** Every RPC call resolves identity server-side (`auth.uid()` inside the RPC body); the Flutter layer never sends a `user_id` parameter.
- **No table bypass.** The repository calls only the four approved RPCs; it never queries `backpack_catalog_items`, `user_backpack_items`, or `user_equipped_items` directly.
- **No service-role key anywhere in the new code** (confirmed by search above). `SupabaseService.requiredClient` uses the app's normal anon/authenticated client, identical to every other feature in the repo.
- **No legacy entitlement becomes a client-side authorization decision.** `BackpackV2EquipEligibility` is explicitly documented as a *hint* only (`eligible` still requires the server RPC to succeed); the real VIP/active/equip-enabled checks stay server-side inside `equip_backpack_item_v2`, which the client cannot see or bypass.
- **Equip eligibility remains DB-enforced.** The controller/repository never marks an item equipped without a successful RPC response; a rejected RPC call always surfaces as a typed error, never a silently-accepted local state change.
- **Expired/unavailable items cannot appear equipped from cached state.** `get_my_equipped_items_v2`'s own WHERE clause excludes expired/revoked/inactive rows before the client ever sees them; the client additionally re-derives `expirationState` defensively.
- **No secrets/tokens in errors or logs.** `BackpackV2Exception` carries only the Postgres `code`/`message` (already a short machine string like `item_expired`), never `PostgrestException.details`/`.hint`/full stack, and no email, token, or profile field is included anywhere in the module.

## 11. Known gaps

1. **`get_my_backpack_v2` does not expose `equip_slot`, catalog `is_active`, `is_equip_enabled`, or `vip_level_required`**, even though the hardened `equip_backpack_item_v2` validates/uses all four server-side (and equips into the catalog's own `equip_slot`, not `item_type`). `BackpackV2CatalogItem.itemType` is therefore nullable for equipped-row-derived instances, and `BackpackV2EquipEligibility` is explicitly documented as a necessary-but-not-sufficient client hint. **Recommended DB follow-up before M5 builds an equip-affordance UI**: extend `get_my_backpack_v2`'s return columns to include `equip_slot`, `is_active`, `is_equip_enabled`, and `vip_level_required`, so the UI can show an accurate pre-flight eligibility state instead of relying solely on post-submit RPC errors.
2. **No standalone catalog-browse RPC exists.** A future store/shop screen that lists *unowned* catalog items will need a new RPC (e.g. `get_backpack_catalog()`) — out of scope for M4, called out in `backpack_v2_repository.dart`'s doc comment.
3. **`consume_backpack_item_v2`, `cleanup_my_expired_equipped_items_v2`, and the admin grant/revoke RPCs are unimplemented** in this module — deliberately excluded from the user's 8-operation scope, not a defect.

No blocking contract defect was found in the M1/M2/M2.1 migrations during M4; no migration file was touched.

## 12. M5 prerequisites

- User approval of this M4 report.
- Resolution (or explicit acceptance) of Known Gap #1 above, since M5's equip-affordance UI will be more accurate with the missing columns exposed.
- **R6 dependency**: R6 (VIP entry-effect synthesis) must complete and be approved **before** M5/M6 activate Backpack V2 rendering for the `entry_effect` slot specifically. M4's domain layer already models `entry_effect` as an ordinary `BackpackV2SlotType`/`BackpackV2ItemType` value with no special-casing, so no rework is anticipated here — but M5/M6 must not wire entry-effect rendering to this domain layer until R6 ships.

## 13. Confirmations

- **No UI components were added.** Every new file is under `models/`, `exceptions/`, `repositories/`, or `controllers/` — zero `widgets/`, zero `screens/`, zero `Widget` subclasses, zero imports of `flutter/material.dart` or `flutter/widgets.dart`.
- **No existing screen/provider/controller was modified or wired to the new module** (verified by search, §9).
- **No legacy reader (`get_my_backpack`, `equip_backpack_item`) was replaced or touched** (verified by search, §9).
- **No service-role credential was introduced** (verified by search, §9).
- **No unrelated files were touched.** `git status` after this milestone shows only new files under `lib/features/backpack_v2/`, `test/features/backpack_v2/`, and this report.
