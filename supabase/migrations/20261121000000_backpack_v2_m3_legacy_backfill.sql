-- ============================================================================
-- BACKPACK SYSTEM V2 — M3 legacy backfill (DRAFT). NOT YET ACTIVATED.
--
-- This migration is STRICTLY ADDITIVE and NEVER runs automatically:
--   * It creates a new issues-log table and a new SECURITY DEFINER function,
--     public.backpack_v2_run_m3_backfill(). The function is written but is
--     NOT invoked by this migration file — nobody's data changes just
--     because this migration is applied. The backfill only happens when the
--     function is explicitly called (service-role/superuser only — no grant
--     to authenticated/anon, see bottom of file).
--   * No legacy table (avatar_frames, user_avatar_frames, frame_catalog,
--     user_frames, backpack_items, badges, user_badges, vip_plans,
--     user_vip_subscriptions, store_items) is read from more than
--     SELECT-only, and none is ever written to, altered, or dropped.
--   * No existing reader (profile_screen.dart's selected_avatar_frame_key
--     write path, equip_backpack_item(), frames_v2 RPCs, etc.) is touched.
--     Backpack V2 rendering stays unactivated — this migration only
--     populates rows a future, separately-approved milestone will read.
--
-- Scope, per docs/backpack_v2/m3_legacy_mapping_manifest.json: only R1
-- (legacy avatar_frames), R2 (Frame V2 / user_frames), and R4 (backpack_items
-- item_type='avatar_frame') are migrated into real ownership rows. Every
-- other manifest record (R3, R5, R6-R10, R13) is UNRESOLVED or BLOCKED per
-- the manifest and is instead logged into backpack_v2_migration_issues,
-- never migrated. R11 (dead infra, 0 rows) and R12 (no legacy source at all)
-- need no log entries — there is nothing to skip.
--
-- Equipped-state tie-break (three legacy systems can independently claim a
-- user has a frame "equipped", per discovery report Finding 4): priority is
--   1. R2 — profiles.selected_avatar_frame_key matched against frame_catalog
--      (the only column actually rendered by the app today, so it is the
--      most truthful signal of current real-world equipped state)
--   2. R4 — backpack_items.equipped (the only one of the three legacy
--      equipped flags that is enforced exclusive-per-item_type by
--      equip_backpack_item())
--   3. R1 — user_avatar_frames.is_equipped (not exclusivity-enforced by any
--      constraint)
-- Any lower-priority claim overridden by a higher one is logged as
-- 'equip_conflict_resolved', never silently dropped.
--
-- Idempotency: every insert is retry-safe.
--   * Catalog upsert: ON CONFLICT (code) DO UPDATE.
--   * Ownership inserts: ON CONFLICT (user_id, item_id) WHERE is_revoked =
--     false DO NOTHING, against the existing user_backpack_items_active_unique
--     partial index (M1). Rows already migrated by a prior run of this same
--     function are silently skipped (no duplicate log entry, see below).
--   * Equip inserts: ON CONFLICT (user_id, slot_type) DO UPDATE ... WHERE
--     user_backpack_item_id IS DISTINCT FROM excluded.user_backpack_item_id
--     — reruns that resolve to the same winner touch nothing.
--   * Issue log entries: ON CONFLICT on a dedicated dedupe index (batch,
--     source_table, source_row_id, source_user_id, issue_type) DO NOTHING —
--     rerunning the function never duplicates a log entry. A row that was
--     skipped as "duplicate/superseded" on run 1 is distinguished from a row
--     that is merely "already migrated by myself" on run 2 by comparing the
--     existing row's source_reference — only a genuine different-source
--     collision is logged, not routine idempotent no-ops.
--
-- Rollback: see the comment block at the bottom of this file. No destructive
-- SQL is included here — rollback of a backfill this size requires explicit
-- approval and a reviewed one-off script, not a blind DROP/DELETE.
-- ============================================================================

-- ── 1. Migration issues log ──────────────────────────────────────────────

