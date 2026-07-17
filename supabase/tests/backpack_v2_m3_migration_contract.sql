-- Contract test: Backpack V2 M3 legacy backfill
-- (20261121000000_backpack_v2_m3_legacy_backfill.sql)
--
-- Covers all 12 scenarios requested for M3 Step 3: idempotent double-apply,
-- stable ownership count on retry, permanent ownership stays permanent,
-- temporary ownership preserves expiry exactly, an expired equipped legacy
-- item stays unequipped, a valid equipped legacy item migrates and equips
-- correctly, an unknown/unresolvable item is logged and left untouched,
-- duplicate legacy ownership across sources follows the documented R2>R4>R1
-- priority rule, revoked legacy ownership is never merged into active
-- ownership, a missing user reference is logged instead of crashing the
-- whole backfill, a missing catalog mapping is logged, and legacy data is
-- never modified by any of this.
--
-- The backfill function is never granted to authenticated/anon (by design —
-- see the migration), so this test calls it directly as the migrating role,
-- the same way it would be invoked from the SQL editor / service role.
\set ON_ERROR_STOP on
begin;

-- ── Fixtures: catalog (frame_catalog / avatar_frames / frame_legacy_map) ───

insert into public.frame_catalog (code, name, category, asset_type, rarity, is_active, sort_order)
values
  ('m3t_frame_a', 'M3 Test Frame A', 'custom', 'painter', 'common', true, 0),
  ('m3t_frame_b', 'M3 Test Frame B', 'custom', 'painter', 'common', true, 0),
  ('m3t_frame_c', 'M3 Test Frame C', 'custom', 'painter', 'common', true, 0),
  ('m3t_frame_d', 'M3 Test Frame D', 'custom', 'painter', 'common', true, 0),
  ('m3t_frame_e', 'M3 Test Frame E', 'custom', 'painter', 'common', true, 0),
  ('m3t_frame_f', 'M3 Test Frame F', 'custom', 'painter', 'common', true, 0)
on conflict (code) do nothing;

-- 'm3t_frame_a' is also inserted here (frame_key = the frame_catalog code
-- verbatim) solely so profiles.selected_avatar_frame_key's FK
-- (-> avatar_frames.frame_key) can be satisfied below; it plays no role in
-- R1 resolution for U1.
insert into public.avatar_frames (frame_key, name, category, is_active)
values
  ('m3t_frame_a', 'M3 Test Frame A (for FK)', 'normal', true),
  ('m3t_legacy_key_b', 'M3 Legacy Key B', 'normal', true),
  ('m3t_legacy_key_c', 'M3 Legacy Key C', 'normal', true),
  ('m3t_legacy_key_e', 'M3 Legacy Key E', 'normal', true),
  ('m3t_nonexistent_key', 'M3 Unresolvable', 'normal', true)
on conflict (frame_key) do nothing;

insert into public.frame_legacy_map (legacy_key, code)
values
  ('m3t_legacy_key_b', 'm3t_frame_b'),
  ('m3t_legacy_key_c', 'm3t_frame_c'),
  ('m3t_legacy_key_d', 'm3t_frame_d'),
  ('m3t_legacy_key_e', 'm3t_frame_e')
on conflict (legacy_key) do nothing;
-- Deliberately no frame_legacy_map / frame_catalog entry for
-- 'm3t_nonexistent_key' or 'm3t_nonexistent_key_2' — these must fail to
-- resolve (scenarios: unknown item logged, missing catalog mapping logged).

-- ── Fixtures: users ──────────────────────────────────────────────────────
-- U8 is deliberately NOT inserted into auth.users/profiles at all — it is
-- referenced only by a backpack_items.user_id row, inserted below with FK
-- enforcement bypassed for that one insert, to exercise the
-- missing-user-reference path (see the U8 fixture below for why).

insert into auth.users(id,instance_id,aud,role,email) values
 ('bc030000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u1@example.com'),
 ('bc030000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u2@example.com'),
 ('bc030000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u3@example.com'),
 ('bc030000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u4@example.com'),
 ('bc030000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u5@example.com'),
 ('bc030000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u6@example.com'),
 ('bc030000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u7@example.com'),
 ('bc030000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m3-u9@example.com')
