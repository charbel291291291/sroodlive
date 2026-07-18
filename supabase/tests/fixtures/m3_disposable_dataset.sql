-- M3 Step 3+4: disposable, real-shaped dataset + backfill execution + metrics.
-- (20261121000000_backpack_v2_m3_legacy_backfill.sql)
--
-- This is NOT a pass/fail contract test file (though it does assert the
-- structural invariants that must hold no matter what data is fed in). Its
-- purpose is to exercise public.backpack_v2_run_m3_backfill() against a
-- broader, more realistic mix of legacy shapes than the 12-scenario contract
-- test or the 13-scenario equip tie-break matrix, and to print the
-- before/after metrics the M3 dry-run report requires.
--
-- Disposable-only: everything below runs inside a single transaction against
-- the LOCAL docker Supabase instance and ends in ROLLBACK. Nothing is
-- committed; no production/staging connection is used or possible from this
-- file. Namespace: users bc050000-...0001 through ...0015, catalog/frame
-- codes prefixed 'ds_', chosen to never collide with the bc030000/m3t_
-- (migration contract test) or bc040000/tb_ (equip tie-break matrix)
-- namespaces, so all three files remain safe to run in the same session.
--
-- Dataset categories (Step 3 checklist) -> dedicated user:
--   DS01  existing Backpack V2 user (native purchase, zero legacy footprint)
--   DS02  user with no Backpack V2 records and no legacy records at all
--   DS03  VIP-tier cosmetic (R9: user_vip_subscriptions -> vip_plans.frame_key)
--   DS04  duplicate historical grant (same resolved code via R2 AND R1)
--   DS05  expired cosmetic, never equipped (R1, expires_at in the past)
--   DS06  missing catalog mapping (R1 frame_key with no resolution at all)
--   DS07  invalid legacy foreign key (R4 backpack_items.user_id not in auth.users)
--   DS08  conflicting equipped cosmetics (R2 vs R4, fresh instance)
--   DS09  multiple legacy source systems (R1 + R2 + R4 all owned; only R2 equipped)
--   DS10  previously-migrated + incrementally-added legacy source (see run 2)
--   DS11  admin-granted item (frame_catalog.unlock_type = 'admin_grant')
--   DS12  purchased item (frame_catalog.unlock_type = 'purchase')
--   DS13  free/promotional item (frame_catalog.unlock_type = 'event')
--   DS14  revoked legacy ownership (R2 user_frames.revoked_at set)
--   DS15  badges (R3: user_badges, always unresolved/unmigrated)
--   DS16  non-avatar_frame backpack_items row (R5: item_type <> 'avatar_frame',
--         e.g. a 'name_color' item — always unresolved/unmigrated)
--
-- Categories with NO per-user fixture, by design:
--   store_items-sourced grants / "legacy source unavailable" (R13) — the
--   store_items table has no tracked migration and does not exist in a clean
--   `supabase db reset`; the migration never queries it and instead emits one
--   unconditional category-level log row. No real row can be constructed for
--   it in this schema. See Step 5 finding in the dry-run report.
--   R6-R8, R10 (VIP-tier synthesis candidates) are also unconditional,
--   category-level, one-row-per-batch log entries independent of any user
--   data — verified below by presence, not by a dedicated fixture.
\set ON_ERROR_STOP on
begin;

-- ── Fixtures: catalog (frame_catalog + matching avatar_frames FK rows) ─────

insert into public.frame_catalog (code, name, category, asset_type, rarity, is_active, sort_order, unlock_type)
values
  ('ds_dup_04',           'DS Dup Grant 04',       'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_expired_05',       'DS Expired 05',         'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_orphan_fk_07',     'DS Orphan FK 07',       'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_conflict_r2_08',   'DS Conflict R2 08',     'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_conflict_r4_08',   'DS Conflict R4 08',     'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_multi_r1_09',      'DS Multi R1 09',        'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_multi_r2_09',      'DS Multi R2 09',        'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_multi_r4_09',      'DS Multi R4 09',        'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_incr_r1_10',       'DS Incremental R1 10',  'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_incr_r2_10',       'DS Incremental R2 10',  'custom', 'painter', 'common', true, 0, 'free'),
  ('ds_admin_11',         'DS Admin Grant 11',     'custom', 'painter', 'common', true, 0, 'admin_grant'),
  ('ds_purchased_12',     'DS Purchased 12',       'custom', 'painter', 'common', true, 0, 'purchase'),
  ('ds_promo_13',         'DS Promo 13',           'custom', 'painter', 'common', true, 0, 'event'),
  ('ds_revoked_14',       'DS Revoked 14',         'custom', 'painter', 'common', true, 0, 'free')
on conflict (code) do nothing;
-- Deliberately no frame_catalog row for a "ds_missing_06" code — DS06's
-- fixture below references a frame_key that resolves nowhere, on purpose.