create table if not exists public.backpack_v2_migration_issues (
  id uuid primary key default gen_random_uuid(),
  batch text not null,
  source_table text not null,
  source_row_id text,
  source_user_id uuid,
  issue_type text not null check (issue_type in (
    'missing_catalog_mapping', 'revoked_source', 'duplicate_superseded',
    'equip_conflict_resolved', 'missing_user_reference', 'unresolved_mapping',
    'deferred_synthesis', 'blocked_source_unavailable'
  )),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Dedupe key: reruns of the same batch never insert a duplicate log row for
-- the same source row / user / issue. coalesce() covers category-level
-- issues (R6-R10, R13) that have no source_row_id/source_user_id at all.
create unique index if not exists backpack_v2_migration_issues_dedupe
  on public.backpack_v2_migration_issues (
    batch, source_table, coalesce(source_row_id, ''),
    coalesce(source_user_id::text, ''), issue_type
  );
create index if not exists backpack_v2_migration_issues_batch_idx
  on public.backpack_v2_migration_issues (batch, issue_type);

alter table public.backpack_v2_migration_issues enable row level security;

drop policy if exists "backpack_v2 migration issues admin read" on public.backpack_v2_migration_issues;
create policy "backpack_v2 migration issues admin read"
  on public.backpack_v2_migration_issues for select to authenticated
  using (public.has_admin_access());
-- No insert/update/delete policy: written only by the SECURITY DEFINER
-- backfill function below, which is never granted to authenticated/anon.

grant select on public.backpack_v2_migration_issues to authenticated;

-- ── 2. Backfill function ─────────────────────────────────────────────────
-- SECURITY DEFINER, search_path='', and (see grants at the bottom) NOT
-- granted to authenticated or anon at all — stricter than every other V2
-- RPC in this system on purpose: this function must only ever be invoked
-- from the SQL editor / service role / a future explicitly-approved admin
-- tool, never from client code, per "do not activate Backpack V2 rendering
-- yet" and "do not expose admin RPCs to normal users".

create or replace function public.backpack_v2_run_m3_backfill()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch text := 'm3_legacy_backfill_v1';
  v_catalog_count int;
  v_r2_inserted int;
  v_r1_inserted int;
  v_r4_inserted int;
  v_equip_count int;
  v_issues_count int;
begin
  -- ── Catalog upsert: frame_catalog -> backpack_catalog_items ────────────
  -- localized_names has no confirmed ar/fr key convention (discovery report
  -- open question), so it is preserved losslessly inside metadata rather
  -- than guessed into name_ar/name_fr.
  with catalog_ins as (
    insert into public.backpack_catalog_items (
      code, name, item_type, equip_slot, rarity, asset_key, preview_asset_key,
      metadata, is_active, is_equippable, vip_level_required, sort_order
    )
    select
      fc.code, fc.name, 'avatar_frame', 'avatar_frame', fc.rarity,
      fc.asset_url, fc.thumbnail_url,
      jsonb_build_object(
        'legacy_source', 'frame_catalog',
        'legacy_frame_catalog_id', fc.id,
        'localized_names', fc.localized_names,
        'category', fc.category,
        'asset_type', fc.asset_type,
        'animation_url', fc.animation_url,
        'is_animated', fc.is_animated,
        'unlock_type', fc.unlock_type,
        'unlock_value', fc.unlock_value
      ),
      fc.is_active, true, fc.vip_level, fc.sort_order
    from public.frame_catalog fc
    on conflict (code) do update set
      name = excluded.name,
      rarity = excluded.rarity,
      asset_key = excluded.asset_key,
      preview_asset_key = excluded.preview_asset_key,
      metadata = excluded.metadata,
      is_active = excluded.is_active,
      vip_level_required = excluded.vip_level_required,
      sort_order = excluded.sort_order
    returning 1
  )
  select count(*) into v_catalog_count from catalog_ins;

  -- ── R2 — Frame V2 (user_frames), highest ownership priority ────────────
  -- Only active (revoked_at is null) rows are valid ownership. Revoked rows
  -- are never merged into active ownership — logged instead.
  insert into public.backpack_v2_migration_issues
    (batch, source_table, source_row_id, source_user_id, issue_type, detail)
  select v_batch, 'user_frames', uf.id::text, uf.user_id, 'revoked_source',
    jsonb_build_object('revoked_at', uf.revoked_at)
  from public.user_frames uf
  where uf.revoked_at is not null
  on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
    do nothing;

  with r2_resolved as (
    select
      uf.id as source_id, uf.user_id, uf.expires_at,
      fc.code as resolved_code, bci.id as catalog_item_id
    from public.user_frames uf
    join public.frame_catalog fc on fc.id = uf.frame_id
    left join public.backpack_catalog_items bci on bci.code = fc.code
    where uf.revoked_at is null
  ),
  log_unmapped as (
    insert into public.backpack_v2_migration_issues
      (batch, source_table, source_row_id, source_user_id, issue_type, detail)
    select v_batch, 'user_frames', source_id::text, user_id, 'missing_catalog_mapping',
      jsonb_build_object('reason', 'frame_catalog row has no matching backpack_catalog_items.code after upsert')
    from r2_resolved
    where catalog_item_id is null
    on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
      do nothing
    returning 1
  ),
  r2_ins as (
    insert into public.user_backpack_items (user_id, item_id, source_type, source_reference, acquired_at, expires_at)
    select user_id, catalog_item_id, 'legacy_migration', 'user_frames:' || source_id, now(), expires_at
    from r2_resolved
    where catalog_item_id is not null
    on conflict (user_id, item_id) where is_revoked = false do nothing
    returning user_id
  )
  select count(*) into v_r2_inserted from r2_ins;

  -- ── R1 — legacy avatar frames (user_avatar_frames) ──────────────────────
  with r1_resolved as (
    select
      uaf.id as source_id, uaf.user_id, uaf.expires_at,
      coalesce(fc_via_map.code, fc_direct.code) as resolved_code
    from public.user_avatar_frames uaf
    left join public.frame_legacy_map flm on flm.legacy_key = uaf.frame_key
    left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
    left join public.frame_catalog fc_direct on fc_direct.code = uaf.frame_key
  ),
  r1_mapped as (
    select r.*, bci.id as catalog_item_id
    from r1_resolved r
    left join public.backpack_catalog_items bci on bci.code = r.resolved_code
  ),
  log_unmapped as (
    insert into public.backpack_v2_migration_issues
      (batch, source_table, source_row_id, source_user_id, issue_type, detail)
    select v_batch, 'user_avatar_frames', source_id::text, user_id, 'missing_catalog_mapping',
      jsonb_build_object('reason', 'frame_key has no frame_legacy_map/frame_catalog match')
    from r1_mapped
    where catalog_item_id is null
    on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
      do nothing
    returning 1
  ),
  r1_ins as (
    insert into public.user_backpack_items (user_id, item_id, source_type, source_reference, acquired_at, expires_at)
    select user_id, catalog_item_id, 'legacy_migration', 'user_avatar_frames:' || source_id, now(), expires_at
    from r1_mapped
    where catalog_item_id is not null
    on conflict (user_id, item_id) where is_revoked = false do nothing
    returning user_id
  ),
  log_superseded as (
    insert into public.backpack_v2_migration_issues
      (batch, source_table, source_row_id, source_user_id, issue_type, detail)
    select v_batch, 'user_avatar_frames', m.source_id::text, m.user_id, 'duplicate_superseded',
      jsonb_build_object('resolved_code', m.resolved_code, 'existing_source_reference', ubi.source_reference)
    from r1_mapped m
    join public.user_backpack_items ubi
      on ubi.user_id = m.user_id and ubi.item_id = m.catalog_item_id and ubi.is_revoked = false
    where m.catalog_item_id is not null
      and ubi.source_reference is distinct from ('user_avatar_frames:' || m.source_id)
    on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
      do nothing
    returning 1
  )
  select count(*) into v_r1_inserted from r1_ins;

  -- ── R4 — backpack_items (item_type = 'avatar_frame') ────────────────────
  -- item_id is unused/unenforced (Finding 2); real identifier is
  -- metadata->>'frame_key'. user_id has NO foreign key on this legacy
  -- table, so a missing user reference is a real, checked case here.
  with r4_resolved as (
    select
      bi.id as source_id, bi.user_id,
      coalesce(fc_via_map.code, fc_direct.code) as resolved_code,
      exists (select 1 from auth.users u where u.id = bi.user_id) as user_exists
    from public.backpack_items bi
    left join public.frame_legacy_map flm on flm.legacy_key = bi.metadata ->> 'frame_key'
    left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
    left join public.frame_catalog fc_direct on fc_direct.code = bi.metadata ->> 'frame_key'
    where bi.item_type = 'avatar_frame'
  ),
  r4_mapped as (
    select r.*, bci.id as catalog_item_id
    from r4_resolved r
    left join public.backpack_catalog_items bci on bci.code = r.resolved_code
  ),
  log_missing_user as (
    insert into public.backpack_v2_migration_issues
      (batch, source_table, source_row_id, source_user_id, issue_type, detail)
    select v_batch, 'backpack_items', source_id::text, user_id, 'missing_user_reference',
      jsonb_build_object('reason', 'backpack_items.user_id has no FK to auth.users and does not resolve to an existing user')
    from r4_mapped
    where not user_exists
    on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
      do nothing
    returning 1
  ),
  log_unmapped as (
    insert into public.backpack_v2_migration_issues
      (batch, source_table, source_row_id, source_user_id, issue_type, detail)
    select v_batch, 'backpack_items', source_id::text, user_id, 'missing_catalog_mapping',
      jsonb_build_object('reason', 'metadata->>frame_key has no frame_legacy_map/frame_catalog match')
    from r4_mapped
    where user_exists and catalog_item_id is null
    on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
      do nothing
    returning 1
  ),
  r4_ins as (
    insert into public.user_backpack_items (user_id, item_id, source_type, source_reference, acquired_at, expires_at)
    select user_id, catalog_item_id, 'legacy_migration', 'backpack_items:' || source_id, now(), null
    from r4_mapped
    where user_exists and catalog_item_id is not null
    on conflict (user_id, item_id) where is_revoked = false do nothing
    returning user_id
  ),
  log_superseded as (
    insert into public.backpack_v2_migration_issues
      (batch, source_table, source_row_id, source_user_id, issue_type, detail)
    select v_batch, 'backpack_items', m.source_id::text, m.user_id, 'duplicate_superseded',
      jsonb_build_object('resolved_code', m.resolved_code, 'existing_source_reference', ubi.source_reference)
    from r4_mapped m
    join public.user_backpack_items ubi
      on ubi.user_id = m.user_id and ubi.item_id = m.catalog_item_id and ubi.is_revoked = false
    where m.user_exists and m.catalog_item_id is not null
      and ubi.source_reference is distinct from ('backpack_items:' || m.source_id)
    on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
      do nothing
    returning 1
  )
  select count(*) into v_r4_inserted from r4_ins;

  -- ── Equipped-state migration: R2 > R4 > R1 tie-break ────────────────────
  -- Only migrates equip state onto ownership rows that are valid right now
  -- (present, not revoked, not expired, catalog active/equippable/equip-
  -- enabled). Expired or otherwise-invalid claims are never equipped.
  with r2_claim as (
    select uf.user_id, fc.code as resolved_code, 1 as priority, 'user_frames' as claim_source
    from public.user_frames uf
    join public.frame_catalog fc on fc.id = uf.frame_id
    join public.profiles p on p.id = uf.user_id and p.selected_avatar_frame_key = fc.code
    where uf.revoked_at is null
  ),
  r4_claim as (
    select bi.user_id, coalesce(fc_via_map.code, fc_direct.code) as resolved_code, 2 as priority, 'backpack_items' as claim_source
    from public.backpack_items bi
    left join public.frame_legacy_map flm on flm.legacy_key = bi.metadata ->> 'frame_key'
    left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
    left join public.frame_catalog fc_direct on fc_direct.code = bi.metadata ->> 'frame_key'
    where bi.item_type = 'avatar_frame' and bi.equipped = true
      and exists (select 1 from auth.users u where u.id = bi.user_id)
  ),
  r1_claim as (
    select uaf.user_id, coalesce(fc_via_map.code, fc_direct.code) as resolved_code, 3 as priority, 'user_avatar_frames' as claim_source
    from public.user_avatar_frames uaf
    left join public.frame_legacy_map flm on flm.legacy_key = uaf.frame_key
    left join public.frame_catalog fc_via_map on fc_via_map.code = flm.code
    left join public.frame_catalog fc_direct on fc_direct.code = uaf.frame_key
    where uaf.is_equipped = true
  ),
  all_claims as (
    select * from r2_claim where resolved_code is not null
    union all
    select * from r4_claim where resolved_code is not null
    union all
    select * from r1_claim where resolved_code is not null
  ),
  ranked as (
    select
      ac.user_id, ac.resolved_code, ac.priority, ac.claim_source,
      ubi.id as ownership_id, ubi.expires_at,
      bci.is_active, bci.is_equippable, bci.is_equip_enabled, bci.equip_slot,
      row_number() over (partition by ac.user_id order by ac.priority asc) as rn
    from all_claims ac
    join public.backpack_catalog_items bci on bci.code = ac.resolved_code
    left join public.user_backpack_items ubi
      on ubi.user_id = ac.user_id and ubi.item_id = bci.id and ubi.is_revoked = false
  ),
  winners as (
    select *
    from ranked
    where rn = 1
      and ownership_id is not null
      and (expires_at is null or expires_at > now())
      and is_active and is_equippable and is_equip_enabled
      and equip_slot = 'avatar_frame'
  ),
  log_conflicts as (
    insert into public.backpack_v2_migration_issues
      (batch, source_table, source_row_id, source_user_id, issue_type, detail)
    select v_batch, r.claim_source, null, r.user_id, 'equip_conflict_resolved',
      jsonb_build_object('overridden_code', r.resolved_code, 'winning_code', w.resolved_code, 'overridden_priority', r.priority)
    from ranked r
    join winners w on w.user_id = r.user_id
    where r.rn > 1 and r.resolved_code is distinct from w.resolved_code
    on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
      do nothing
    returning 1
  ),
  equip_ins as (
    insert into public.user_equipped_items (user_id, slot_type, user_backpack_item_id, equipped_at)
    select user_id, 'avatar_frame', ownership_id, now()
    from winners
    on conflict (user_id, slot_type) do update
      set user_backpack_item_id = excluded.user_backpack_item_id,
          equipped_at = excluded.equipped_at
      where public.user_equipped_items.user_backpack_item_id is distinct from excluded.user_backpack_item_id
    returning user_id
  )
  select count(*) into v_equip_count from equip_ins;

  -- ── Unresolved/deferred manifest records: logged, never migrated ───────

  -- R3 — badges: target catalog code naming is an open design question.
  insert into public.backpack_v2_migration_issues
    (batch, source_table, source_row_id, source_user_id, issue_type, detail)
  select v_batch, 'user_badges', ub.id::text, ub.user_id, 'unresolved_mapping',
    jsonb_build_object('manifest_record', 'R3_badges',
      'reason', 'target backpack_catalog_items.code naming for badges is undecided; not migrated')
  from public.user_badges ub
  on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
    do nothing;

  -- R5 — backpack_items rows whose item_type is not 'avatar_frame': real
  -- production value set was never enumerated (manifest R5, none confidence).
  insert into public.backpack_v2_migration_issues
    (batch, source_table, source_row_id, source_user_id, issue_type, detail)
  select v_batch, 'backpack_items', bi.id::text, bi.user_id, 'unresolved_mapping',
    jsonb_build_object('manifest_record', 'R5_backpack_items_other_item_types', 'item_type', bi.item_type,
      'reason', 'non-avatar_frame item_type values must be enumerated against production before mapping')
  from public.backpack_items bi
  where bi.item_type <> 'avatar_frame'
  on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
    do nothing;

  -- R9 — vip_plans.frame_key: a tier-derived grant, distinct question from
  -- R1/R2/R4 direct ownership, never addressed by the discovery report's own
  -- synthesis section. Logged per active subscription, not migrated.
  insert into public.backpack_v2_migration_issues
    (batch, source_table, source_row_id, source_user_id, issue_type, detail)
  select v_batch, 'user_vip_subscriptions', uvs.id::text, uvs.user_id, 'unresolved_mapping',
    jsonb_build_object('manifest_record', 'R9_vip_plan_frame_key', 'frame_key', vp.frame_key,
      'reason', 'whether a VIP tier frame_key is ownership distinct from any separately-held frame is an unresolved product decision')
  from public.user_vip_subscriptions uvs
  join public.vip_plans vp on vp.id = uvs.vip_plan_id
  where uvs.is_active = true and uvs.ends_at > now() and vp.frame_key is not null
  on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
    do nothing;

  -- R6-R8, R10 — VIP-tier synthesis candidates (entry_effect, mic_effect,
  -- profile_frame, badge-by-tier): no per-user ownership row exists anywhere
  -- for these; only tier-level attributes. One category-level log entry
  -- each, not one per user, since there is no source row to iterate.
  insert into public.backpack_v2_migration_issues
    (batch, source_table, source_row_id, source_user_id, issue_type, detail)
  values
    (v_batch, 'vip_levels', null, null, 'deferred_synthesis',
      jsonb_build_object('manifest_record', 'R6_vip_tier_entry_effect',
        'reason', 'synthesized from tier membership, not an ownership row; catalog code/equipped-state design undecided')),
    (v_batch, 'vip_levels', null, null, 'deferred_synthesis',
      jsonb_build_object('manifest_record', 'R7_vip_tier_mic_effect',
        'reason', 'mic_frame_url is unpopulated in every observed row; no source value to migrate or synthesize from')),
    (v_batch, 'vip_levels', null, null, 'deferred_synthesis',
      jsonb_build_object('manifest_record', 'R8_vip_tier_profile_frame',
        'reason', 'profile_frame_url is unpopulated in every observed row; no source value to migrate or synthesize from')),
    (v_batch, 'vip_levels', null, null, 'deferred_synthesis',
      jsonb_build_object('manifest_record', 'R10_vip_tier_badge',
        'reason', 'no key-shaped identifier exists for a per-tier badge; badge_label is a display string, not an identity'))
  on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
    do nothing;

  -- R13 — store_items: table does not exist in tracked migration history;
  -- never queried directly (would error against a clean local reset).
  insert into public.backpack_v2_migration_issues
    (batch, source_table, source_row_id, source_user_id, issue_type, detail)
  values
    (v_batch, 'store_items', null, null, 'blocked_source_unavailable',
      jsonb_build_object('manifest_record', 'R13_store_items',
        'reason', 'table has no tracked migration and does not exist in a clean reset; production shape unverified'))
  on conflict (batch, source_table, coalesce(source_row_id, ''), coalesce(source_user_id::text, ''), issue_type)
    do nothing;

  select count(*) into v_issues_count
  from public.backpack_v2_migration_issues where batch = v_batch;

  return jsonb_build_object(
    'batch', v_batch,
    'catalog_upserted', v_catalog_count,
    'r2_frame_v2_ownership_inserted', v_r2_inserted,
    'r1_legacy_avatar_frames_ownership_inserted', v_r1_inserted,
    'r4_backpack_items_ownership_inserted', v_r4_inserted,
    'equipped_slots_set', v_equip_count,
    'issues_logged_total', v_issues_count
  );
end;
$$;

-- No grant to authenticated/anon, unlike every other Backpack V2 RPC: this
-- function is service-role/superuser-only until an explicitly-approved
-- future milestone wires a reviewed admin entry point to it, if ever.
revoke all on function public.backpack_v2_run_m3_backfill() from public;

-- ── Rollback inventory (manual, requires explicit approval) ────────────────
-- This migration is additive and inert until public.backpack_v2_run_m3_backfill()
-- is actually called. If it was never called, rollback is a pure drop:
--   drop function public.backpack_v2_run_m3_backfill();
--   drop table public.backpack_v2_migration_issues;
-- If it WAS called against real data, do not blindly delete the rows it
-- created — user_backpack_items rows it inserted are indistinguishable from
-- any other ownership row except via source_type = 'legacy_migration' and
-- source_reference LIKE 'user_frames:%' / 'user_avatar_frames:%' /
-- 'backpack_items:%'. A reviewed, batch-scoped rollback script (delete
-- user_equipped_items rows pointing at those user_backpack_items rows, then
-- the user_backpack_items rows themselves, by source_reference prefix) would
-- need to be written and approved separately — not included here by design,
-- per "add rollback guidance, but do not create destructive rollback SQL".
-- No legacy table is ever modified by this migration, so no legacy-table
-- rollback is required under any circumstance.
