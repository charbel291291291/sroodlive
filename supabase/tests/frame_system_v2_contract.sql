\set ON_ERROR_STOP on
begin;

-- ── Catalog seeded and legacy-mapped ─────────────────────────────────────────
do $$ begin
  if (select count(*) from public.frame_catalog where code like 'vip_%') < 9 then
    raise exception 'vip tier catalog rows missing';
  end if;
  if (select code from public.frame_legacy_map where legacy_key='vip_bronze_star') <> 'vip_1' then
    raise exception 'legacy alias vip_bronze_star not mapped to vip_1';
  end if;
  -- Every legacy catalog row must be reachable in v2 (code or legacy map).
  if exists (
    select 1 from public.avatar_frames af
    where not exists (select 1 from public.frame_catalog fc where fc.code = af.frame_key)
      and not exists (select 1 from public.frame_legacy_map m where m.legacy_key = af.frame_key)
  ) then
    raise exception 'unmapped legacy avatar_frames keys exist';
  end if;
  -- Legacy FK compatibility: vip_N codes exist in avatar_frames too.
  if (select count(*) from public.avatar_frames where frame_key like 'vip\_%' and frame_key ~ '^vip_[1-9]$') <> 9 then
    raise exception 'vip_1..vip_9 missing from legacy avatar_frames (profiles FK would fail)';
  end if;
  -- Enforcement must default to LOG-ONLY.
  if (select enforce_selection from public.frame_settings_v2 where id=1) then
    raise exception 'enforcement must default to false (log-only)';
  end if;
end $$;

-- ── Test users: one plain, one VIP 5, one admin ──────────────────────────────
insert into auth.users(id,instance_id,aud,role,email) values
 ('f2000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','frames-v2-plain@example.com'),
 ('f2000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','frames-v2-vip@example.com'),
 ('f2000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','frames-v2-admin@example.com')
on conflict(id) do nothing;

insert into public.profiles(id) values
 ('f2000000-0000-0000-0000-000000000001'),
 ('f2000000-0000-0000-0000-000000000002'),
 ('f2000000-0000-0000-0000-000000000003')
on conflict(id) do nothing;

update public.profiles set vip_level=5, vip_expires_at=now()+interval '30 days'
 where id='f2000000-0000-0000-0000-000000000002';
-- app_user_roles gates wearing role-restricted frames (frames_v2_user_can_use);
-- admin_users gates admin RPC access (has_admin_access) — two distinct models,
-- both needed here since this user exercises both paths below.
insert into public.app_user_roles(user_id, role)
 values ('f2000000-0000-0000-0000-000000000003','super_admin')
on conflict do nothing;
insert into public.admin_users(user_id, role, is_active)
 values ('f2000000-0000-0000-0000-000000000003','super_admin', true)
on conflict do nothing;

-- ── Entitlement rules ────────────────────────────────────────────────────────
do $$ begin
  -- Free frames usable by anyone.
  if not public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000001','normal_silver_ring') then
    raise exception 'free frame must be usable';
  end if;
  -- VIP tier gates.
  if public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000001','vip_1') then
    raise exception 'non-VIP user must not use vip_1';
  end if;
  if not public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000002','vip_5') then
    raise exception 'VIP 5 user must use vip_5';
  end if;
  if public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000002','vip_6') then
    raise exception 'VIP 5 user must not use vip_6';
  end if;
  -- Legacy alias resolves and stays gated.
  if not public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000002','vip_royal_king') then
    raise exception 'legacy alias vip_royal_king must resolve for VIP 5';
  end if;
  -- Expired VIP loses tier frames.
  update public.profiles set vip_expires_at=now()-interval '1 day'
    where id='f2000000-0000-0000-0000-000000000002';
  if public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000002','vip_5') then
    raise exception 'expired VIP must not use vip_5';
  end if;
  update public.profiles set vip_expires_at=now()+interval '30 days'
    where id='f2000000-0000-0000-0000-000000000002';
  -- Role frames require the server-side role.
  if public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000001','custom_super_admin') then
    raise exception 'role frame must not be usable without role';
  end if;
  if not public.frames_v2_user_can_use('f2000000-0000-0000-0000-000000000003','custom_super_admin') then
    raise exception 'super_admin role frame must be usable by super_admin';
  end if;
end $$;