insert into public.avatar_frames (frame_key, name, category, is_active)
values
  ('ds_dup_04',           'DS Dup Grant 04 (legacy FK)',       'normal', true),
  ('ds_expired_05',       'DS Expired 05 (legacy FK)',         'normal', true),
  ('ds_conflict_r2_08',   'DS Conflict R2 08 (legacy FK)',     'normal', true),
  ('ds_multi_r1_09',      'DS Multi R1 09 (legacy FK)',        'normal', true),
  ('ds_multi_r2_09',      'DS Multi R2 09 (legacy FK)',        'normal', true),
  ('ds_incr_r1_10',       'DS Incremental R1 10 (legacy FK)',  'normal', true),
  ('ds_incr_r2_10',       'DS Incremental R2 10 (legacy FK)',  'normal', true),
  ('ds_admin_11',         'DS Admin Grant 11 (legacy FK)',     'normal', true),
  ('ds_purchased_12',     'DS Purchased 12 (legacy FK)',       'normal', true)
on conflict (frame_key) do nothing;
-- No avatar_frames row for ds_orphan_fk_07 / ds_conflict_r4_08 / ds_multi_r4_09
-- / ds_promo_13 (R4-only claims: backpack_items has no FK to avatar_frames)
-- or ds_revoked_14 (R2 ownership that is never equipped, so
-- profiles.selected_avatar_frame_key -> avatar_frames.frame_key is never hit).

-- DS01: a genuine, non-legacy Backpack V2 catalog item (never sourced from
-- frame_catalog), proving an already-onboarded V2 user with zero legacy
-- footprint is left completely untouched by the backfill.
insert into public.backpack_catalog_items
  (code, name, item_type, equip_slot, rarity, is_active, is_equippable, is_equip_enabled)
values
  ('ds_v2_native_01', 'DS V2 Native 01', 'avatar_frame', 'avatar_frame', 'common', true, true, true)
on conflict (code) do nothing;

-- ── Fixtures: users ──────────────────────────────────────────────────────

insert into auth.users(id,instance_id,aud,role,email) values
 ('bc050000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u1@example.com'),
 ('bc050000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u2@example.com'),
 ('bc050000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u3@example.com'),
 ('bc050000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u4@example.com'),
 ('bc050000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u5@example.com'),
 ('bc050000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u6@example.com'),
 ('bc050000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u8@example.com'),
 ('bc050000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u9@example.com'),
 ('bc050000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u10@example.com'),
 ('bc050000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u11@example.com'),
 ('bc050000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u12@example.com'),
 ('bc050000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u13@example.com'),
 ('bc050000-0000-0000-0000-000000000014','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u14@example.com'),
 ('bc050000-0000-0000-0000-000000000015','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u15@example.com'),
 ('bc050000-0000-0000-0000-000000000016','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-u16@example.com')
on conflict(id) do nothing;
-- Note: DS07 (bc050000-...0007) is deliberately NOT inserted here — see below.

insert into public.profiles(id) values
 ('bc050000-0000-0000-0000-000000000001'),('bc050000-0000-0000-0000-000000000002'),
 ('bc050000-0000-0000-0000-000000000003'),('bc050000-0000-0000-0000-000000000004'),
 ('bc050000-0000-0000-0000-000000000005'),('bc050000-0000-0000-0000-000000000006'),
 ('bc050000-0000-0000-0000-000000000008'),('bc050000-0000-0000-0000-000000000009'),
 ('bc050000-0000-0000-0000-000000000010'),('bc050000-0000-0000-0000-000000000011'),
 ('bc050000-0000-0000-0000-000000000012'),('bc050000-0000-0000-0000-000000000013'),
 ('bc050000-0000-0000-0000-000000000014'),('bc050000-0000-0000-0000-000000000015'),
 ('bc050000-0000-0000-0000-000000000016')
on conflict(id) do nothing;

-- ── DS01: existing Backpack V2 user, zero legacy footprint ───────────────
insert into public.user_backpack_items (user_id, item_id, source_type, source_reference)
select 'bc050000-0000-0000-0000-000000000001', bci.id, 'purchase', 'order:ds01'
from public.backpack_catalog_items bci where bci.code = 'ds_v2_native_01'
returning id as ds01_native_ubi_id \gset
insert into public.user_equipped_items (user_id, slot_type, user_backpack_item_id)
values ('bc050000-0000-0000-0000-000000000001', 'avatar_frame', :'ds01_native_ubi_id');
create temp table ds01_ids as select :'ds01_native_ubi_id'::uuid as native_ubi_id;

-- ── DS02: no Backpack V2 records, no legacy records at all ───────────────
-- (nothing to insert; profile row alone is the entire fixture)