on conflict(id) do nothing;

insert into public.profiles(id) values
 ('bc030000-0000-0000-0000-000000000001'),
 ('bc030000-0000-0000-0000-000000000002'),
 ('bc030000-0000-0000-0000-000000000003'),
 ('bc030000-0000-0000-0000-000000000004'),
 ('bc030000-0000-0000-0000-000000000005'),
 ('bc030000-0000-0000-0000-000000000006'),
 ('bc030000-0000-0000-0000-000000000007'),
 ('bc030000-0000-0000-0000-000000000009')
on conflict(id) do nothing;

-- U1 renders m3t_frame_a today (the only real "equipped" signal for Frame V2).
update public.profiles set selected_avatar_frame_key = 'm3t_frame_a'
where id = 'bc030000-0000-0000-0000-000000000001';

-- ── Fixtures: legacy ownership rows ─────────────────────────────────────

-- U1 — R2 permanent ownership, equipped via profiles.selected_avatar_frame_key.
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc030000-0000-0000-0000-000000000001', fc.id, null, null
from public.frame_catalog fc where fc.code = 'm3t_frame_a';

-- U2 — R1 temporary ownership, not equipped. Exact expiry must survive verbatim.
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc030000-0000-0000-0000-000000000002', af.id, 'm3t_legacy_key_b', false, timestamptz '2027-03-15 10:00:00+00'
from public.avatar_frames af where af.frame_key = 'm3t_legacy_key_b';

-- U3 — R1 expired ownership, marked equipped at the source. Must migrate as
-- ownership (expiry preserved) but must NOT produce an equipped row.
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc030000-0000-0000-0000-000000000003', af.id, 'm3t_legacy_key_c', true, now() - interval '1 day'
from public.avatar_frames af where af.frame_key = 'm3t_legacy_key_c';

-- U4 — R4 valid equipped ownership, no competing claim from another source.
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values (
  'bc030000-0000-0000-0000-000000000004', gen_random_uuid(), 'avatar_frame', true,
  jsonb_build_object('frame_key', 'm3t_legacy_key_d')
);

-- U5 — R1 unresolvable frame_key: must be logged, never migrated.
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc030000-0000-0000-0000-000000000005', af.id, 'm3t_nonexistent_key', false, null
from public.avatar_frames af where af.frame_key = 'm3t_nonexistent_key';

-- U6 — duplicate ownership of the same resolved item across R2 (higher
-- priority) and R1 (lower priority). Only R2's row should win as active.
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc030000-0000-0000-0000-000000000006', fc.id, null, null
from public.frame_catalog fc where fc.code = 'm3t_frame_e';
insert into public.user_avatar_frames (user_id, frame_id, frame_key, is_equipped, expires_at)
select 'bc030000-0000-0000-0000-000000000006', af.id, 'm3t_legacy_key_e', false, null
from public.avatar_frames af where af.frame_key = 'm3t_legacy_key_e';

-- U7 — revoked R2 ownership: must never be merged into active ownership.
insert into public.user_frames (user_id, frame_id, expires_at, revoked_at)
select 'bc030000-0000-0000-0000-000000000007', fc.id, null, now()
from public.frame_catalog fc where fc.code = 'm3t_frame_f';

-- U8 — NOT in auth.users at all. backpack_items.user_id IS FK-enforced
-- (backpack_items_user_id_fkey, added in
-- 20261113000000_backpack_items_baseline_and_frame_guard.sql), so this row
-- can only exist today via orphaning after the fact (e.g. a bulk load with
-- constraints disabled, or a future schema change) — not through normal
-- app writes. The backfill's defensive user-existence check is defense in
-- depth for that case; session_replication_role bypasses FK enforcement
-- here, for this one row only, purely to construct that orphaned shape in
-- the test fixture. It never touches the legacy migration/schema itself.
set local session_replication_role = replica;
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values (
  'bc030000-0000-0000-0000-000000000008', gen_random_uuid(), 'avatar_frame', false,
  jsonb_build_object('frame_key', 'm3t_legacy_key_d')
);
set local session_replication_role = default;