-- ── select_my_frame_v2: allowed + blocked paths ─────────────────────────────
select set_config('request.jwt.claims','{"sub":"f2000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.select_my_frame_v2('vip_5');
do $$ begin
  if (select selected_avatar_frame_key from public.profiles
      where id='f2000000-0000-0000-0000-000000000002') <> 'vip_5' then
    raise exception 'select_my_frame_v2 did not persist selection';
  end if;
end $$;

do $$ begin
  begin
    perform public.select_my_frame_v2('vip_9');
    raise exception 'selecting vip_9 as VIP5 must fail';
  exception when others then
    if sqlerrm not like '%frame_not_allowed%' then raise; end if;
  end;
end $$;

-- ── Log-only guard: direct column update logs violation but is not blocked ──
update public.profiles set selected_avatar_frame_key='custom_super_admin'
 where id='f2000000-0000-0000-0000-000000000002';
do $$ begin
  if (select selected_avatar_frame_key from public.profiles
      where id='f2000000-0000-0000-0000-000000000002') <> 'custom_super_admin' then
    raise exception 'log-only mode must not block the legacy direct update path';
  end if;
  if not exists (
    select 1 from public.frame_ownership_audit
    where user_id='f2000000-0000-0000-0000-000000000002'
      and frame_code='custom_super_admin' and action='violation'
  ) then
    raise exception 'violation was not logged';
  end if;
end $$;
update public.profiles set selected_avatar_frame_key='vip_5'
 where id='f2000000-0000-0000-0000-000000000002';

-- ── Enforcement mode blocks the same path ────────────────────────────────────
update public.frame_settings_v2 set enforce_selection=true where id=1;
do $$ begin
  begin
    update public.profiles set selected_avatar_frame_key='custom_super_admin'
     where id='f2000000-0000-0000-0000-000000000002';
    raise exception 'enforced mode must block unauthorized selection';
  exception when others then
    if sqlerrm not like '%frame_not_allowed%' then raise; end if;
  end;
end $$;
update public.frame_settings_v2 set enforce_selection=false where id=1;

-- ── Admin assign / revoke with audit history ────────────────────────────────
select set_config('request.jwt.claims','{"sub":"f2000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.admin_assign_frame_v2('f2000000-0000-0000-0000-000000000001','luxury_ruby_royal','admin_grant',null);
do $$ begin
  if not exists (
    select 1 from public.user_frames uf
    join public.frame_catalog fc on fc.id=uf.frame_id
    where uf.user_id='f2000000-0000-0000-0000-000000000001'
      and fc.code='luxury_ruby_royal' and uf.revoked_at is null
  ) then
    raise exception 'admin assignment missing';
  end if;
end $$;

select public.admin_revoke_frame_v2('f2000000-0000-0000-0000-000000000001','luxury_ruby_royal','contract-test');
do $$ begin
  if exists (
    select 1 from public.user_frames uf
    join public.frame_catalog fc on fc.id=uf.frame_id
    where uf.user_id='f2000000-0000-0000-0000-000000000001'
      and fc.code='luxury_ruby_royal' and uf.revoked_at is null
  ) then
    raise exception 'revocation did not close ownership';
  end if;
  if (select count(*) from public.frame_ownership_audit
      where user_id='f2000000-0000-0000-0000-000000000001'
        and frame_code='luxury_ruby_royal'
        and action in ('grant','revoke')) < 2 then
    raise exception 'grant/revoke audit history missing';
  end if;
end $$;

-- Non-admin must not manage frames.
select set_config('request.jwt.claims','{"sub":"f2000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.admin_assign_frame_v2('f2000000-0000-0000-0000-000000000001','vip_9','admin_grant',null);
    raise exception 'non-admin assign must fail';
  exception when others then
    if sqlerrm not like '%not_authorized%' then raise; end if;
  end;
end $$;

-- ── Privilege boundaries ─────────────────────────────────────────────────────
do $$ begin
  if has_table_privilege('authenticated','public.user_frames','INSERT')
    or has_table_privilege('authenticated','public.user_frames','UPDATE')
    or has_table_privilege('authenticated','public.frame_catalog','UPDATE')
    or has_table_privilege('authenticated','public.frame_settings_v2','UPDATE')
    or has_table_privilege('anon','public.frame_catalog','SELECT') then
    raise exception 'frame v2 privilege boundary failed';
  end if;
end $$;

-- ── Migration report shape ───────────────────────────────────────────────────
select set_config('request.jwt.claims','{"sub":"f2000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
do $$ declare v jsonb; begin
  v := public.frames_v2_migration_report();
  if v is null or not (v ? 'legacy_catalog_rows') or not (v ? 'v2_ownership_rows') then
    raise exception 'migration report incomplete';
  end if;
end $$;

rollback;