-- ── DS03: VIP-tier cosmetic (R9) ──────────────────────────────────────────
-- vip_plans.level is CHECK(1-9) AND unique, and every level 1-9 is already
-- seeded by 20260606073000_full_social_economy_schema.sql (level 1 has a
-- null frame_key; levels 2-9 already carry real seeded frame_key values
-- such as 'custom_luxury_gold'). No new vip_plans row can be inserted
-- without colliding with that seed, so this fixture attaches to the
-- existing level-2 plan (frame_key = 'custom_luxury_gold') instead —
-- arguably more real-shaped than a synthetic plan would be.
select id as ds03_plan_id, frame_key as ds03_plan_frame_key
from public.vip_plans where level = 2 \gset
create temp table ds03_frame_key_tbl as select :'ds03_plan_frame_key'::text as ds03_plan_frame_key;
insert into public.user_vip_subscriptions (user_id, vip_plan_id, ends_at, is_active)
values ('bc050000-0000-0000-0000-000000000003', :'ds03_plan_id', now() + interval '20 days', true);

-- ── DS04: duplicate historical grant (same code via R2 AND R1) ───────────
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc050000-0000-0000-0000-000000000004', fc.id, null, null
from public.frame_catalog fc where fc.code = 'ds_dup_04';
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc050000-0000-0000-0000-000000000004', af.id, 'ds_dup_04', false, null
from public.avatar_frames af where af.frame_key = 'ds_dup_04';

-- ── DS05: expired cosmetic, never equipped ────────────────────────────────
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc050000-0000-0000-0000-000000000005', af.id, 'ds_expired_05', false, now() - interval '30 days'
from public.avatar_frames af where af.frame_key = 'ds_expired_05';

-- ── DS06: missing catalog mapping (R1, unresolvable frame_key) ───────────
insert into public.avatar_frames (frame_key, name, category, is_active)
values ('ds_missing_06', 'DS Missing 06 (legacy FK only, no catalog match)', 'normal', true)
on conflict (frame_key) do nothing;
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc050000-0000-0000-0000-000000000006', af.id, 'ds_missing_06', false, null
from public.avatar_frames af where af.frame_key = 'ds_missing_06';

-- ── DS07: invalid legacy FK (R4 user_id not in auth.users) ───────────────
-- backpack_items.user_id IS FK-enforced; this shape can only exist via an
-- orphaning bypass (see the M3 migration contract test's identical U8
-- fixture for the full rationale). session_replication_role is scoped to
-- this single insert only.
set local session_replication_role = replica;
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values (
  'bc050000-0000-0000-0000-000000000007', gen_random_uuid(), 'avatar_frame', false,
  jsonb_build_object('frame_key', 'ds_orphan_fk_07')
);
set local session_replication_role = default;

-- ── DS08: conflicting equipped cosmetics (R2 vs R4, R2 must win) ─────────
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc050000-0000-0000-0000-000000000008', fc.id, null, null
from public.frame_catalog fc where fc.code = 'ds_conflict_r2_08';
update public.profiles set selected_avatar_frame_key = 'ds_conflict_r2_08'
where id = 'bc050000-0000-0000-0000-000000000008';
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values ('bc050000-0000-0000-0000-000000000008', gen_random_uuid(), 'avatar_frame', true,
  jsonb_build_object('frame_key', 'ds_conflict_r4_08'));

-- ── DS09: multiple legacy source systems (R1+R2+R4 owned; only R2 equipped) ─
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc050000-0000-0000-0000-000000000009', fc.id, null, null
from public.frame_catalog fc where fc.code = 'ds_multi_r2_09';
update public.profiles set selected_avatar_frame_key = 'ds_multi_r2_09'
where id = 'bc050000-0000-0000-0000-000000000009';
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc050000-0000-0000-0000-000000000009', af.id, 'ds_multi_r1_09', false, null
from public.avatar_frames af where af.frame_key = 'ds_multi_r1_09';
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values ('bc050000-0000-0000-0000-000000000009', gen_random_uuid(), 'avatar_frame', false,
  jsonb_build_object('frame_key', 'ds_multi_r4_09'));

-- ── DS10: previously-migrated user + a NEW legacy source added before run 2 ─
-- Realistic cutover shape: a user migrated in an earlier batch run, then
-- acquires an additional legacy record before the backfill runs again.
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc050000-0000-0000-0000-000000000010', af.id, 'ds_incr_r1_10', false, null
from public.avatar_frames af where af.frame_key = 'ds_incr_r1_10';
-- ds_incr_r2_10 (the run-2 addition) is inserted further below, immediately
-- before Run 2, not here.

-- ── DS11: admin-granted item (unlock_type = admin_grant) ─────────────────
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc050000-0000-0000-0000-000000000011', af.id, 'ds_admin_11', true, null
from public.avatar_frames af where af.frame_key = 'ds_admin_11';