-- U9 — R4 unresolvable frame_key: second, independent missing-catalog-mapping case.
insert into public.backpack_items (user_id, item_id, item_type, equipped, metadata)
values (
  'bc030000-0000-0000-0000-000000000009', gen_random_uuid(), 'avatar_frame', false,
  jsonb_build_object('frame_key', 'm3t_nonexistent_key_2')
);

-- ── Snapshot legacy state before running the backfill ───────────────────

create temp table m3_legacy_snapshot_before as
select
  (select count(*) from public.user_frames) as user_frames_count,
  (select count(*) from public.user_avatar_frames) as user_avatar_frames_count,
  (select count(*) from public.backpack_items) as backpack_items_count,
  (select count(*) from public.avatar_frames) as avatar_frames_count,
  (select count(*) from public.frame_catalog) as frame_catalog_count,
  (select count(*) from public.frame_legacy_map) as frame_legacy_map_count,
  (select is_equipped from public.user_avatar_frames
     where user_id = 'bc030000-0000-0000-0000-000000000003') as u3_is_equipped,
  (select expires_at from public.user_avatar_frames
     where user_id = 'bc030000-0000-0000-0000-000000000003') as u3_expires_at;

-- ── Run 1 ─────────────────────────────────────────────────────────────────

-- psql's `:'var'` substitution never reaches inside dollar-quoted (`$$…$$`)
-- bodies (it's a client-side lexing rule, not something \gset can bypass),
-- so the RPC's jsonb result is carried into later do blocks via a temp
-- table instead of a psql variable.
create temp table m3_run1 as
select public.backpack_v2_run_m3_backfill() as result;

do $$
declare v_result jsonb;
begin
  select result into v_result from m3_run1;
  if v_result ->> 'r2_frame_v2_ownership_inserted' is distinct from '2' then
    raise exception 'expected 2 R2 ownership inserts (U1, U6 — U7 is revoked and excluded), got %', v_result;
  end if;
end $$;

-- Scenario: permanent ownership stays permanent (U1, expires_at null).
do $$
declare v_row public.user_backpack_items%rowtype;
begin
  select ubi.* into v_row
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.user_id = 'bc030000-0000-0000-0000-000000000001' and bci.code = 'm3t_frame_a';
  if not found then raise exception 'U1 ownership row missing'; end if;
  if v_row.expires_at is not null then raise exception 'U1 permanent ownership must stay permanent, got expires_at=%', v_row.expires_at; end if;
  if v_row.source_type <> 'legacy_migration' or v_row.source_reference !~ '^user_frames:' then
    raise exception 'U1 unexpected source shape: %', row_to_json(v_row);
  end if;
end $$;

-- Scenario: temporary ownership preserves expiry exactly (U2).
do $$
declare v_expires timestamptz;
begin
  select ubi.expires_at into v_expires
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.user_id = 'bc030000-0000-0000-0000-000000000002' and bci.code = 'm3t_frame_b';
  if v_expires is distinct from timestamptz '2027-03-15 10:00:00+00' then
    raise exception 'U2 expiry not preserved exactly: got %', v_expires;
  end if;
end $$;

-- Scenario: expired equipped legacy item migrates ownership but never equips (U3).
do $$
declare v_ownership_exists boolean;
declare v_equipped_exists boolean;
begin
  select exists (
    select 1 from public.user_backpack_items ubi
    join public.backpack_catalog_items bci on bci.id = ubi.item_id
    where ubi.user_id = 'bc030000-0000-0000-0000-000000000003' and bci.code = 'm3t_frame_c'
      and ubi.expires_at < now()
  ) into v_ownership_exists;
  if not v_ownership_exists then raise exception 'U3 expired ownership row must still be preserved'; end if;

  select exists (
    select 1 from public.user_equipped_items where user_id = 'bc030000-0000-0000-0000-000000000003'
  ) into v_equipped_exists;
  if v_equipped_exists then raise exception 'U3 expired legacy item must never be migrated as equipped'; end if;
end $$;

-- Scenario: valid equipped legacy item migrates and equips correctly (U4).
do $$
declare v_row record;
begin
  select uei.user_id, bci.code into v_row
  from public.user_equipped_items uei
  join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where uei.user_id = 'bc030000-0000-0000-0000-000000000004' and uei.slot_type = 'avatar_frame';
  if not found then raise exception 'U4 valid equipped R4 item must migrate as equipped'; end if;
  if v_row.code <> 'm3t_frame_d' then raise exception 'U4 equipped wrong item: %', v_row.code; end if;
end $$;

-- Scenario: unknown/unresolvable item is logged and left untouched (U5),
-- and a distinct missing-catalog-mapping case is logged for R4 too (U9).
do $$
begin
  if exists (select 1 from public.user_backpack_items where user_id = 'bc030000-0000-0000-0000-000000000005') then
    raise exception 'U5 unresolvable frame_key must never produce an ownership row';
  end if;
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_avatar_frames' and source_user_id = 'bc030000-0000-0000-0000-000000000005'
      and issue_type = 'missing_catalog_mapping'
  ) then
    raise exception 'U5 unresolvable row must be logged as missing_catalog_mapping';
  end if;

  if exists (select 1 from public.user_backpack_items where user_id = 'bc030000-0000-0000-0000-000000000009') then
    raise exception 'U9 unresolvable frame_key must never produce an ownership row';
  end if;
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'backpack_items' and source_user_id = 'bc030000-0000-0000-0000-000000000009'
      and issue_type = 'missing_catalog_mapping'
  ) then
    raise exception 'U9 unresolvable row must be logged as missing_catalog_mapping';
  end if;
