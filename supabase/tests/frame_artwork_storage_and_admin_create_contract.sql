-- Frame Management v2 — artwork storage, admin_create_frame_v2, and admin
-- role compatibility for role-gated frames.
--
-- Covers:
--   20261133000000_frame_artwork_storage_and_create_rpc.sql
--   20261202000000_frames_v2_admin_role_compatibility.sql
--
-- Runs inside a single transaction and ends in ROLLBACK, so every test user,
-- test frame, storage object, audit row and role grant created here is undone.
-- Nothing is left behind in the local database.
--
--   docker exec -i supabase_db_srood_live psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/frame_artwork_storage_and_admin_create_contract.sql

\set ON_ERROR_STOP on
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- Baseline: row counts + content digests of everything this work must preserve
-- ════════════════════════════════════════════════════════════════════════════

create temp table frames_baseline(label text primary key, cnt bigint, digest text);

insert into frames_baseline
select 'frame_catalog', count(*), md5(coalesce(string_agg(t, '|' order by t), ''))
from (
  select id::text||'~'||code||'~'||name||'~'||category||'~'||coalesce(asset_url,'')
      ||'~'||coalesce(thumbnail_url,'')||'~'||coalesce(animation_url,'')
      ||'~'||coalesce(unlock_value,'')||'~'||coalesce(required_role,'')
      ||'~'||coalesce(required_level::text,'')||'~'||coalesce(required_vip_level::text,'')
      ||'~'||is_active::text||'~'||sort_order::text as t
  from public.frame_catalog
) s;

insert into frames_baseline
select 'avatar_frames', count(*), md5(coalesce(string_agg(t, '|' order by t), ''))
from (
  select id::text||'~'||frame_key||'~'||name||'~'||category
      ||'~'||coalesce(vip_level::text,'')||'~'||coalesce(required_vip_level::text,'')
      ||'~'||coalesce(asset_url,'')||'~'||is_active::text||'~'||sort_order::text as t
  from public.avatar_frames
) s;

insert into frames_baseline
select 'user_avatar_frames', count(*), md5(coalesce(string_agg(t, '|' order by t), ''))
from (select id::text||'~'||user_id::text||'~'||frame_key as t from public.user_avatar_frames) s;

insert into frames_baseline
select 'user_frames', count(*), md5(coalesce(string_agg(t, '|' order by t), ''))
from (select id::text||'~'||user_id::text||'~'||frame_id::text as t from public.user_frames) s;

\echo '── BEFORE ──────────────────────────────────────────────────────────────'
select label, cnt from frames_baseline order by label;

-- ════════════════════════════════════════════════════════════════════════════
-- Fixtures
--   ...0002  plain authenticated user, no roles at all
--   ...0003  active admin_users role 'admin'
--   ...0004  INACTIVE admin_users role 'super_admin'
--   ...0005  legacy app_user_roles role 'super_admin', no admin_users row
-- ════════════════════════════════════════════════════════════════════════════

insert into auth.users(id,instance_id,aud,role,email) values
 ('f2100000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fa-plain@example.test'),
 ('f2100000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fa-admin@example.test'),
 ('f2100000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fa-inactive-admin@example.test'),
 ('f2100000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fa-legacy-role@example.test')
on conflict(id) do nothing;

insert into public.profiles(id) values
 ('f2100000-0000-0000-0000-000000000002'),
 ('f2100000-0000-0000-0000-000000000003'),
 ('f2100000-0000-0000-0000-000000000004'),
 ('f2100000-0000-0000-0000-000000000005')
on conflict(id) do nothing;

-- admin_users has no plain unique key on user_id (only a partial unique index
-- WHERE is_active), so these are plain inserts for freshly created test users.
insert into public.admin_users(user_id, role, is_active) values
 ('f2100000-0000-0000-0000-000000000003','admin', true),
 ('f2100000-0000-0000-0000-000000000004','super_admin', false);

insert into public.app_user_roles(user_id, role) values
 ('f2100000-0000-0000-0000-000000000005','super_admin')