-- ── DS12: purchased item (unlock_type = purchase) ─────────────────────────
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc050000-0000-0000-0000-000000000012', fc.id, null, null
from public.frame_catalog fc where fc.code = 'ds_purchased_12';
update public.profiles set selected_avatar_frame_key = 'ds_purchased_12'
where id = 'bc050000-0000-0000-0000-000000000012';

-- ── DS13: free/promotional item (unlock_type = event) ─────────────────────
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values ('bc050000-0000-0000-0000-000000000013', gen_random_uuid(), 'avatar_frame', true,
  jsonb_build_object('frame_key', 'ds_promo_13'));

-- ── DS14: revoked legacy ownership (R2, never merged) ─────────────────────
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc050000-0000-0000-0000-000000000014', fc.id, null, now() - interval '5 days'
from public.frame_catalog fc where fc.code = 'ds_revoked_14';

-- ── DS15: badges (R3, always unresolved/unmigrated) ───────────────────────
-- NOTE (Step 5/6 finding): badges.required_vip_level DEFAULTs to 0, but its
-- own CHECK constraint (badges_required_vip_level_check) only allows NULL or
-- 1-9 — the column's default violates its own constraint, so every insert
-- must explicitly override it. This is a pre-existing schema bug, unrelated
-- to Backpack V2, surfaced incidentally by this fixture.
insert into public.badges (badge_key, name, category, rarity, required_vip_level)
values ('ds_badge_15', 'DS Badge 15', 'achievement', 'common', null)
on conflict (badge_key) do nothing
returning id as ds15_badge_id \gset
insert into public.user_badges (user_id, badge_id, badge_key, is_equipped, source)
select 'bc050000-0000-0000-0000-000000000015', b.id, b.badge_key, true, 'admin_grant'
from public.badges b where b.badge_key = 'ds_badge_15';

-- ── DS16: non-avatar_frame backpack_items row (R5, always unresolved) ─────
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values ('bc050000-0000-0000-0000-000000000016', gen_random_uuid(), 'name_color', false,
  jsonb_build_object('color_hex', '#ff00aa'));

-- ── Pre-run snapshot: prove no legacy table is ever modified ─────────────

create temp table ds_legacy_snapshot_before as
select
  (select count(*) from public.user_frames where user_id::text like 'bc050000-%') as user_frames_count,
  (select count(*) from public.user_avatar_frames where user_id::text like 'bc050000-%') as user_avatar_frames_count,
  (select count(*) from public.backpack_items where user_id::text like 'bc050000-%') as backpack_items_count,
  (select count(*) from public.user_vip_subscriptions where user_id::text like 'bc050000-%') as vip_subs_count,
  (select count(*) from public.user_badges where user_id::text like 'bc050000-%') as user_badges_count,
  (select md5(string_agg(id::text || revoked_at::text || expires_at::text, ',' order by id))
     from public.user_frames where user_id::text like 'bc050000-%') as user_frames_hash,
  (select md5(string_agg(id::text || is_equipped::text || expires_at::text, ',' order by id))
     from public.user_avatar_frames where user_id::text like 'bc050000-%') as user_avatar_frames_hash,
  (select md5(string_agg(id::text || equipped::text || metadata::text, ',' order by id))
     from public.backpack_items where user_id::text like 'bc050000-%') as backpack_items_hash;

-- ══════════════════════════════════════════════════════════════════════════
-- RUN 1
-- ══════════════════════════════════════════════════════════════════════════

create temp table ds_run1_result as
select public.backpack_v2_run_m3_backfill() as result;

select 'RUN 1 RESULT' as label, result from ds_run1_result;

-- Metrics: ownership / equip / issues breakdown scoped to this dataset.
select 'RUN1 ownership_inserted_by_source' as label, ubi.source_reference ~ '^[a-z_]+' as ok,
  split_part(ubi.source_reference, ':', 1) as source_table, count(*)
from public.user_backpack_items ubi
where ubi.user_id::text like 'bc050000-%' and ubi.source_type = 'legacy_migration'
group by 2, 3 order by 3;

select 'RUN1 equipped_slots_by_user' as label, uei.user_id, uei.slot_type, bci.code, ubi.source_type
from public.user_equipped_items uei
join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
join public.backpack_catalog_items bci on bci.id = ubi.item_id
where uei.user_id::text like 'bc050000-%'
order by uei.user_id;

select 'RUN1 issues_by_type_and_table' as label, source_table, issue_type, count(*)
from public.backpack_v2_migration_issues
where batch = 'm3_legacy_backfill_v1'
  and (source_user_id::text like 'bc050000-%' or source_user_id is null)
group by 2, 3 order by 2, 3;

select 'RUN1 category_level_issues_R6_R7_R8_R10_R13' as label, source_table, issue_type,
  detail ->> 'manifest_record' as manifest_record
