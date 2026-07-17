-- ============================================================================
-- M3 Step 2 — Backfill dry-run report.
--
-- READ ONLY. No INSERT/UPDATE/DELETE/TRUNCATE/ALTER anywhere in this file.
-- Produces counts only, split per legacy source system (per
-- docs/backpack_v2/m3_legacy_mapping_manifest.json — there is no single
-- unified "legacy catalog"/"legacy ownership" table, so a single combined
-- total would obscure which system each number came from).
--
-- Run via:
--   docker exec -i supabase_db_srood_live psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 < supabase/tests/m3_backfill_dry_run.sql
--
-- Output is captured verbatim into docs/backpack_v2/m3_backfill_dry_run_report.md.
-- ============================================================================

begin;
set transaction read only;

-- ── Source: legacy avatar frames (avatar_frames / user_avatar_frames) ──────

with legacy_frame_resolution as (
  select
    uaf.id,
    uaf.user_id,
    uaf.frame_id,
    uaf.frame_key,
    uaf.is_equipped,
    uaf.expires_at,
    coalesce(fc_via_map.code, fc_direct.code) as resolved_code
  from public.user_avatar_frames uaf
  left join public.frame_legacy_map flm on flm.legacy_key = uaf.frame_key
  left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
  left join public.frame_catalog fc_direct on fc_direct.code = uaf.frame_key
),
catalog_resolution as (
  select
    af.id,
    af.frame_key,
    coalesce(fc_via_map.code, fc_direct.code) as resolved_code
  from public.avatar_frames af
  left join public.frame_legacy_map flm on flm.legacy_key = af.frame_key
  left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
  left join public.frame_catalog fc_direct on fc_direct.code = af.frame_key
),
duplicate_groups as (
  select user_id, frame_id, count(*) as cnt
  from public.user_avatar_frames
  group by user_id, frame_id
  having count(*) > 1
)
select
  'R1_legacy_avatar_frames' as source_system,
  (select count(*) from catalog_resolution) as total_legacy_catalog_records,
  (select count(*) from catalog_resolution where resolved_code is not null) as mapped_catalog_records,
  (select count(*) from catalog_resolution where resolved_code is null) as unmapped_catalog_records,
  (select count(*) from public.user_avatar_frames) as legacy_ownership_rows,
  (select count(*) from legacy_frame_resolution where resolved_code is not null) as mapped_ownership_rows,
  (select count(*) from duplicate_groups) as duplicate_ownership_candidate_groups,
  (select count(*) from public.user_avatar_frames where expires_at is not null and expires_at < now()) as expired_ownership_rows,
  null::bigint as revoked_ownership_rows,
  (select count(*) from public.user_avatar_frames where is_equipped = true) as equipped_legacy_rows,
  (select count(*) from legacy_frame_resolution
     where is_equipped = true
       and (resolved_code is null or (expires_at is not null and expires_at < now()))) as invalid_equipped_rows,
  (select count(*) from public.user_avatar_frames uaf
     where not exists (select 1 from auth.users u where u.id = uaf.user_id)) as missing_user_references,
  (select count(*) from public.user_avatar_frames uaf
     where not exists (select 1 from public.avatar_frames af where af.id = uaf.frame_id)) as missing_item_references,
  (select count(*) from legacy_frame_resolution where resolved_code is null) as unknown_item_codes,
  'revoked_ownership_rows: n/a, table has no revocation column' as notes;

-- ── Source: Frame V2 (frame_catalog / user_frames) ──────────────────────────
-- frame_catalog IS the target catalog identity for this source (code reused
-- verbatim per manifest R2), so mapped == total by construction. Equipped
-- state has no column on user_frames; it is derived by matching
-- profiles.selected_avatar_frame_key against the resolved code.