on conflict do nothing;

-- ════════════════════════════════════════════════════════════════════════════
-- 1. Anonymous user cannot upload an avatar frame object
-- ════════════════════════════════════════════════════════════════════════════

select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;

do $do$
declare ok boolean := false;
begin
  begin
    insert into storage.objects(bucket_id, name)
    values ('avatar-frames','luxury/zz_test_anon/v1.webp');
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then
    raise exception 'CASE 1 FAILED: anon was allowed to upload into avatar-frames';
  end if;
end $do$;

reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- 2. Normal authenticated user cannot upload an avatar frame object
-- ════════════════════════════════════════════════════════════════════════════

select set_config('request.jwt.claims','{"sub":"f2100000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;

do $do$
declare ok boolean := false;
begin
  begin
    insert into storage.objects(bucket_id, name, owner)
    values ('avatar-frames','luxury/zz_test_plain/v1.webp','f2100000-0000-0000-0000-000000000002');
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then
    raise exception 'CASE 2 FAILED: non-admin authenticated user uploaded into avatar-frames';
  end if;
end $do$;

reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- 3. Admin user can upload an avatar frame object
-- ════════════════════════════════════════════════════════════════════════════

select set_config('request.jwt.claims','{"sub":"f2100000-0000-0000-0000-000000000003","role":"authenticated"}',true);
set local role authenticated;

insert into storage.objects(bucket_id, name, owner)
values ('avatar-frames','luxury/zz_test_alpha/v1.webp','f2100000-0000-0000-0000-000000000003');

do $do$ begin
  if not exists (
    select 1 from storage.objects
    where bucket_id='avatar-frames' and name='luxury/zz_test_alpha/v1.webp'
  ) then
    raise exception 'CASE 3 FAILED: admin upload did not persist';
  end if;
end $do$;

reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- 4. Anonymous user cannot call admin_create_frame_v2
-- ════════════════════════════════════════════════════════════════════════════

select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;

do $do$
declare ok boolean := false;
begin
  begin
    perform public.admin_create_frame_v2('zz_test_anon','ZZ Anon','luxury');
  exception
    when insufficient_privilege then ok := true;
    when others then if sqlerrm = 'not_authorized' then ok := true; else raise; end if;
  end;
  if not ok then
    raise exception 'CASE 4 FAILED: anon called admin_create_frame_v2';
  end if;
end $do$;

reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- 5. Normal authenticated user cannot call admin_create_frame_v2
-- ════════════════════════════════════════════════════════════════════════════

select set_config('request.jwt.claims','{"sub":"f2100000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;

do $do$
declare ok boolean := false;
begin
  begin
    perform public.admin_create_frame_v2('zz_test_plain','ZZ Plain','luxury');
  exception when others then
    if sqlerrm = 'not_authorized' then ok := true; else raise; end if;
  end;
  if not ok then
    raise exception 'CASE 5 FAILED: non-admin created a frame';
  end if;
end $do$;

do $do$ begin
  if exists (select 1 from public.frame_catalog where code in ('zz_test_anon','zz_test_plain')) then
    raise exception 'CASE 4/5 FAILED: a rejected create still wrote a frame_catalog row';
  end if;
end $do$;

reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- 6. Admin user can create a valid frame
-- ════════════════════════════════════════════════════════════════════════════

select set_config('request.jwt.claims','{"sub":"f2100000-0000-0000-0000-000000000003","role":"authenticated"}',true);
set local role authenticated;

do $do$
declare v_id uuid;
begin
  v_id := public.admin_create_frame_v2(
    p_code => 'zz_test_alpha',
    p_name => 'ZZ Test Alpha',
    p_category => 'luxury',
    p_rarity => 'rare',
    p_asset_type => 'network',
    p_asset_url => 'https://example.test/avatar-frames/luxury/zz_test_alpha/v1.webp',
    p_thumbnail_url => 'https://example.test/avatar-frames/luxury/zz_test_alpha/thumb.webp',
    p_animation_url => 'https://example.test/avatar-frames/luxury/zz_test_alpha/anim.webp',
    p_is_animated => true,
    p_sort_order => 990,
    p_unlock_type => 'free',
    p_unlock_value => 'zz-unlock-value',
    p_required_level => 3
  );
  if v_id is null then
    raise exception 'CASE 6 FAILED: admin_create_frame_v2 returned null id';
  end if;
  if not exists (
    select 1 from public.frame_catalog
    where id = v_id and code='zz_test_alpha' and name='ZZ Test Alpha'
      and thumbnail_url is not null and animation_url is not null
      and unlock_value = 'zz-unlock-value' and required_level = 3
  ) then
    raise exception 'CASE 6 FAILED: created row missing or columns dropped';
  end if;
end $do$;

-- ════════════════════════════════════════════════════════════════════════════
-- 7. Duplicate frame code fails with frame_code_exists
-- ════════════════════════════════════════════════════════════════════════════

do $do$
declare ok boolean := false;
begin
  begin
    perform public.admin_create_frame_v2('zz_test_alpha','Different Name','vip');
  exception when others then
    if sqlerrm = 'frame_code_exists' then ok := true; else raise; end if;
  end;
  if not ok then
    raise exception 'CASE 7 FAILED: duplicate code did not raise frame_code_exists';
  end if;
end $do$;

-- ════════════════════════════════════════════════════════════════════════════
-- 8. Invalid VIP configuration fails with invalid_vip_config
-- ════════════════════════════════════════════════════════════════════════════

do $do$
declare ok boolean := false;
begin
  -- vip_level unlock with no VIP level at all
  begin
    perform public.admin_create_frame_v2(
      p_code => 'zz_test_vipbad', p_name => 'ZZ VIP Bad', p_category => 'vip',
      p_unlock_type => 'vip_level');
  exception when others then
    if sqlerrm = 'invalid_vip_config' then ok := true; else raise; end if;
  end;
  if not ok then
    raise exception 'CASE 8 FAILED: vip_level unlock with no level was accepted';
  end if;

  -- two VIP columns that disagree
  ok := false;
  begin
    perform public.admin_create_frame_v2(
      p_code => 'zz_test_vipdrift', p_name => 'ZZ VIP Drift', p_category => 'vip',
      p_vip_level => 7, p_unlock_type => 'vip_level', p_required_vip_level => 2);
  exception when others then
    if sqlerrm = 'invalid_vip_config' then ok := true; else raise; end if;
  end;
  if not ok then
    raise exception 'CASE 8 FAILED: drifting vip_level / required_vip_level was accepted';
  end if;
end $do$;

-- ════════════════════════════════════════════════════════════════════════════
-- 9. Invalid role configuration fails with invalid_role_config
-- ════════════════════════════════════════════════════════════════════════════

do $do$
declare ok boolean := false;
begin
  begin
    perform public.admin_create_frame_v2(
      p_code => 'zz_test_rolebad', p_name => 'ZZ Role Bad', p_category => 'luxury',
      p_unlock_type => 'role', p_required_role => '   ');
  exception when others then
    if sqlerrm = 'invalid_role_config' then ok := true; else raise; end if;
  end;
  if not ok then
    raise exception 'CASE 9 FAILED: role unlock with blank required_role was accepted';
  end if;
end $do$;

-- ════════════════════════════════════════════════════════════════════════════
-- 10. A successful create writes an admin_audit_logs row (create_frame_v2)
-- ════════════════════════════════════════════════════════════════════════════

do $do$ begin
  if not exists (
    select 1 from public.admin_audit_logs
    where action='create_frame_v2' and entity_type='frame_catalog'
      and entity_id='zz_test_alpha'
      and admin_user_id='f2100000-0000-0000-0000-000000000003'
  ) then
    raise exception 'CASE 10 FAILED: no create_frame_v2 audit row for the creating admin';
  end if;
  if (select count(*) from public.admin_audit_logs
      where action='create_frame_v2'
        and entity_id in ('zz_test_anon','zz_test_plain','zz_test_vipbad',
                          'zz_test_vipdrift','zz_test_rolebad')) <> 0 then
    raise exception 'CASE 10 FAILED: rejected creates wrote audit rows';
  end if;
end $do$;

-- ════════════════════════════════════════════════════════════════════════════
-- 11. A successful create mirrors the legacy avatar_frames row (profiles FK)
-- ════════════════════════════════════════════════════════════════════════════

do $do$ begin
  if not exists (
    select 1 from public.avatar_frames
    where frame_key='zz_test_alpha' and category='luxury' and is_active
  ) then
    raise exception 'CASE 11 FAILED: legacy avatar_frames mirror row missing';
  end if;
end $do$;

-- profiles.selected_avatar_frame_key FK really does accept the new code.
reset role;
update public.profiles set selected_avatar_frame_key='zz_test_alpha'
 where id='f2100000-0000-0000-0000-000000000003';
do $do$ begin
  if (select selected_avatar_frame_key from public.profiles
      where id='f2100000-0000-0000-0000-000000000003') <> 'zz_test_alpha' then
    raise exception 'CASE 11 FAILED: created code not selectable on profiles';
  end if;
end $do$;
update public.profiles set selected_avatar_frame_key=null
 where id='f2100000-0000-0000-0000-000000000003';
set local role authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 12. A failed create does not modify an existing frame
-- ════════════════════════════════════════════════════════════════════════════

do $do$
declare v_before text;
        v_after  text;
        ok boolean := false;
begin
  select name||'~'||category||'~'||coalesce(asset_url,'')||'~'||coalesce(thumbnail_url,'')
         ||'~'||coalesce(unlock_value,'')||'~'||coalesce(required_level::text,'')
         ||'~'||is_active::text||'~'||sort_order::text
    into v_before from public.frame_catalog where code='zz_test_alpha';

  begin
    perform public.admin_create_frame_v2(
      p_code => 'zz_test_alpha', p_name => 'OVERWRITTEN', p_category => 'vip',
      p_vip_level => 9, p_asset_url => 'https://example.test/evil.webp',
      p_is_active => false, p_sort_order => 1);
  exception when others then
    if sqlerrm = 'frame_code_exists' then ok := true; else raise; end if;
  end;
  if not ok then
    raise exception 'CASE 12 FAILED: colliding create did not fail';
  end if;

  select name||'~'||category||'~'||coalesce(asset_url,'')||'~'||coalesce(thumbnail_url,'')
         ||'~'||coalesce(unlock_value,'')||'~'||coalesce(required_level::text,'')
         ||'~'||is_active::text||'~'||sort_order::text
    into v_after from public.frame_catalog where code='zz_test_alpha';

  if v_before is distinct from v_after then
    raise exception 'CASE 12 FAILED: failed create mutated the existing frame (% -> %)',
      v_before, v_after;
  end if;
end $do$;

-- ════════════════════════════════════════════════════════════════════════════
-- 13. admin_upsert_frame_v2 still updates an existing frame
-- ════════════════════════════════════════════════════════════════════════════

do $do$ begin
  perform public.admin_upsert_frame_v2(
    p_code => 'zz_test_alpha',
    p_name => 'ZZ Test Alpha Renamed',
    p_category => 'luxury',
    p_vip_level => null,
    p_rarity => 'epic',
    p_asset_type => 'network',
    p_asset_url => 'https://example.test/avatar-frames/luxury/zz_test_alpha/v2.webp',
    p_thumbnail_url => 'https://example.test/avatar-frames/luxury/zz_test_alpha/thumb.webp',
    p_animation_url => 'https://example.test/avatar-frames/luxury/zz_test_alpha/anim.webp',
    p_is_animated => true,
    p_is_active => true,
    p_sort_order => 991,
    p_unlock_type => 'free',
    p_unlock_value => 'zz-unlock-value',
    p_required_role => null,
    p_required_level => 3,
    p_required_vip_level => null,
    p_starts_at => null,
    p_expires_at => null,
    p_localized_names => '{}'::jsonb
  );
  if not exists (
    select 1 from public.frame_catalog
    where code='zz_test_alpha' and name='ZZ Test Alpha Renamed'
      and rarity='epic' and sort_order=991
      and asset_url like '%/v2.webp'
      and thumbnail_url is not null and animation_url is not null
      and unlock_value='zz-unlock-value' and required_level=3
  ) then
    raise exception 'CASE 13 FAILED: admin_upsert_frame_v2 did not update the frame';
  end if;
  if (select count(*) from public.frame_catalog where code='zz_test_alpha') <> 1 then
    raise exception 'CASE 13 FAILED: upsert duplicated the frame row';
  end if;
end $do$;

reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- R1-R6. Admin role compatibility (20261202000000)
--   custom_admin        required_role 'admin',       unlock_type 'role'
--   custom_super_admin  required_role 'super_admin', unlock_type 'role'
-- ════════════════════════════════════════════════════════════════════════════

do $do$ begin
  -- R1. A qualifying admin_users record unlocks the matching role frame.
  if not public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000003','custom_admin') then
    raise exception 'CASE R1 FAILED: active admin_users role=admin cannot use custom_admin';
  end if;

  -- R2. A revoked / inactive admin does not unlock it.
  if public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000004','custom_super_admin') then
    raise exception 'CASE R2 FAILED: inactive admin unlocked custom_super_admin';
  end if;
  if public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000004','custom_admin') then
    raise exception 'CASE R2 FAILED: inactive admin unlocked custom_admin';
  end if;

  -- R3. An unrelated / lower admin role does not unlock it.
  if public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000003','custom_super_admin') then
    raise exception 'CASE R3 FAILED: role=admin unlocked the super_admin frame';
  end if;

  -- R4. Existing app_user_roles behaviour still works, unchanged.
  if not public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000005','custom_super_admin') then
    raise exception 'CASE R4 FAILED: legacy app_user_roles super_admin lost access';
  end if;
  if public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000005','custom_admin') then
    raise exception 'CASE R4 FAILED: legacy app_user_roles super_admin leaked into custom_admin';
  end if;

  -- R5. Non-role frames are unaffected in both directions.
  if not public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000002','luxury_autumn_bloom') then
    raise exception 'CASE R5 FAILED: free frame no longer usable by a plain user';
  end if;
  if public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000003','vip_9') then
    raise exception 'CASE R5 FAILED: admin membership bypassed the VIP gate on vip_9';
  end if;
  if not public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000003','luxury_autumn_bloom') then
    raise exception 'CASE R5 FAILED: free frame unusable by an admin';
  end if;

  -- R6. Normal users gain nothing.
  if public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000002','custom_admin')
    or public.frames_v2_user_can_use(
       'f2100000-0000-0000-0000-000000000002','custom_super_admin') then
    raise exception 'CASE R6 FAILED: plain user unlocked an admin frame';
  end if;

  -- Helper fails closed on anything outside the four admin_users_role_check values.
  if public.frames_v2_user_has_admin_role(
       'f2100000-0000-0000-0000-000000000003','moderator')
    or public.frames_v2_user_has_admin_role(
       'f2100000-0000-0000-0000-000000000003','')
    or public.frames_v2_user_has_admin_role(
       'f2100000-0000-0000-0000-000000000003', null) then
    raise exception 'CASE R-helper FAILED: unknown required_role did not fail closed';
  end if;
  -- ...and remains callable only by the owner (no PUBLIC / authenticated grant).
  if has_function_privilege('authenticated',
       'public.frames_v2_user_has_admin_role(uuid,text)','EXECUTE')
    or has_function_privilege('anon',
       'public.frames_v2_user_has_admin_role(uuid,text)','EXECUTE') then
    raise exception 'CASE R-helper FAILED: helper is directly callable by clients';
  end if;
end $do$;

-- ════════════════════════════════════════════════════════════════════════════
-- 14. Existing frame rows remain unchanged
-- 15. Existing ownership rows remain unchanged
-- ════════════════════════════════════════════════════════════════════════════

do $do$
declare b record; v_cnt bigint; v_digest text;
begin
  -- frame_catalog, excluding the one row this test created
  select count(*), md5(coalesce(string_agg(t, '|' order by t), '')) into v_cnt, v_digest
  from (
    select id::text||'~'||code||'~'||name||'~'||category||'~'||coalesce(asset_url,'')
        ||'~'||coalesce(thumbnail_url,'')||'~'||coalesce(animation_url,'')
        ||'~'||coalesce(unlock_value,'')||'~'||coalesce(required_role,'')
        ||'~'||coalesce(required_level::text,'')||'~'||coalesce(required_vip_level::text,'')
        ||'~'||is_active::text||'~'||sort_order::text as t
    from public.frame_catalog where code not like 'zz\_test\_%'
  ) s;
  select * into b from frames_baseline where label='frame_catalog';
  if v_cnt <> b.cnt or v_digest <> b.digest then
    raise exception 'CASE 14 FAILED: pre-existing frame_catalog rows changed (% -> % rows)',
      b.cnt, v_cnt;
  end if;

  select count(*), md5(coalesce(string_agg(t, '|' order by t), '')) into v_cnt, v_digest
  from (
    select id::text||'~'||frame_key||'~'||name||'~'||category
        ||'~'||coalesce(vip_level::text,'')||'~'||coalesce(required_vip_level::text,'')
        ||'~'||coalesce(asset_url,'')||'~'||is_active::text||'~'||sort_order::text as t
    from public.avatar_frames where frame_key not like 'zz\_test\_%'
  ) s;
  select * into b from frames_baseline where label='avatar_frames';
  if v_cnt <> b.cnt or v_digest <> b.digest then
    raise exception 'CASE 14 FAILED: pre-existing avatar_frames rows changed (% -> % rows)',
      b.cnt, v_cnt;
  end if;

  select count(*), md5(coalesce(string_agg(t, '|' order by t), '')) into v_cnt, v_digest
  from (select id::text||'~'||user_id::text||'~'||frame_key as t from public.user_avatar_frames) s;
  select * into b from frames_baseline where label='user_avatar_frames';
  if v_cnt <> b.cnt or v_digest <> b.digest then
    raise exception 'CASE 15 FAILED: user_avatar_frames changed (% -> % rows)', b.cnt, v_cnt;
  end if;

  select count(*), md5(coalesce(string_agg(t, '|' order by t), '')) into v_cnt, v_digest
  from (select id::text||'~'||user_id::text||'~'||frame_id::text as t from public.user_frames) s;
  select * into b from frames_baseline where label='user_frames';
  if v_cnt <> b.cnt or v_digest <> b.digest then
    raise exception 'CASE 15 FAILED: user_frames changed (% -> % rows)', b.cnt, v_cnt;
  end if;
end $do$;

\echo '── AFTER (test rows included) ──────────────────────────────────────────'
select 'frame_catalog' as label, count(*) as cnt from public.frame_catalog
union all select 'avatar_frames', count(*) from public.avatar_frames
union all select 'user_avatar_frames', count(*) from public.user_avatar_frames
union all select 'user_frames', count(*) from public.user_frames
order by label;

\echo '── AFTER (excluding zz_test_* fixtures) ────────────────────────────────'
select 'frame_catalog' as label, count(*) as cnt from public.frame_catalog where code not like 'zz\_test\_%'
union all select 'avatar_frames', count(*) from public.avatar_frames where frame_key not like 'zz\_test\_%'
union all select 'user_avatar_frames', count(*) from public.user_avatar_frames
union all select 'user_frames', count(*) from public.user_frames
order by label;

\echo 'ALL FRAME ARTWORK / CREATE-RPC / ROLE-COMPAT CASES PASSED'

-- Everything above is discarded: no test user, frame, object or audit row
-- survives this script.
rollback;