from public.backpack_v2_migration_issues
where batch = 'm3_legacy_backfill_v1' and source_user_id is null
  and issue_type in ('deferred_synthesis', 'blocked_source_unavailable')
order by 1, detail ->> 'manifest_record';

-- ── Structural assertions (must hold regardless of exact counts) ─────────

do $$
declare v_count int;
begin
  -- DS01: existing V2 user must be completely untouched.
  select count(*) into v_count from public.user_backpack_items
    where user_id = 'bc050000-0000-0000-0000-000000000001';
  if v_count <> 1 then raise exception 'DS01: expected exactly 1 ownership row (the native purchase), got %', v_count; end if;
  if (select user_backpack_item_id from public.user_equipped_items
        where user_id = 'bc050000-0000-0000-0000-000000000001' and slot_type = 'avatar_frame')
     is distinct from (select native_ubi_id from ds01_ids) then
    raise exception 'DS01: native V2 equip identity must be untouched by the backfill';
  end if;

  -- DS02: zero footprint -> zero rows, zero issues.
  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000002')
  then raise exception 'DS02: user with no legacy data must get no ownership rows'; end if;
  if exists (select 1 from public.backpack_v2_migration_issues where source_user_id = 'bc050000-0000-0000-0000-000000000002')
  then raise exception 'DS02: user with no legacy data must get no issue log rows'; end if;

  -- DS03: R9 must be logged as unresolved_mapping, never migrated as ownership.
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_vip_subscriptions' and source_user_id = 'bc050000-0000-0000-0000-000000000003'
      and issue_type = 'unresolved_mapping'
      and detail ->> 'frame_key' = (select ds03_plan_frame_key from ds03_frame_key_tbl)
  ) then raise exception 'DS03: VIP-tier frame_key grant must be logged as unresolved_mapping (R9)'; end if;
  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000003')
  then raise exception 'DS03: R9 must never produce a real ownership row'; end if;

  -- DS04: duplicate grant -> exactly one active ownership row for the resolved
  -- code, the losing source logged as duplicate_superseded.
  select count(*) into v_count from public.user_backpack_items ubi
    join public.backpack_catalog_items bci on bci.id = ubi.item_id
    where ubi.user_id = 'bc050000-0000-0000-0000-000000000004' and bci.code = 'ds_dup_04' and ubi.is_revoked = false;
  if v_count <> 1 then raise exception 'DS04: expected exactly 1 active ownership row for the duplicated code, got %', v_count; end if;
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_avatar_frames' and source_user_id = 'bc050000-0000-0000-0000-000000000004'
      and issue_type = 'duplicate_superseded'
  ) then raise exception 'DS04: the losing (R1) duplicate grant must be logged as duplicate_superseded'; end if;

  -- DS05: expired ownership preserved, never equipped, no conflict log (it
  -- was never marked equipped at the source, so it never becomes a claim).
  if not exists (
    select 1 from public.user_backpack_items ubi
    join public.backpack_catalog_items bci on bci.id = ubi.item_id
    where ubi.user_id = 'bc050000-0000-0000-0000-000000000005' and bci.code = 'ds_expired_05'
      and ubi.expires_at < now()
  ) then raise exception 'DS05: expired ownership row must be created with expiry preserved'; end if;
  if exists (select 1 from public.user_equipped_items where user_id = 'bc050000-0000-0000-0000-000000000005')
  then raise exception 'DS05: an expired, never-equipped-at-source row must never be equipped'; end if;

  -- DS06: missing catalog mapping -> logged, no ownership row.
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_avatar_frames' and source_user_id = 'bc050000-0000-0000-0000-000000000006'
      and issue_type = 'missing_catalog_mapping'
  ) then raise exception 'DS06: unresolvable frame_key must be logged as missing_catalog_mapping'; end if;
  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000006')
  then raise exception 'DS06: unresolvable frame_key must never produce an ownership row'; end if;

  -- DS07: invalid FK -> logged as missing_user_reference, no crash, no row.
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'backpack_items' and source_user_id = 'bc050000-0000-0000-0000-000000000007'
      and issue_type = 'missing_user_reference'
  ) then raise exception 'DS07: orphaned backpack_items.user_id must be logged as missing_user_reference'; end if;
  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000007')
  then raise exception 'DS07: an orphaned legacy row must never produce an ownership row'; end if;

  -- DS08: R2 must win over R4.
  if (select bci.code from public.user_equipped_items uei
        join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
        join public.backpack_catalog_items bci on bci.id = ubi.item_id
        where uei.user_id = 'bc050000-0000-0000-0000-000000000008' and uei.slot_type = 'avatar_frame')
     <> 'ds_conflict_r2_08'
  then raise exception 'DS08: R2 must win the equip slot over R4'; end if;

  -- DS09: three ownership rows, exactly one equipped (R2's).
  select count(*) into v_count from public.user_backpack_items
    where user_id = 'bc050000-0000-0000-0000-000000000009' and source_type = 'legacy_migration';
  if v_count <> 3 then raise exception 'DS09: expected 3 ownership rows from 3 legacy sources, got %', v_count; end if;
  if (select bci.code from public.user_equipped_items uei
        join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
        join public.backpack_catalog_items bci on bci.id = ubi.item_id
        where uei.user_id = 'bc050000-0000-0000-0000-000000000009' and uei.slot_type = 'avatar_frame')
     <> 'ds_multi_r2_09'
  then raise exception 'DS09: R2 must be the equipped winner'; end if;

  -- DS10 after run 1: only the R1 row exists yet (run-2 addition not inserted yet).
  select count(*) into v_count from public.user_backpack_items
    where user_id = 'bc050000-0000-0000-0000-000000000010' and source_type = 'legacy_migration';
  if v_count <> 1 then raise exception 'DS10 (run1): expected exactly 1 ownership row before the run-2 addition, got %', v_count; end if;

  -- DS11/DS12/DS13: admin_grant / purchase / event unlock_type items migrate
  -- and equip correctly; catalog metadata carries the original unlock_type
  -- through even though source_type is generically 'legacy_migration'.
  if not exists (
    select 1 from public.user_equipped_items uei
    join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
    join public.backpack_catalog_items bci on bci.id = ubi.item_id
    where uei.user_id = 'bc050000-0000-0000-0000-000000000011' and bci.code = 'ds_admin_11'
      and bci.metadata ->> 'unlock_type' = 'admin_grant'
  ) then raise exception 'DS11: admin-granted item must migrate, equip, and preserve unlock_type in catalog metadata'; end if;

  if not exists (
    select 1 from public.user_equipped_items uei
    join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
    join public.backpack_catalog_items bci on bci.id = ubi.item_id
    where uei.user_id = 'bc050000-0000-0000-0000-000000000012' and bci.code = 'ds_purchased_12'
      and bci.metadata ->> 'unlock_type' = 'purchase'
  ) then raise exception 'DS12: purchased item must migrate, equip, and preserve unlock_type in catalog metadata'; end if;

  if not exists (
    select 1 from public.user_equipped_items uei
    join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
    join public.backpack_catalog_items bci on bci.id = ubi.item_id
    where uei.user_id = 'bc050000-0000-0000-0000-000000000013' and bci.code = 'ds_promo_13'
      and bci.metadata ->> 'unlock_type' = 'event'
  ) then raise exception 'DS13: promotional item must migrate, equip, and preserve unlock_type in catalog metadata'; end if;

  -- DS14: revoked ownership never merged, logged as revoked_source.
  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000014')
  then raise exception 'DS14: revoked legacy ownership must never be merged into active ownership'; end if;
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_frames' and source_user_id = 'bc050000-0000-0000-0000-000000000014'
      and issue_type = 'revoked_source'
  ) then raise exception 'DS14: revoked legacy ownership must be logged as revoked_source'; end if;

  -- DS15: badges (R3) always unresolved, never migrated.
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_badges' and source_user_id = 'bc050000-0000-0000-0000-000000000015'
      and issue_type = 'unresolved_mapping'
  ) then raise exception 'DS15: badge ownership must be logged as unresolved_mapping (R3)'; end if;
  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000015')
  then raise exception 'DS15: badge ownership must never produce a Backpack V2 ownership row'; end if;

  -- DS16: non-avatar_frame backpack_items row (R5) always unresolved, never migrated.
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'backpack_items' and source_user_id = 'bc050000-0000-0000-0000-000000000016'
      and issue_type = 'unresolved_mapping' and detail ->> 'item_type' = 'name_color'
  ) then raise exception 'DS16: non-avatar_frame backpack_items row must be logged as unresolved_mapping (R5)'; end if;
  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000016')
  then raise exception 'DS16: non-avatar_frame backpack_items row must never produce a Backpack V2 ownership row'; end if;

  -- Category-level deferred/blocked sources (R6-R8, R10, R13) fire exactly
  -- once per batch, independent of any fixture in this file.
  if (select count(*) from public.backpack_v2_migration_issues
        where batch = 'm3_legacy_backfill_v1' and issue_type = 'deferred_synthesis'
          and source_table = 'vip_levels' and source_user_id is null) <> 4
  then raise exception 'R6-R8/R10: expected exactly 4 category-level deferred_synthesis rows for vip_levels'; end if;
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where batch = 'm3_legacy_backfill_v1' and issue_type = 'blocked_source_unavailable'
      and source_table = 'store_items' and source_user_id is null
  ) then raise exception 'R13: expected exactly one blocked_source_unavailable row for store_items'; end if;
