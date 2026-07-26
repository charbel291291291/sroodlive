# Frame System v2 — Migration, Compatibility & Cleanup Plan

## Compatibility strategy (why nothing breaks)

1. **Selection pointer unchanged.** v2 keeps `profiles.selected_avatar_frame_key`
   as the single selection source. Every current renderer keeps reading it.
2. **Codes are FK-safe.** Every v2 catalog code also exists as a row in the
   legacy `avatar_frames` table (seeded by the migration / mirrored by
   `admin_upsert_frame_v2`), so the existing FK constraint keeps holding.
3. **Legacy keys keep resolving.** `frame_legacy_map` (server) and
   `FrameRegistry.legacyAliases` (client) map every pre-v2 key; identity rows
   cover keys that carry over unchanged.
4. **Rendering delegates.** `SroodAvatarFrame` renders every pre-v2 code
   through the existing `AvatarWithFrame` pipeline — pixel-identical output.
5. **Enforcement is staged.** The selection guard trigger ships in LOG-ONLY
   mode (`frame_settings_v2.enforce_selection = false`). Violations are
   recorded in `frame_ownership_audit`, nothing is blocked. Enabling
   enforcement is an explicit admin action after the log is reviewed.
6. **Ownership is copied, not moved.** `user_avatar_frames` rows are
   backfilled into `user_frames` with `source='legacy_migration'`; originals
   are untouched and still honored by `frames_v2_user_can_use`.

## Rollout order

1. Apply `20261112000000_frame_system_v2.sql` (additive).
2. Ship the app update (registry + widget + admin screen; zero visual change).
3. Review `frames_v2_migration_report()` → unmapped keys must be empty.
4. Watch `frame_ownership_audit` violations for ≥ 1 week.
5. Produce final VIP 1–9 assets (docs/frames_v2/ASSET_PROMPTS.md), register
   them, QA in the admin preview, then enable `preferV2TierArt` at call sites.
6. Enable selection enforcement (`admin_set_frame_enforcement_v2(true)`).
7. Migrate call sites from `AvatarWithFrame`/`VipFramedAvatar` to
   `SroodAvatarFrame` screen by screen.
8. Only then: cleanup below, after explicit approval.

## Phase 9 — Cleanup candidates (NOTHING deleted yet; requires approval)

### Files proposed for deletion (after step 7 completes)
- `lib/shared/widgets/vip_framed_avatar.dart` (3 call sites → SroodAvatarFrame)
- Duplicate/backup art: `assets/avatar_frames/custom/srood_live_frame.png`,
  `srood_live_frame_backup.png`, `srood_live_frame_v2_backup.png`,
  `srood_live_frame_v2.png` (superseded by `srood_live_frame_final.png` —
  note: the DB seed `20260606055832` points at `_v2`; keep until the catalog
  row is repointed), `super_admin_frame.png`, `admin_frame.png`,
  `luxury_gold_frame.png`, `luxury_diamond_frame.png` (non-transparent
  originals), `assets/images/vip_frames/100.png` (unreferenced)

### Constants/widgets replaced (deprecate, then delete)
- `avatarFrameAssetPaths` map + `_FrameStyle`/painters in
  `avatar_with_frame.dart` → registry + tier painters (AvatarWithFrame itself
  stays until every call site is migrated)
- `_fallbackAvatarFrames` in `profile_screen.dart` → `FrameRegistry.all()`
- `vipFrameAssetPath`/`vipFrameScale` → catalog `asset_url` + registry ratio

### Database rows proposed for archival (mark inactive, never hard-delete)
- Legacy named VIP frames (`vip_bronze_star` … `vip_royal_king`) →
  `is_active=false` once no profile selects them
  (`select count(*) from profiles where selected_avatar_frame_key='vip_bronze_star'` …)
- `user_avatar_frames` → keep as read-only history; stop writing after the
  purchase RPC is repointed at `user_frames`

### Storage assets
- None (no storage bucket holds frames today).

### Remaining references to check before each deletion
- `grep -rn "avatarFrameAssetPaths\|vipFrameAssetPath\|VipFramedAvatar\|AvatarWithFrame(" lib/`
- `frames_v2_migration_report()` unmapped lists empty
- `select distinct selected_avatar_frame_key from profiles` ⊆ frame_catalog codes ∪ legacy map

## Rollback procedure

App: revert the Flutter changes (registry/widget/admin screen are additive —
no existing screen depends on them except the admin dashboard card).

Database (safe at any point before cleanup):
```sql
drop trigger if exists frames_v2_guard_selection_trg on public.profiles;
drop function if exists public.frames_v2_guard_selection();
-- optionally the RPCs and tables, in reverse dependency order (see the
-- rollback inventory at the bottom of 20261112000000_frame_system_v2.sql)
```
The only rows added to a legacy table are `avatar_frames.vip_1 … vip_9`;
deleting them is safe (`profiles` FK is ON DELETE SET NULL) but only needed
if a full rollback is required — they are harmless otherwise.