end $$;

-- Scenario: duplicate legacy ownership across sources follows R2 > R1 (U6).
do $$
declare v_active_count int;
declare v_source_ref text;
begin
  select count(*) into v_active_count
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.user_id = 'bc030000-0000-0000-0000-000000000006' and bci.code = 'm3t_frame_e' and ubi.is_revoked = false;
  if v_active_count <> 1 then raise exception 'U6 must have exactly one active ownership row after dedupe, got %', v_active_count; end if;

  select ubi.source_reference into v_source_ref
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.user_id = 'bc030000-0000-0000-0000-000000000006' and bci.code = 'm3t_frame_e' and ubi.is_revoked = false;
  if v_source_ref !~ '^user_frames:' then
    raise exception 'U6 higher-priority R2 source must win, got source_reference=%', v_source_ref;
  end if;

  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_avatar_frames' and source_user_id = 'bc030000-0000-0000-0000-000000000006'
      and issue_type = 'duplicate_superseded'
  ) then
    raise exception 'U6 lower-priority R1 row must be logged as duplicate_superseded';
  end if;
end $$;

-- Scenario: revoked legacy ownership stays revoked, never merged (U7).
do $$
begin
  if exists (select 1 from public.user_backpack_items where user_id = 'bc030000-0000-0000-0000-000000000007') then
    raise exception 'U7 revoked user_frames row must never produce an active ownership row';
  end if;
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'user_frames' and source_user_id = 'bc030000-0000-0000-0000-000000000007'
      and issue_type = 'revoked_source'
  ) then
    raise exception 'U7 revoked row must be logged as revoked_source';
  end if;
end $$;

-- Scenario: missing user reference is logged, migration does not crash (U8).
do $$
begin
  if exists (select 1 from public.user_backpack_items where user_id = 'bc030000-0000-0000-0000-000000000008') then
    raise exception 'U8 (no auth.users row) must never produce an ownership row';
  end if;
  if not exists (
    select 1 from public.backpack_v2_migration_issues
    where source_table = 'backpack_items' and source_user_id = 'bc030000-0000-0000-0000-000000000008'
      and issue_type = 'missing_user_reference'
  ) then
    raise exception 'U8 missing user reference must be logged';
  end if;
end $$;

-- ── Snapshot post-run-1 counts (for retry-stability comparison) ─────────

create temp table m3_post_run1 as
select
  (select count(*) from public.user_backpack_items where source_type = 'legacy_migration') as ownership_count,
  (select count(*) from public.user_equipped_items) as equipped_count,
  (select count(*) from public.backpack_v2_migration_issues where batch = 'm3_legacy_backfill_v1') as issues_count;

-- ── Run 2: migration applied twice must be a stable no-op ───────────────

create temp table m3_run2 as
select public.backpack_v2_run_m3_backfill() as result;