end $$;

-- Legacy tables must never be modified — same hash/count check the migration
-- contract test uses, re-run here against this file's broader fixture set.
do $$
declare v_before record;
declare v_after record;
begin
  select * into v_before from ds_legacy_snapshot_before;
  select
    (select count(*) from public.user_frames where user_id::text like 'bc050000-%') as user_frames_count,
    (select count(*) from public.user_avatar_frames where user_id::text like 'bc050000-%') as user_avatar_frames_count,
    (select count(*) from public.backpack_items where user_id::text like 'bc050000-%') as backpack_items_count,
    (select count(*) from public.user_vip_subscriptions where user_id::text like 'bc050000-%') as vip_subs_count,
    (select count(*) from public.user_badges where user_id::text like 'bc050000-%') as user_badges_count,
    (select md5(string_agg(id::text || revoked_at::text || expires_at::text, ',' order by id))
       from public.user_frames where user_id::text like 'bc050000-%') as user_frames_hash,
    (select md5(string_agg(id::text || is_equipped::text || expires_at::text, ',' order by id))
       from public.user_avatar_frames where user_id::text like 'bc050000-%') as user_avatar_frames_hash,
    (select md5(string_agg(id::text || equipped::text || metadata::text, ',' order by id))
       from public.backpack_items where user_id::text like 'bc050000-%') as backpack_items_hash
  into v_after;

  if v_before is distinct from v_after then
    raise exception 'legacy source tables were modified by the backfill: before=% after=%',
      row_to_json(v_before), row_to_json(v_after);
  end if;
