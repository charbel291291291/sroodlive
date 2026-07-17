# Backpack V2 — M3 Step 2: Backfill Dry-Run Report

**Read-only.** No legacy table was written to. The dry-run SQL
([`supabase/tests/m3_backfill_dry_run.sql`](../../supabase/tests/m3_backfill_dry_run.sql))
runs entirely inside `begin; set transaction read only; ... rollback;` — it contains no
`INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`ALTER` statement anywhere.

**Run against:** a freshly-reset local Supabase instance (`npx supabase db reset`, full
tracked migration history through `20261120000002_backpack_v2_hardening.sql`), via:

```
docker exec -i supabase_db_srood_live psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/tests/m3_backfill_dry_run.sql
```

**Critical caveat, repeated from the discovery report:** a clean local reset has **zero
real ownership rows** anywhere — only catalog seed data. Every ownership-related count
below is legitimately `0` because there is no local data to count, not because the
resolution logic found nothing to migrate. **This report must be re-run against the
production project (Supabase MCP, read-only) before the real backfill is finalized.** The
catalog-level counts (29 frames, 11 badges, asset-path checks) *are* meaningful today since
catalog data ships as tracked migration seed data.

There is no single unified "legacy catalog"/"legacy ownership" pair of numbers — per the
[mapping manifest](m3_legacy_mapping_manifest.json), five independent legacy sources exist
with incompatible shapes. Results are reported per source, matching the manifest's record
IDs.

---

## R1 — Legacy avatar frames (`avatar_frames` / `user_avatar_frames`)

| Metric | Count |
|---|---|
| Total legacy catalog records | 29 |
| Mapped catalog records | 29 |
| Unmapped catalog records | 0 |
| Legacy ownership rows | 0 |
| Mapped ownership rows | 0 |
| Duplicate ownership candidate groups | 0 |
| Expired ownership rows | 0 |
| Revoked ownership rows | n/a — table has no revocation column |
| Equipped legacy rows | 0 |
| Invalid equipped rows | 0 |
| Missing user references | 0 |
| Missing item references | 0 |
| Unknown item codes | 0 |

All 29 `avatar_frames` catalog rows resolve cleanly through `frame_legacy_map` /
`frame_catalog` — the catalog-level mapping mechanism itself is sound. Zero ownership rows
locally means duplicate/expired/equipped/invalid metrics are trivially zero and **not yet
validated against real data**.

## R2 — Frame V2 (`frame_catalog` / `user_frames`)

| Metric | Count |
|---|---|
| Total legacy catalog records | 29 |
| Mapped catalog records | 29 |
| Unmapped catalog records | 0 |
| Legacy ownership rows | 0 |
| Mapped ownership rows | 0 |
| Duplicate ownership candidate groups | 0 |
| Expired ownership rows | 0 |
| Revoked ownership rows | 0 |
| Equipped legacy rows (via `profiles.selected_avatar_frame_key` match) | 0 |
| Invalid equipped rows | 0 |
| Missing user references | 0 |
| Missing item references | 0 |
| Unknown item codes | 0 |

`frame_catalog.code` is reused verbatim as the target code (manifest R2), so mapped ==
total by construction. Equipped state is derived by matching `profiles.selected_avatar_frame_key`
against the resolved code — this join mechanism ran without error, but has never been
exercised against a real `selected_avatar_frame_key` value (0 rows).

## R3 — Badges (`badges` / `user_badges`)

| Metric | Count |
|---|---|
| Total legacy catalog records | 11 |
| Mapped catalog records | n/a — target catalog code naming unresolved (manifest R3) |
| Unmapped catalog records | n/a — same |
| Legacy ownership rows | 0 |
| Mapped ownership rows (FK-resolvable only, independent of naming) | 0 |
| Duplicate ownership candidate groups | 0 |
| Expired ownership rows | 0 |
| Revoked ownership rows | n/a — table has no revocation column |
| Equipped legacy rows | 0 |
| Invalid equipped rows | 0 |
| Missing user references | 0 |
| Missing item references | 0 |
| Unknown item codes | 0 |

Structural (FK-level) resolution works; the final `backpack_catalog_items.code` naming
question flagged in the manifest is still open and blocks computing a true mapped/unmapped
split.

## R4 — `backpack_items` (`item_type = 'avatar_frame'`)

| Metric | Count |
|---|---|
| Total legacy catalog records | n/a — this source has no catalog, ownership only |
| Legacy ownership rows | 0 |
| Mapped ownership rows (via `metadata->>'frame_key'` → `frame_legacy_map`) | 0 |
| Duplicate ownership candidate groups | 0 |
| Expired ownership rows | n/a — table has no `expires_at` column |
| Revoked ownership rows | n/a — table has no revocation column |
| Equipped legacy rows | 0 |
| Invalid equipped rows | 0 |
| Missing user references | 0 |
| Missing item references | n/a — `item_id` is unused/unenforced (Finding 2), not checked |
| Unknown item codes | 0 |

## R5 — `backpack_items` (`item_type <> 'avatar_frame'`)

| Metric | Value |
|---|---|
| Rows found | 0 |
| Distinct `item_type` values found | *(none — empty array)* |

**Unresolved per manifest R5**: local reset cannot surface what non-`avatar_frame`
`item_type` values exist in production, since this table has 0 rows locally and no CHECK
constraint enumerates valid values. This block must be re-run against production; if it
returns any rows, those `item_type` values need their own mapping records added to the
manifest before backfill — none should be migrated blind.

## Cross-source: conflicting simultaneous "equipped frame" claims

| Metric | Count |
|---|---|
| Cross-user inconsistencies (users with >1 distinct resolved frame code marked equipped across R1 legacy / R2 Frame V2 / R4 backpack_items simultaneously) | 0 |

Zero by construction (no ownership rows locally to conflict). This check is real and
reusable — it must be re-run against production, where three independently-maintained
"equipped" flags (Finding 4) could plausibly disagree for the same user.

## Asset paths — repository existence check

SQL cannot check filesystem existence, so the dry-run query only *lists* distinct asset
locators (see raw output in `supabase/tests/m3_backfill_dry_run.sql`). A follow-up
filesystem check was run manually against those values:

| Source column | Distinct non-null values | Missing from repository |
|---|---|---|
| `avatar_frames.asset_url` | 7 | **0** |
| `frame_catalog.asset_url` | 16 | **0** |
| `badges.icon` | 6 | n/a — these are Material icon identifiers (`card_giftcard`, `favorite`, `groups`, `mic`, `person_add`, `workspace_premium`), not file paths, so "missing from repository" does not apply the same way |

All 16 distinct frame asset paths referenced by seed catalog data (`assets/avatar_frames/...`,
`assets/images/vip_frames/...`) exist under the repo's `assets/` directory. `NULL`
`asset_url` counts (22 of 29 `avatar_frames` rows, 13 of 29 `frame_catalog` rows) are rows
with no asset at all — not missing files, just unpopulated columns; VIP-tier `vip_N` rows
are the largest contributor here since their visuals are currently sourced from
`VipSpec`/`VipSpecResolver`, not from this column.

---

## What this dry run does **not** cover (by design, per manifest)

- **VIP-tier synthesis candidates** (R6–R10: entry_effect, mic_effect, profile_frame,
  badge-by-tier, `vip_plans.frame_key`) — these are synthesized from tier membership, not
  migrated from an ownership row, so "legacy ownership rows" doesn't apply to them the same
  way. They remain `UNRESOLVED` in the manifest pending catalog-code/equipped-state design
  decisions, and are intentionally excluded from this counts-only dry run.
- **`gamification_store_items` / `gamification_backpack_items`** (R11) — confirmed 0 rows,
  no writer RPC; excluded per manifest, nothing to count.
- **`room_background` / `name_color` / `chat_effect` / `vehicle`** (R12) — no legacy source
  exists at all; nothing to count.
- **`store_items`** (R13) — does not exist in a clean local reset; cannot be queried at all
  until checked against production.

## Required before the real backfill runs

1. Re-run `supabase/tests/m3_backfill_dry_run.sql` (or an equivalent read-only query set)
   against the **production** project via the Supabase MCP, since every ownership-level
   metric above is `0` only because local data is empty, not because it was verified empty.
2. Enumerate real `backpack_items.item_type` values in production (R5).
3. Confirm `store_items`'s real production shape, or its absence (R13).
4. Resolve the open design questions the manifest marks `unresolved` (badge catalog-code
   naming R3; VIP-tier synthesis catalog codes and equipped-state defaults R6–R8;
   `vip_plans.frame_key` ownership-distinctness question R9) — these block writing correct
   `INSERT` logic for those sources, independent of what any dry run counts.

No legacy data was modified in the production of this report.