do $$
declare v_result jsonb;
begin
  select result into v_result from m3_run2;
  if v_result ->> 'r2_frame_v2_ownership_inserted' <> '0'
    or v_result ->> 'r1_legacy_avatar_frames_ownership_inserted' <> '0'
    or v_result ->> 'r4_backpack_items_ownership_inserted' <> '0' then
    raise exception 'second run must insert zero new ownership rows, got %', v_result;
  end if;
end $$;

do $$
declare v_before record;
declare v_after record;
begin
  select * into v_before from m3_post_run1;
  select
    (select count(*) from public.user_backpack_items where source_type = 'legacy_migration') as ownership_count,
    (select count(*) from public.user_equipped_items) as equipped_count,
    (select count(*) from public.backpack_v2_migration_issues where batch = 'm3_legacy_backfill_v1') as issues_count
  into v_after;

  if v_before.ownership_count <> v_after.ownership_count then
    raise exception 'ownership count not stable after retry: % -> %', v_before.ownership_count, v_after.ownership_count;
  end if;
  if v_before.equipped_count <> v_after.equipped_count then
    raise exception 'equipped count not stable after retry: % -> %', v_before.equipped_count, v_after.equipped_count;
  end if;
  if v_before.issues_count <> v_after.issues_count then
    raise exception 'issues count not stable after retry (dedupe failed): % -> %', v_before.issues_count, v_after.issues_count;
  end if;
end $$;

-- Re-verify U1's permanent ownership and U4's equip are still intact and
-- untouched after the retry (row identity, not just counts).
do $$
declare v_expires timestamptz;
begin
  select ubi.expires_at into v_expires
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.user_id = 'bc030000-0000-0000-0000-000000000001' and bci.code = 'm3t_frame_a';
  if v_expires is not null then raise exception 'U1 permanent ownership regressed after retry'; end if;

  if not exists (
    select 1 from public.user_equipped_items where user_id = 'bc030000-0000-0000-0000-000000000004' and slot_type = 'avatar_frame'
  ) then
    raise exception 'U4 equipped state regressed after retry';
  end if;
end $$;

-- ── Scenario: legacy data remains completely unchanged ───────────────────

do $$
declare v_before record;
declare v_after record;
begin
  select * into v_before from m3_legacy_snapshot_before;
  select
    (select count(*) from public.user_frames) as user_frames_count,
    (select count(*) from public.user_avatar_frames) as user_avatar_frames_count,
    (select count(*) from public.backpack_items) as backpack_items_count,
    (select count(*) from public.avatar_frames) as avatar_frames_count,
    (select count(*) from public.frame_catalog) as frame_catalog_count,
    (select count(*) from public.frame_legacy_map) as frame_legacy_map_count,
    (select is_equipped from public.user_avatar_frames
       where user_id = 'bc030000-0000-0000-0000-000000000003') as u3_is_equipped,
    (select expires_at from public.user_avatar_frames
       where user_id = 'bc030000-0000-0000-0000-000000000003') as u3_expires_at
  into v_after;

  if v_before.user_frames_count <> v_after.user_frames_count
    or v_before.user_avatar_frames_count <> v_after.user_avatar_frames_count
    or v_before.backpack_items_count <> v_after.backpack_items_count
    or v_before.avatar_frames_count <> v_after.avatar_frames_count
    or v_before.frame_catalog_count <> v_after.frame_catalog_count
    or v_before.frame_legacy_map_count <> v_after.frame_legacy_map_count then
    raise exception 'legacy table row counts changed: before=% after=%', row_to_json(v_before), row_to_json(v_after);
  end if;
  if v_before.u3_is_equipped is distinct from v_after.u3_is_equipped
    or v_before.u3_expires_at is distinct from v_after.u3_expires_at then
    raise exception 'legacy row content mutated: U3 before=%/% after=%/%',
      v_before.u3_is_equipped, v_before.u3_expires_at, v_after.u3_is_equipped, v_after.u3_expires_at;
  end if;
end $$;

-- ── Function is not exposed to authenticated/anon ────────────────────────

do $$ begin
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims','{"sub":"bc030000-0000-0000-0000-000000000001","role":"authenticated"}',true);
    perform public.backpack_v2_run_m3_backfill();
    raise exception 'authenticated role must not be able to call the M3 backfill function';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end $$;

rollback;