end $$;

-- ── Snapshot post-run-1 aggregate counts for the idempotency comparison ──

create temp table ds_post_run1 as
select
  (select count(*) from public.user_backpack_items where source_type = 'legacy_migration'
     and user_id::text like 'bc050000-%') as ownership_count,
  (select count(*) from public.user_equipped_items where user_id::text like 'bc050000-%') as equipped_count,
  (select count(*) from public.backpack_v2_migration_issues
     where batch = 'm3_legacy_backfill_v1'
       and (source_user_id::text like 'bc050000-%' or source_user_id is null)) as issues_count;

-- ══════════════════════════════════════════════════════════════════════════
-- Incremental legacy data arrives for DS10 (already-migrated user), THEN RUN 2
-- ══════════════════════════════════════════════════════════════════════════

insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc050000-0000-0000-0000-000000000010', fc.id, null, null
from public.frame_catalog fc where fc.code = 'ds_incr_r2_10';
update public.profiles set selected_avatar_frame_key = 'ds_incr_r2_10'
where id = 'bc050000-0000-0000-0000-000000000010';

create temp table ds_run2_result as
select public.backpack_v2_run_m3_backfill() as result;

select 'RUN 2 RESULT' as label, result from ds_run2_result;

select 'RUN2 issues_by_type_and_table' as label, source_table, issue_type, count(*)
from public.backpack_v2_migration_issues
where batch = 'm3_legacy_backfill_v1'
  and (source_user_id::text like 'bc050000-%' or source_user_id is null)
group by 2, 3 order by 2, 3;