with frame_v2_ownership as (
  select
    uf.id,
    uf.user_id,
    uf.frame_id,
    uf.expires_at,
    uf.revoked_at,
    fc.code as resolved_code,
    p.selected_avatar_frame_key
  from public.user_frames uf
  left join public.frame_catalog fc on fc.id = uf.frame_id
  left join public.profiles p on p.id = uf.user_id
),
duplicate_groups as (
  select user_id, frame_id, count(*) as cnt
  from public.user_frames
  group by user_id, frame_id
  having count(*) > 1
)
select
  'R2_frame_v2' as source_system,
  (select count(*) from public.frame_catalog) as total_legacy_catalog_records,
  (select count(*) from public.frame_catalog) as mapped_catalog_records,
  0::bigint as unmapped_catalog_records,
  (select count(*) from public.user_frames) as legacy_ownership_rows,
  (select count(*) from frame_v2_ownership where resolved_code is not null) as mapped_ownership_rows,
  (select count(*) from duplicate_groups) as duplicate_ownership_candidate_groups,
  (select count(*) from public.user_frames
     where revoked_at is null and expires_at is not null and expires_at < now()) as expired_ownership_rows,
  (select count(*) from public.user_frames where revoked_at is not null) as revoked_ownership_rows,
  (select count(*) from frame_v2_ownership where selected_avatar_frame_key = resolved_code) as equipped_legacy_rows,
  (select count(*) from frame_v2_ownership
     where selected_avatar_frame_key = resolved_code
       and (revoked_at is not null or (expires_at is not null and expires_at < now()))) as invalid_equipped_rows,
  (select count(*) from public.user_frames uf
     where not exists (select 1 from auth.users u where u.id = uf.user_id)) as missing_user_references,
  (select count(*) from frame_v2_ownership where resolved_code is null) as missing_item_references,
  0::bigint as unknown_item_codes,
  'equipped derived from profiles.selected_avatar_frame_key string match, per manifest R2' as notes;

-- ── Source: badges / user_badges ─────────────────────────────────────────────
-- Target catalog code naming is UNRESOLVED (manifest R3). Structural counts
-- below are independent of that naming decision — they check FK-level
-- resolution only (does badge_id point at a real badges row), not the final
-- backpack_catalog_items.code.

with badge_ownership as (
  select
    ub.id,
    ub.user_id,
    ub.badge_id,
    ub.badge_key,
    ub.is_equipped,
    ub.expires_at,
    b.id as resolved_badge_id
  from public.user_badges ub
  left join public.badges b on b.id = ub.badge_id
),
duplicate_groups as (
  select user_id, badge_id, count(*) as cnt
  from public.user_badges
  group by user_id, badge_id
  having count(*) > 1
)
select
  'R3_badges' as source_system,
  (select count(*) from public.badges) as total_legacy_catalog_records,
  null::bigint as mapped_catalog_records,
  null::bigint as unmapped_catalog_records,
  (select count(*) from public.user_badges) as legacy_ownership_rows,
  (select count(*) from badge_ownership where resolved_badge_id is not null) as mapped_ownership_rows,
  (select count(*) from duplicate_groups) as duplicate_ownership_candidate_groups,
  (select count(*) from public.user_badges where expires_at is not null and expires_at < now()) as expired_ownership_rows,
  null::bigint as revoked_ownership_rows,
  (select count(*) from public.user_badges where is_equipped = true) as equipped_legacy_rows,
  (select count(*) from badge_ownership
     where is_equipped = true
       and (resolved_badge_id is null or (expires_at is not null and expires_at < now()))) as invalid_equipped_rows,
  (select count(*) from public.user_badges ub
     where not exists (select 1 from auth.users u where u.id = ub.user_id)) as missing_user_references,
  (select count(*) from badge_ownership where resolved_badge_id is null) as missing_item_references,
  0::bigint as unknown_item_codes,
  'mapped/unmapped_catalog_records n/a: target backpack_catalog_items.code naming is unresolved (manifest R3); no revocation column on this table' as notes;

-- ── Source: backpack_items, item_type = 'avatar_frame' ──────────────────────
-- Per manifest R4: real identifier is metadata->>'frame_key', not item_id.

