# Frame System v2 — Phase 1 Audit

Read-only inventory of the avatar-frame and VIP visual system as of 2026-07-16
(branch `audit/supabase-migration-history`). Nothing in this phase modified code,
data, or assets.

## 1. Rendering widgets

| Widget | File | Used by |
|---|---|---|
| `AvatarWithFrame` | `lib/shared/widgets/avatar_with_frame.dart` | De-facto universal renderer (11 call sites): profile hero avatar, frame-picker tiles, room mic seats (`srood_occupied_mic_seat.dart`), room chat/participants/gift rail (`srood_room_avatar.dart`), private chat screen + sheet, room user profile sheet, backpack, store |
| `VipFramedAvatar` | `lib/shared/widgets/vip_framed_avatar.dart` | VIP-only variant: VIP Center (2×), Messages list |
| `SroodProfileAvatar` | `lib/features/profile/presentation/srood_profile_avatar.dart` | Profile hero header (webp frame family + `VipFrameLayout` calibration) |
| `SroodRoomAvatar` | `lib/features/rooms/presentation/room_screen/widgets/common/srood_room_avatar.dart` | Wrapper adding selection ring / agent badge around `AvatarWithFrame` |
| `VipMicFrame`, `VipMicWaveRing`, `VipProfileFrame`, `VipBadge`, `VipEntranceEffect` | `lib/features/vip/widgets/` | Mic-seat decorations, badges, entrance banners (VIP visuals, not avatar frames per se) |
| Leaderboard (`leaderboard_screen.dart`) | plain `CircleAvatar` | **Does not render frames today** (doesn't even select the frame column) |
| Search / follow lists | plain avatars | No frame rendering today |

## 2. Asset families (three parallel systems)

| Family | Path | Format | Used by |
|---|---|---|---|
| A. Custom/luxury PNG | `assets/avatar_frames/*.png`, `assets/avatar_frames/custom/*.png` (17 files incl. backups/dupes) | static PNG | `avatarFrameAssetPaths` map in `avatar_with_frame.dart` (7 mapped keys) |
| B. VIP wreath PNG | `assets/images/vip_frames/{11,2,3,vip4,5,6,7,88,99}.png` (+ unused `100.png`) | static PNG | `vipFrameAssetPath()` in `vip_spec.dart`; auto `vip_N` frames + `VipFramedAvatar` |
| C. VIP webp | `assets/vip/vipN/{frame,badge,hero}.webp` (N=1..9) | static webp | `VipAssets` (`lib/features/profile/utils/vip_assets.dart`), profile hero only, calibrated by `VipFrameLayout` |

No Supabase Storage bucket holds frames — all frame art ships in the app bundle.
`avatar_frames.asset_url` is null for most rows / points at bundled asset paths.

## 3. Constants, enums, style tables

- `avatarFrameAssetPaths` (7 hard-coded key→PNG entries) — `avatar_with_frame.dart:33`
- `_FrameStyle.fromKey` — programmatic painter styles for legacy catalog keys (`normal_*`, `luxury_*`, `vip_bronze_star`…`vip_royal_king`) — `avatar_with_frame.dart`
- `_FrameAnimType._forKey` — animation type per key — `avatar_with_frame.dart`
- `vipFrameAssetPath` / `vipFrameScale` — `lib/core/vip/vip_spec.dart:186/202`
- `VipFrameLayout` per-tier opening calibration — `lib/core/vip/vip_frame_layout.dart`
- `VipSpecResolver` (VIP 0–9 visual spec table) — `lib/core/vip/vip_spec.dart`
- `VipAssets` — `lib/features/profile/utils/vip_assets.dart`
- `VipFeatures.canUseVipFrame` — client-side frame entitlement incl. legacy alias map (`vip_bronze_star`→1 … `vip_celestial`→9) — `lib/features/rooms/utils/vip_room_features.dart:73`
- `_fallbackAvatarFrames` (offline fallback list of 7 frames) — `lib/features/profile/profile_screen.dart:73`

## 4. Database objects (from `supabase/migrations` + `migrations_next` baseline)

| Object | Definition | Notes |
|---|---|---|
| `public.avatar_frames` | `20260604143954_add_avatar_frames.sql` (+ `required_vip_level`, `is_featured` in step 14) | Catalog: `id uuid`, `frame_key unique`, `name`, `category check in (normal,luxury,vip)`, `vip_level`, `required_vip_level`, `asset_url`, `is_active`, `sort_order`. RLS: authenticated SELECT where `is_active` |
| `public.profiles.selected_avatar_frame_key` | same migration | FK → `avatar_frames.frame_key` ON UPDATE CASCADE ON DELETE SET NULL |
| `public.user_avatar_frames` | baseline | Ownership: `user_id`, `frame_id` FK, `frame_key`, `is_equipped`, `source` (default `purchase`), `purchased_at`, `expires_at`; UNIQUE(user_id, frame_id); RLS: own-or-`has_admin_access()` SELECT only |
| `equip_avatar_frame(p_frame_id uuid)` | baseline | SECURITY DEFINER; checks ownership + expiry, flips `is_equipped`, writes `profiles.selected_avatar_frame_key` |
| `purchase…frame` RPC (coin purchase) | baseline ~L14460 | Checks `required_vip_level`, debits `user_wallets`, inserts `user_avatar_frames` (source `purchase`), logs `coin_transactions` |
| `equip_backpack_item(p_backpack_item_id)` | baseline L8703 | Gamification path: sets `profiles.selected_avatar_frame_key` from `backpack_items.metadata->>'frame_key'` **without catalog/ownership-expiry validation** |
| `admin_list_avatar_frames`, `admin_update_avatar_frame` | step 14 (`20260605201708`) | Admin catalog CRUD (upsert by frame_key), audit-logged |
| `admin_user_detail` | baseline | Exposes `selected_avatar_frame_key` to admin UI |
| Seed rows | `20260604143954`, `…153925` (ruby royal), `…234734` (custom), `20260606055832` (srood v2 asset swap) | 11 base keys + luxury/custom additions |

**Migration-history caveat:** the repo is mid-reconciliation (`migrations/`,
`migrations_next/` squashed baseline, `migrations_legacy_archive/`,
`baseline_candidate/`). Latest applied-series timestamp:
`20261111000003_preserve_wallet_transaction_types.sql`. New work must be
additive files in `supabase/migrations/` sorted after that.

## 5. Entitlement flows today

- **VIP source of truth:** `profiles.vip_level` + `profiles.vip_expires_at`; client computes effective level via `VipFeatures.effectiveVipLevel` (expiry → 0). VIP frames are *implicit* entitlements (no `user_avatar_frames` row): renderers auto-apply `vip_N` and re-check `canUseVipFrame` client-side.
- **Purchased frames:** coin purchase → `user_avatar_frames` (`source='purchase'`, optional `expires_at`) → `equip_avatar_frame` RPC (server-validated).
- **Store/backpack path:** `store_items` (`item_type='avatar_frame'`) → `backpack_items` → `equip_backpack_item` (server-side, but validates only backpack ownership, not catalog state/expiry).
- **Role frames** (`custom_admin`, `custom_super_admin`, `custom_srood_live`): no server-side assignment path found; they exist as catalog rows + bundled art. Whoever sets the key wears the frame (see gap below).
- **Selection gap (pre-existing):** `profile_screen._chooseAvatarFrame` updates `profiles.selected_avatar_frame_key` **directly from the client**; the only guard is the FK and client-side `isUnlockedFor`/`canUseVipFrame`. A crafted API call can select any active catalog key (incl. admin frames). Renderers strip unauthorized `vip_*` keys client-side only.

## 6. Admin controls today

- `AdminService.fetchAvatarFrames` / `updateAvatarFrame` (`admin_service.dart:612/627`) → assets tab inside `admin_dashboard_screen.dart` (~L2712), edit-in-place of catalog rows.
- `vip_visual_preview_screen.dart` — VIP visual preview for admins.
- No admin assign/revoke-frame-to-user UI or RPC exists.
- Admin authorization: `has_admin_access()` SQL + existing dashboard gating (reused, not duplicated, by v2).

## 7. Tests touching frames/VIP

`test/features/vip/vip_models_test.dart`, `test/features/rooms/room_mic_seat_size_contract_test.dart`,
`test/features/rooms/room_ui_v2_widgets_test.dart`, `test/contracts/admin_audit_vip_security_contract_test.dart`,
`test/features/gamification/gamification_models_test.dart`, profile UI tests (avatar shell contract).
No test covers: legacy key mapping, expired entitlement display, frame fallback, animated disposal.

## 8. Required audit table

| Current frame | Identifier | Asset location | DB references | Screens using it | Unlock condition | Animation | Migration destination | Removal risk |
|---|---|---|---|---|---|---|---|---|
| Silver Ring | `normal_silver_ring` | none (painter) | `avatar_frames` row | picker, any avatar | free | overlay only | v2 catalog `normal_silver_ring` | Low |
| Blue Glow | `normal_blue_glow` | none (painter) | `avatar_frames` row | same | free | overlay only | v2 `normal_blue_glow` | Low |
| Soft Gold | `normal_soft_gold` | none (painter) | `avatar_frames` row | same | free | overlay only | v2 `normal_soft_gold` | Low |
| Royal Gold | `luxury_royal_gold` | none (painter) | `avatar_frames` row | same | free (luxury) | shimmer overlay | v2 `luxury_royal_gold` | Low |
| Diamond Purple | `luxury_diamond_purple` | none (painter) | `avatar_frames` row | same | free (luxury) | sparkle overlay | v2 `luxury_diamond_purple` | Low |
| Black Gold Crown | `luxury_black_gold_crown` | none (painter) | `avatar_frames` row | same | free (luxury) | sparkle overlay | v2 `luxury_black_gold_crown` | Low |
| Ruby Royal (+Dark) | `luxury_ruby_royal`, `_dark` | `assets/avatar_frames/luxury_ruby_royal*.png` | `avatar_frames` rows (`…155118`) | same | free (luxury) | shimmer overlay | v2 same codes | Low |
| SrOOd Live Frame | `custom_srood_live` | `assets/avatar_frames/custom/srood_live_frame_final.png` (+v2/backup dupes) | `avatar_frames` row (`…234734`) | same | none server-side (role frame de facto) | sparkle overlay | v2 `custom_srood_live`, `required_role='official'` | **Medium** (role enforcement changes behavior) |
| Admin Frame | `custom_admin` | `assets/avatar_frames/custom/admin_frame_transparent.png` | `avatar_frames` row | same | none server-side | sparkle overlay | v2 `custom_admin`, `required_role='admin'` | **Medium** |
| Super Admin Frame | `custom_super_admin` | `assets/avatar_frames/custom/super_admin_frame_transparent.png` | `avatar_frames` row | same | none server-side | sparkle overlay | v2 `custom_super_admin`, `required_role='super_admin'` | **Medium** |
| Luxury Gold | `custom_luxury_gold` | `custom/luxury_gold_frame_transparent.png` | `avatar_frames` row | same | free/purchase | shimmer overlay | v2 same code | Low |
| Luxury Diamond | `custom_luxury_diamond` | `custom/luxury_diamond_frame_transparent.png` | `avatar_frames` row | same | free/purchase | shimmer overlay | v2 same code | Low |
| Legacy VIP names 1–5 | `vip_bronze_star`, `vip_silver_flame`, `vip_gold_crown`, `vip_platinum_diamond`, `vip_royal_king` | none (painters) | `avatar_frames` rows | picker (vip group) | client `canUseVipFrame` tier 1–5 | glow overlay | alias-map → v2 `vip_1`…`vip_5` | **Medium** (aliases must keep resolving) |
| Auto VIP wreaths 1–9 | implicit `vip_1`…`vip_9` (never stored in DB) | `assets/images/vip_frames/*.png` | none (derived from `profiles.vip_level`) | every `AvatarWithFrame` site | active VIP ≥ N | glow overlay | v2 `vip_1`…`vip_9` implicit entitlement | **High** (default look of all VIP users) |
| Profile-hero webp 1–9 | per-level assets | `assets/vip/vipN/frame.webp` | none | profile hero only | active VIP = N | none | keep as hero variant of `vip_N` | Medium |
| Backpack/store frames | `backpack_items.metadata->>'frame_key'` | store item image URLs | `store_items`, `backpack_items` | store, backpack | coin purchase | n/a | ownership rows in v2 `user_frames` (mapped) | **High** (paid entitlements) |

Categories requested but with no current implementation (Agency Owner, Host,
Recharge Owner, Room Owner, Event, Achievement, Seasonal, Special Edition,
Reward): **no code, assets, or rows exist** — they enter v2 as new catalog
categories only, no migration needed.