-- ── DS10: the pre-existing R1 ownership row must be untouched by identity,
-- and the newly-added R2 row must be picked up and become the new equip
-- winner (R2 > R1) without disturbing anything else in the dataset. ───────
do $$
declare v_before record;
declare v_after record;
declare v_equipped_code text;
declare v_r1_count int;
begin
  select
    (select count(*) from public.user_backpack_items where source_type = 'legacy_migration'
       and user_id::text like 'bc050000-%') as ownership_count,
    (select count(*) from public.user_equipped_items where user_id::text like 'bc050000-%') as equipped_count,
    (select count(*) from public.backpack_v2_migration_issues
       where batch = 'm3_legacy_backfill_v1'
         and (source_user_id::text like 'bc050000-%' or source_user_id is null)) as issues_count
  into v_after;
  select * into v_before from ds_post_run1;

  -- Ownership grew by exactly 1 (DS10's new R2 row); nothing else changed.
  if v_after.ownership_count <> v_before.ownership_count + 1 then
    raise exception 'idempotency: expected ownership_count to grow by exactly 1 (DS10 R2 addition), % -> %',
      v_before.ownership_count, v_after.ownership_count;
  end if;
  -- Equipped count grew by exactly 1 (DS10 goes from unequipped to equipped).
  if v_after.equipped_count <> v_before.equipped_count + 1 then
    raise exception 'idempotency: expected equipped_count to grow by exactly 1 (DS10), % -> %',
      v_before.equipped_count, v_after.equipped_count;
  end if;
  -- Issues count must not have grown at all: DS10's R2 claim has no
  -- competitor (its R1 row was never equipped), so no new conflict log row
  -- is expected, and every other dataset row is a pure idempotent no-op.
  if v_after.issues_count <> v_before.issues_count then
    raise exception 'idempotency: issues_count changed on rerun (dedupe failed or unexpected new issue) % -> %',
      v_before.issues_count, v_after.issues_count;
  end if;

  select count(*) into v_r1_count from public.user_backpack_items ubi
    join public.backpack_catalog_items bci on bci.id = ubi.item_id
    where ubi.user_id = 'bc050000-0000-0000-0000-000000000010' and bci.code = 'ds_incr_r1_10';
  if v_r1_count <> 1 then raise exception 'DS10: the run-1 R1 ownership row must survive run 2 untouched'; end if;

  select bci.code into v_equipped_code
  from public.user_equipped_items uei
  join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where uei.user_id = 'bc050000-0000-0000-0000-000000000010' and uei.slot_type = 'avatar_frame';
  if v_equipped_code <> 'ds_incr_r2_10' then
    raise exception 'DS10: the newly-added R2 claim must win the equip slot on run 2, got %', v_equipped_code;
  end if;
end $$;

-- Re-verify every run-1 assertion still holds after run 2 (full-dataset
-- idempotency, not just DS10's incremental case): every prior winner/loser/
-- log outcome must be byte-identical.
do $$
begin
  if (select bci.code from public.user_equipped_items uei
        join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
        join public.backpack_catalog_items bci on bci.id = ubi.item_id
        where uei.user_id = 'bc050000-0000-0000-0000-000000000001' and uei.slot_type = 'avatar_frame')
     <> 'ds_v2_native_01'
  then raise exception 'DS01: native V2 equip must remain stable after run 2'; end if;

  if (select uei.user_backpack_item_id from public.user_equipped_items uei
        where uei.user_id = 'bc050000-0000-0000-0000-000000000001' and uei.slot_type = 'avatar_frame')
     is distinct from (select native_ubi_id from ds01_ids)
  then raise exception 'DS01: native V2 equip row identity must not change across reruns'; end if;

  if (select bci.code from public.user_equipped_items uei
        join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
        join public.backpack_catalog_items bci on bci.id = ubi.item_id
        where uei.user_id = 'bc050000-0000-0000-0000-000000000008' and uei.slot_type = 'avatar_frame')
     <> 'ds_conflict_r2_08'
  then raise exception 'DS08: R2 must still be the winner after run 2'; end if;

  if (select bci.code from public.user_equipped_items uei
        join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
        join public.backpack_catalog_items bci on bci.id = ubi.item_id
        where uei.user_id = 'bc050000-0000-0000-0000-000000000009' and uei.slot_type = 'avatar_frame')
     <> 'ds_multi_r2_09'
  then raise exception 'DS09: R2 must still be the winner after run 2'; end if;

  if exists (select 1 from public.user_backpack_items where user_id = 'bc050000-0000-0000-0000-000000000014')
  then raise exception 'DS14: revoked ownership must remain unmerged after run 2'; end if;
end $$;

-- ── Duplicate source-reference / orphan checks (Step 7 requirement) ──────

do $$
declare v_dupe_count int;
declare v_orphan_equip int;
declare v_orphan_ownership int;
begin
  select count(*) into v_dupe_count from (
    select source_reference, user_id, count(*)
    from public.user_backpack_items
    where user_id::text like 'bc050000-%' and source_type = 'legacy_migration'
    group by 1, 2 having count(*) > 1
  ) d;
  if v_dupe_count <> 0 then raise exception 'found % duplicate source_reference rows for one user', v_dupe_count; end if;

  select count(*) into v_orphan_equip
  from public.user_equipped_items uei
  where uei.user_id::text like 'bc050000-%'
    and not exists (select 1 from public.user_backpack_items ubi where ubi.id = uei.user_backpack_item_id);
  if v_orphan_equip <> 0 then raise exception 'found % orphaned user_equipped_items rows', v_orphan_equip; end if;

  select count(*) into v_orphan_ownership
  from public.user_backpack_items ubi
  where ubi.user_id::text like 'bc050000-%'
    and not exists (select 1 from public.backpack_catalog_items bci where bci.id = ubi.item_id);
  if v_orphan_ownership <> 0 then raise exception 'found % ownership rows pointing at a nonexistent catalog item', v_orphan_ownership; end if;
end $$;

-- ── Privilege check: anon/authenticated must not be able to call the backfill ──

do $$ begin
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims','{"sub":"bc050000-0000-0000-0000-000000000001","role":"authenticated"}',true);
    perform public.backpack_v2_run_m3_backfill();
    raise exception 'authenticated role must not be able to call the M3 backfill function';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end $$;

do $$ begin
  begin
    set local role anon;
    perform public.backpack_v2_run_m3_backfill();
    raise exception 'anon role must not be able to call the M3 backfill function';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end $$;

-- Disposable dataset: nothing here is ever committed.
rollback;