with backpack_frame_resolution as (
  select
    bi.id,
    bi.user_id,
    bi.equipped,
    bi.metadata ->> 'frame_key' as frame_key,
    coalesce(fc_via_map.code, fc_direct.code) as resolved_code
  from public.backpack_items bi
  left join public.frame_legacy_map flm on flm.legacy_key = bi.metadata ->> 'frame_key'
  left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
  left join public.frame_catalog fc_direct on fc_direct.code = bi.metadata ->> 'frame_key'
  where bi.item_type = 'avatar_frame'
),
duplicate_groups as (
  select user_id, metadata ->> 'frame_key' as frame_key, count(*) as cnt
  from public.backpack_items
  where item_type = 'avatar_frame'
  group by user_id, metadata ->> 'frame_key'
  having count(*) > 1
)
select
  'R4_backpack_items_avatar_frame' as source_system,
  null::bigint as total_legacy_catalog_records,
  null::bigint as mapped_catalog_records,
  null::bigint as unmapped_catalog_records,
  (select count(*) from public.backpack_items where item_type = 'avatar_frame') as legacy_ownership_rows,
  (select count(*) from backpack_frame_resolution where resolved_code is not null) as mapped_ownership_rows,
  (select count(*) from duplicate_groups) as duplicate_ownership_candidate_groups,
  null::bigint as expired_ownership_rows,
  null::bigint as revoked_ownership_rows,
  (select count(*) from public.backpack_items where item_type = 'avatar_frame' and equipped = true) as equipped_legacy_rows,
  (select count(*) from backpack_frame_resolution where equipped = true and resolved_code is null) as invalid_equipped_rows,
  (select count(*) from public.backpack_items bi
     where bi.item_type = 'avatar_frame'
       and not exists (select 1 from auth.users u where u.id = bi.user_id)) as missing_user_references,
  null::bigint as missing_item_references,
  (select count(*) from backpack_frame_resolution where resolved_code is null) as unknown_item_codes,
  'no catalog concept for this source (ownership only); expires_at/revoked_at columns do not exist on backpack_items; item_id column ignored per Finding 2 (unused, no FK)' as notes;

-- ── Source: backpack_items, item_type <> 'avatar_frame' ─────────────────────
-- Per manifest R5: real production value set for item_type was never
-- observed locally (0 rows). This block is informational only.

select
  'R5_backpack_items_other_item_types' as source_system,
  count(*) as unmapped_rows,
  array_agg(distinct item_type) as distinct_item_types_found
from public.backpack_items
where item_type <> 'avatar_frame';

-- ── Cross-source: users with conflicting simultaneous "equipped frame" ──────
-- claims across the three independent equipped-state representations
-- (Finding 4). A user is inconsistent if more than one distinct resolved
-- frame code is marked equipped for them across the three systems at once.

with legacy_equipped as (
  select uaf.user_id, coalesce(fc_via_map.code, fc_direct.code) as resolved_code
  from public.user_avatar_frames uaf
  left join public.frame_legacy_map flm on flm.legacy_key = uaf.frame_key
  left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
  left join public.frame_catalog fc_direct on fc_direct.code = uaf.frame_key
  where uaf.is_equipped = true
),
frame_v2_equipped as (
  select uf.user_id, fc.code as resolved_code
  from public.user_frames uf
  join public.frame_catalog fc on fc.id = uf.frame_id
  join public.profiles p on p.id = uf.user_id and p.selected_avatar_frame_key = fc.code
),
backpack_equipped as (
  select bi.user_id, coalesce(fc_via_map.code, fc_direct.code) as resolved_code
  from public.backpack_items bi
  left join public.frame_legacy_map flm on flm.legacy_key = bi.metadata ->> 'frame_key'
  left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
  left join public.frame_catalog fc_direct on fc_direct.code = bi.metadata ->> 'frame_key'
  where bi.item_type = 'avatar_frame' and bi.equipped = true
),
all_equipped as (
  select * from legacy_equipped
  union all
  select * from frame_v2_equipped
  union all
  select * from backpack_equipped
)
select
  'cross_source_equipped_frame_conflicts' as source_system,
  count(*) as cross_user_inconsistencies
from (
  select user_id
  from all_equipped
  where resolved_code is not null
  group by user_id
  having count(distinct resolved_code) > 1
) conflicted;

-- ── Asset paths: informational only, NOT a count ─────────────────────────────
-- File-existence-in-repository cannot be determined from SQL. This lists the
-- distinct asset locators found so a follow-up filesystem check (outside
-- this dry run) can verify them before the real backfill runs.

select
  'asset_inventory_for_followup_filesystem_check' as source_system,
  'avatar_frames.asset_url' as column_name,
  array_agg(distinct asset_url) filter (where asset_url is not null) as values,
  count(*) filter (where asset_url is null) as null_count
from public.avatar_frames
union all
select
  'asset_inventory_for_followup_filesystem_check',
  'frame_catalog.asset_url',
  array_agg(distinct asset_url) filter (where asset_url is not null),
  count(*) filter (where asset_url is null)
from public.frame_catalog
union all
select
  'asset_inventory_for_followup_filesystem_check',
  'badges.icon',
  array_agg(distinct icon) filter (where icon is not null),
  count(*) filter (where icon is null)
from public.badges;

rollback;
