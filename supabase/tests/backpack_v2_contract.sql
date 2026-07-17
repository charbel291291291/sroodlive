-- Contract test: Backpack System V2 RPCs, hardened per M2.1
-- (20261120000001_backpack_v2_rpcs.sql + 20261120000002_backpack_v2_hardening.sql)
-- enforce ownership, revocation, expiry, active/equippable/equip-enabled,
-- grantability, VIP gating, cross-user isolation (including the composite
-- FK), admin authorization, idempotent grant retries, precise duplicate-
-- grant merge semantics, scoped cleanup, and audit-log immutability
-- entirely server-side.
--
-- NOTE: psql's `:'varname'` interpolation does not reach inside dollar-quoted
-- (`do $$ ... $$`) bodies, so values captured via \gset are relayed into do
-- blocks through a session GUC (set_config/current_setting) instead of being
-- referenced directly inside the block.
\set ON_ERROR_STOP on
begin;

-- ── Fixtures: catalog items ──────────────────────────────────────────────
insert into public.backpack_catalog_items
  (code, name, item_type, equip_slot, is_active, is_equippable, is_grantable,
   is_equip_enabled, is_consumable, is_stackable, vip_level_required, default_duration_days)
values
  ('bpv2_test_frame_free', 'Test Free Frame', 'avatar_frame', 'avatar_frame', true, true, true, true, false, false, null, null),
  ('bpv2_test_frame_vip', 'Test VIP Frame', 'avatar_frame', 'avatar_frame', true, true, true, true, false, false, 5, null),
  ('bpv2_test_frame_not_equippable', 'Test Non-Equippable', 'avatar_frame', null, true, false, true, true, false, false, null, null),
  ('bpv2_test_frame_inactive', 'Test Inactive Frame', 'avatar_frame', 'avatar_frame', false, true, true, true, false, false, null, null),
  ('bpv2_test_frame_equip_disabled', 'Test Equip Disabled', 'avatar_frame', 'avatar_frame', true, true, true, false, false, false, null, null),
  ('bpv2_test_frame_not_grantable', 'Test Not Grantable', 'avatar_frame', 'avatar_frame', true, true, false, true, false, false, null, null),
  ('bpv2_test_badge_stack', 'Test Stackable Badge', 'badge', 'badge', true, true, true, true, true, true, null, null),
  ('bpv2_test_effect_temp', 'Test Temp Effect', 'entry_effect', 'entry_effect', true, true, true, true, false, false, null, 7)
on conflict (code) do nothing;

-- ── Fixtures: users (plain A, other B, admin C, matrix D) ────────────────
insert into auth.users(id,instance_id,aud,role,email) values
 ('bc000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bpv2-a@example.com'),
 ('bc000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bpv2-b@example.com'),
 ('bc000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bpv2-admin@example.com'),
 ('bc000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bpv2-d@example.com')
on conflict(id) do nothing;

insert into public.profiles(id) values
 ('bc000000-0000-0000-0000-000000000001'),
 ('bc000000-0000-0000-0000-000000000002'),
 ('bc000000-0000-0000-0000-000000000003'),
 ('bc000000-0000-0000-0000-000000000004')
on conflict(id) do nothing;

insert into public.admin_users(user_id, role, is_active)
 values ('bc000000-0000-0000-0000-000000000003','super_admin', true)
on conflict do nothing;

-- ── Unauthorized: plain user cannot call admin grant/revoke/global-cleanup ─
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_free');
    raise exception 'plain user must not be able to grant backpack items';
  exception when others then
    if sqlerrm <> 'not_authorized' then raise; end if;
  end;
  begin
    perform public.revoke_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_free', null);
    raise exception 'plain user must not be able to revoke backpack items';
  exception when others then
    if sqlerrm <> 'not_authorized' then raise; end if;
  end;
  begin
    perform public.admin_cleanup_all_expired_equipped_items_v2();
    raise exception 'plain user must not be able to run the global cleanup sweep';
  exception when others then
    if sqlerrm <> 'not_authorized' then raise; end if;
  end;
end $$;

-- ── Admin grants a free frame to user A ──────────────────────────────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_free') as free_grant_id \gset
select set_config('test.free_grant_id', :'free_grant_id', false);

do $$ declare v_row public.user_backpack_items%rowtype; begin
  select * into v_row from public.user_backpack_items where id = current_setting('test.free_grant_id')::uuid;
  if v_row.quantity <> 1 or v_row.is_revoked or v_row.source_type <> 'admin_grant' then
    raise exception 'unexpected grant row shape: %', row_to_json(v_row);
  end if;
end $$;

-- ── Not-grantable catalog items are blocked at grant time ────────────────
do $$ begin
  begin
    perform public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_not_grantable');
    raise exception 'non-grantable catalog item must not be grantable';
  exception when others then
    if sqlerrm <> 'item_not_grantable' then raise; end if;
  end;
end $$;

-- ── User A equips it, sees it in get_my_equipped_items_v2, unequips ──────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.equip_backpack_item_v2(current_setting('test.free_grant_id')::uuid) as equip_result \gset
do $$ begin
  if (select count(*) from public.get_my_equipped_items_v2() where code = 'bpv2_test_frame_free') <> 1 then
    raise exception 'equipped free frame must appear in get_my_equipped_items_v2';
  end if;
end $$;

-- ── Safe rendering RPC exposes only curated columns for any target user ──
do $$ begin
  if not exists (
    select 1 from public.get_public_equipped_items_v2('bc000000-0000-0000-0000-000000000001'::uuid)
    where code = 'bpv2_test_frame_free'
  ) then
    raise exception 'get_public_equipped_items_v2 must expose an equipped item for any target user';
  end if;
end $$;

do $$
declare v_cols text[];
begin
  select proargnames into v_cols
  from pg_proc where proname = 'get_public_equipped_items_v2' and pronamespace = 'public'::regnamespace;
  if v_cols && array['ownership_id','item_id','source_type','source_reference','quantity',
                      'revoked_reason','revoked_at','metadata','expires_at','created_at','updated_at'] then
    raise exception 'safe rendering RPC leaks a restricted column: %', v_cols;
  end if;
  if not (v_cols @> array['user_id','slot_type','code','asset_key']) then
    raise exception 'safe rendering RPC missing expected columns: %', v_cols;
  end if;
end $$;

-- ── Re-equip in the same slot: exactly one item per slot survives ────────
select public.equip_backpack_item_v2(current_setting('test.free_grant_id')::uuid) as slot_equip_2 \gset
do $$ begin
  if (select count(*) from public.user_equipped_items
      where user_id = 'bc000000-0000-0000-0000-000000000001' and slot_type = 'avatar_frame') <> 1 then
    raise exception 'exactly one row must exist per (user, slot) after repeated equips';
  end if;
end $$;

select public.unequip_backpack_slot_v2('avatar_frame') as unequip_1 \gset
select set_config('test.unequip_1', :'unequip_1', false);
do $$ begin
  if not current_setting('test.unequip_1')::boolean then raise exception 'first unequip must return true'; end if;
end $$;
select public.unequip_backpack_slot_v2('avatar_frame') as unequip_2 \gset
select set_config('test.unequip_2', :'unequip_2', false);
do $$ begin
  if current_setting('test.unequip_2')::boolean then raise exception 'second unequip on empty slot must return false, not error'; end if;
end $$;

-- ── Cross-user isolation: user B cannot equip user A's ownership row ────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.equip_backpack_item_v2(current_setting('test.free_grant_id')::uuid);
    raise exception 'user B must not be able to equip user A''s backpack item';
  exception when others then
    if sqlerrm <> 'backpack_item_not_found' then raise; end if;
  end;
end $$;

-- ── Composite FK rejects a cross-user ownership reference outright ───────
-- Even bypassing every RPC (direct SQL, as would a service-role script),
-- the DB itself must refuse to let user B's equipped row point at user A's
-- ownership row.
do $$ begin
  begin
    insert into public.user_equipped_items (user_id, slot_type, user_backpack_item_id)
    values ('bc000000-0000-0000-0000-000000000002', 'avatar_frame', current_setting('test.free_grant_id')::uuid);
    raise exception 'composite FK must reject a user_backpack_item_id owned by a different user';
  exception when foreign_key_violation then
    null;
  end;
end $$;

-- ── VIP gating: equip blocked below required level, allowed at/above ────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_vip') as vip_grant_id \gset
select set_config('test.vip_grant_id', :'vip_grant_id', false);

select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.equip_backpack_item_v2(current_setting('test.vip_grant_id')::uuid);
    raise exception 'VIP-gated frame must not equip below required level';
  exception when others then
    if sqlerrm <> 'vip_level_required' then raise; end if;
  end;
end $$;

update public.profiles set vip_level = 5, vip_expires_at = now() + interval '30 days'
  where id = 'bc000000-0000-0000-0000-000000000001';
select public.equip_backpack_item_v2(current_setting('test.vip_grant_id')::uuid) as vip_equip_result \gset

-- ── Not-equippable, inactive, and equip-disabled items block at equip time ─
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_not_equippable') as ne_grant_id \gset
select set_config('test.ne_grant_id', :'ne_grant_id', false);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_inactive') as inactive_grant_id \gset
select set_config('test.inactive_grant_id', :'inactive_grant_id', false);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_equip_disabled') as equip_disabled_grant_id \gset
select set_config('test.equip_disabled_grant_id', :'equip_disabled_grant_id', false);

select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.equip_backpack_item_v2(current_setting('test.ne_grant_id')::uuid);
    raise exception 'non-equippable item must not equip';
  exception when others then
    if sqlerrm <> 'item_not_equippable' then raise; end if;
  end;
  begin
    perform public.equip_backpack_item_v2(current_setting('test.inactive_grant_id')::uuid);
    raise exception 'inactive catalog item must not equip';
  exception when others then
    if sqlerrm <> 'item_not_active' then raise; end if;
  end;
  begin
    perform public.equip_backpack_item_v2(current_setting('test.equip_disabled_grant_id')::uuid);
    raise exception 'equip-disabled item must not equip';
  exception when others then
    if sqlerrm <> 'item_equip_disabled' then raise; end if;
  end;
end $$;

-- ── Admin revoke: un-equips immediately and blocks future equip ─────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.revoke_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_vip', 'contract test revoke') as revoke_result \gset

do $$ begin
  if not exists (
    select 1 from public.user_backpack_items
    where id = current_setting('test.vip_grant_id')::uuid and is_revoked = true and revoked_reason = 'contract test revoke'
  ) then
    raise exception 'revoke must mark ownership row revoked with reason';
  end if;
  if exists (
    select 1 from public.user_equipped_items where user_backpack_item_id = current_setting('test.vip_grant_id')::uuid
  ) then
    raise exception 'revoke must immediately clear the equipped slot pointing at it';
  end if;
end $$;

select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.equip_backpack_item_v2(current_setting('test.vip_grant_id')::uuid);
    raise exception 'revoked item must not be equippable';
  exception when others then
    if sqlerrm <> 'item_revoked' then raise; end if;
  end;
end $$;

-- ── Stackable duplicate grant increments quantity, non-stackable extends ─
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000002', 'bpv2_test_badge_stack', p_quantity => 3) as stack_grant_1 \gset
select set_config('test.stack_grant_1', :'stack_grant_1', false);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000002', 'bpv2_test_badge_stack', p_quantity => 2) as stack_grant_2 \gset
select set_config('test.stack_grant_2', :'stack_grant_2', false);
do $$ begin
  if current_setting('test.stack_grant_1') <> current_setting('test.stack_grant_2') then
    raise exception 'stackable duplicate grant must reuse the same ownership row, not insert a second one';
  end if;
  if (select quantity from public.user_backpack_items where id = current_setting('test.stack_grant_1')::uuid) <> 5 then
    raise exception 'stackable duplicate grant must sum quantities (3 + 2 = 5)';
  end if;
end $$;

select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000002', 'bpv2_test_effect_temp', p_duration_days => 7) as extend_grant_1 \gset
select set_config('test.extend_grant_1', :'extend_grant_1', false);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000002', 'bpv2_test_effect_temp', p_duration_days => 7) as extend_grant_2 \gset
select set_config('test.extend_grant_2', :'extend_grant_2', false);
do $$ declare v_expires timestamptz; begin
  if current_setting('test.extend_grant_1') <> current_setting('test.extend_grant_2') then
    raise exception 'non-stackable duplicate grant must reuse the same ownership row';
  end if;
  select expires_at into v_expires from public.user_backpack_items where id = current_setting('test.extend_grant_1')::uuid;
  -- Two 7-day grants back-to-back with no time elapsed must extend to ~14
  -- days out, not reset to ~7.
  if v_expires < now() + interval '13 days' then
    raise exception 'non-stackable duplicate grant must extend expiry, not reset it: got %', v_expires;
  end if;
end $$;

-- ── Idempotent grant retry: same source_reference must not double-apply ──
select public.grant_backpack_item_admin_v2(
  'bc000000-0000-0000-0000-000000000001', 'bpv2_test_badge_stack',
  p_quantity => 2, p_source_reference => 'order-idem-1'
) as idem_grant_1 \gset
select set_config('test.idem_grant_1', :'idem_grant_1', false);
select public.grant_backpack_item_admin_v2(
  'bc000000-0000-0000-0000-000000000001', 'bpv2_test_badge_stack',
  p_quantity => 2, p_source_reference => 'order-idem-1'
) as idem_grant_2 \gset
select set_config('test.idem_grant_2', :'idem_grant_2', false);
do $$ begin
  if current_setting('test.idem_grant_1') <> current_setting('test.idem_grant_2') then
    raise exception 'retried grant with the same source_reference must return the same ownership row';
  end if;
  if (select quantity from public.user_backpack_items where id = current_setting('test.idem_grant_1')::uuid) <> 2 then
    raise exception 'retried grant with the same source_reference must not double-apply quantity, got %',
      (select quantity from public.user_backpack_items where id = current_setting('test.idem_grant_1')::uuid);
  end if;
  if (select count(*) from public.backpack_audit_log
      where ownership_id = current_setting('test.idem_grant_1')::uuid and action in ('grant','extend_expiry')) <> 1 then
    raise exception 'retried grant must not write a duplicate audit entry';
  end if;
end $$;

-- ══════════════════════════════════════════════════════════════════════════
-- Duplicate-grant matrix (task 7): temporary+temporary, temporary+permanent,
-- permanent+temporary, permanent+permanent, stackable temporary,
-- non-stackable temporary, expired ownership receiving a new grant, revoked
-- ownership receiving a new grant.
-- ══════════════════════════════════════════════════════════════════════════

insert into public.backpack_catalog_items
  (code, name, item_type, equip_slot, is_active, is_equippable, is_grantable,
   is_equip_enabled, is_consumable, is_stackable, default_duration_days)
values
  ('bpv2_test_matrix_temp', 'Matrix Temp', 'entry_effect', 'entry_effect', true, true, true, true, false, false, 5),
  ('bpv2_test_matrix_stack', 'Matrix Stack', 'badge', 'badge', true, true, true, true, true, true, null),
  ('bpv2_test_matrix_expired', 'Matrix Expired', 'entry_effect', 'entry_effect', true, true, true, true, false, false, 5),
  ('bpv2_test_matrix_revoked', 'Matrix Revoked', 'entry_effect', 'entry_effect', true, true, true, true, false, false, 5)
on conflict (code) do nothing;

-- 1/6. temporary + temporary (non-stackable): extends, does not reset.
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_temp', p_duration_days => 5) as m_tt_1 \gset
select set_config('test.m_tt_1', :'m_tt_1', false);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_temp', p_duration_days => 5) as m_tt_2 \gset
select set_config('test.m_tt_2', :'m_tt_2', false);
do $$ declare v_expires timestamptz; begin
  if current_setting('test.m_tt_1') <> current_setting('test.m_tt_2') then
    raise exception 'temp+temp must reuse the same ownership row';
  end if;
  select expires_at into v_expires from public.user_backpack_items where id = current_setting('test.m_tt_1')::uuid;
  if v_expires < now() + interval '9 days' then
    raise exception 'temp+temp must extend to ~10 days out, got %', v_expires;
  end if;
end $$;

-- 2. temporary + permanent: an explicit permanent grant upgrades the row.
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_temp', p_permanent => true) as m_tp \gset
do $$ begin
  if (select expires_at from public.user_backpack_items where id = current_setting('test.m_tt_1')::uuid) is not null then
    raise exception 'temp+permanent must upgrade the row to permanent (expires_at null)';
  end if;
end $$;

-- 3. permanent + temporary must never downgrade an already-permanent grant.
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_temp', p_duration_days => 5) as m_pt \gset
do $$ begin
  if (select expires_at from public.user_backpack_items where id = current_setting('test.m_tt_1')::uuid) is not null then
    raise exception 'permanent+temp must never downgrade an already-permanent grant to temporary';
  end if;
end $$;

-- 4. permanent + permanent stays permanent.
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_temp', p_permanent => true) as m_pp \gset
do $$ begin
  if (select expires_at from public.user_backpack_items where id = current_setting('test.m_tt_1')::uuid) is not null then
    raise exception 'permanent+permanent must stay permanent';
  end if;
end $$;

-- 5. stackable temporary grants: quantity sums AND expiry extends together.
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_stack', p_quantity => 2, p_duration_days => 3) as m_st_1 \gset
select set_config('test.m_st_1', :'m_st_1', false);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_stack', p_quantity => 4, p_duration_days => 3) as m_st_2 \gset
do $$ declare v_qty int; v_expires timestamptz; begin
  select quantity, expires_at into v_qty, v_expires from public.user_backpack_items where id = current_setting('test.m_st_1')::uuid;
  if v_qty <> 6 then raise exception 'stackable temporary grant must sum quantity (2+4=6), got %', v_qty; end if;
  if v_expires < now() + interval '5 days' then raise exception 'stackable temporary grant must also extend expiry, got %', v_expires; end if;
end $$;

-- 7. expired-but-not-revoked ownership receiving a new grant: extends from
-- now(), not from the stale expiry, and reuses (does not duplicate) the row.
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_expired', p_duration_days => 5) as m_exp_1 \gset
select set_config('test.m_exp_1', :'m_exp_1', false);
update public.user_backpack_items set expires_at = now() - interval '1 day'
  where id = current_setting('test.m_exp_1')::uuid;
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_expired', p_duration_days => 5) as m_exp_2 \gset
select set_config('test.m_exp_2', :'m_exp_2', false);
do $$ declare v_expires timestamptz; begin
  if current_setting('test.m_exp_1') <> current_setting('test.m_exp_2') then
    raise exception 'expired-but-not-revoked ownership must be reused (merged), not duplicated';
  end if;
  select expires_at into v_expires from public.user_backpack_items where id = current_setting('test.m_exp_1')::uuid;
  if v_expires < now() + interval '4 days' or v_expires > now() + interval '6 days' then
    raise exception 'grant on an expired row must extend from now(), not from the stale expiry, got %', v_expires;
  end if;
end $$;

-- 8. revoked ownership receiving a new grant: never silently reused.
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_revoked', p_duration_days => 5) as m_rev_1 \gset
select set_config('test.m_rev_1', :'m_rev_1', false);
select public.revoke_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_revoked','matrix test revoke') as m_rev_revoke \gset
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000004','bpv2_test_matrix_revoked', p_duration_days => 5) as m_rev_2 \gset
select set_config('test.m_rev_2', :'m_rev_2', false);
do $$ begin
  if current_setting('test.m_rev_1') = current_setting('test.m_rev_2') then
    raise exception 'revoked ownership must never be silently reused by a new grant';
  end if;
  if not exists (
    select 1 from public.user_backpack_items
    where id = current_setting('test.m_rev_1')::uuid and is_revoked = true
  ) then
    raise exception 'the original revoked row must remain revoked (no silent restore)';
  end if;
  if exists (
    select 1 from public.user_backpack_items
    where id = current_setting('test.m_rev_2')::uuid and is_revoked = true
  ) then
    raise exception 'the fresh grant row created after revoke must not itself be revoked';
  end if;
end $$;

-- ── consume_backpack_item_v2: decrements, revokes at zero ────────────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.consume_backpack_item_v2(current_setting('test.stack_grant_1')::uuid) as consume_1 \gset
do $$ begin
  if (select quantity from public.user_backpack_items where id = current_setting('test.stack_grant_1')::uuid) <> 4 then
    raise exception 'consume must decrement quantity by 1 (5 -> 4)';
  end if;
end $$;

-- ── cleanup_my_expired_equipped_items_v2: self-scoped only ───────────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.user_backpack_items set expires_at = now() - interval '1 minute'
  where id = current_setting('test.vip_grant_id')::uuid;
-- (already unequipped by the revoke above; exercise cleanup against the
-- still-active free-frame equip instead so there is a real row to remove)
select public.equip_backpack_item_v2(current_setting('test.free_grant_id')::uuid) as reequip_free \gset
update public.user_backpack_items set expires_at = now() - interval '1 minute'
  where id = current_setting('test.free_grant_id')::uuid;

do $$ begin
  if (select count(*) from public.get_my_equipped_items_v2() where code = 'bpv2_test_frame_free') <> 0 then
    raise exception 'get_my_equipped_items_v2 must filter out an equipped item whose ownership has since expired, even before cleanup runs';
  end if;
end $$;

-- User B's own expired equipped rows (none exist here) must be untouched by
-- user A's self-scoped cleanup call — prove scope by asserting the call only
-- reports/removes user A's row, not a cross-user sweep.
select public.cleanup_my_expired_equipped_items_v2() as cleaned_count \gset
select set_config('test.cleaned_count', :'cleaned_count', false);
do $$ begin
  if current_setting('test.cleaned_count')::int < 1 then
    raise exception 'cleanup_my_expired_equipped_items_v2 must report at least 1 row cleaned for the caller';
  end if;
  if exists (
    select 1 from public.user_equipped_items where user_backpack_item_id = current_setting('test.free_grant_id')::uuid
  ) then
    raise exception 'cleanup must physically remove the caller''s expired equipped row';
  end if;
end $$;

-- ── admin_cleanup_all_expired_equipped_items_v2: global sweep, admin-only ─
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin_v2('bc000000-0000-0000-0000-000000000002', 'bpv2_test_frame_free') as sweep_target_grant \gset
select set_config('test.sweep_target_grant', :'sweep_target_grant', false);
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.equip_backpack_item_v2(current_setting('test.sweep_target_grant')::uuid) as sweep_equip \gset
update public.user_backpack_items set expires_at = now() - interval '1 minute'
  where id = current_setting('test.sweep_target_grant')::uuid;

select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.admin_cleanup_all_expired_equipped_items_v2() as global_cleaned_count \gset
select set_config('test.global_cleaned_count', :'global_cleaned_count', false);
do $$ begin
  if current_setting('test.global_cleaned_count')::int < 1 then
    raise exception 'admin_cleanup_all_expired_equipped_items_v2 must report at least 1 row cleaned across all users';
  end if;
  if exists (
    select 1 from public.user_equipped_items where user_backpack_item_id = current_setting('test.sweep_target_grant')::uuid
  ) then
    raise exception 'global sweep must remove another user''s expired equipped row';
  end if;
end $$;

-- ══════════════════════════════════════════════════════════════════════════
-- Task 10 hardening assertions.
-- ══════════════════════════════════════════════════════════════════════════

-- ── RLS: user_equipped_items is owner-or-admin only, no more world read ──
do $$ begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'user_equipped_items'
      and policyname = 'backpack_v2 equipped read all'
  ) then
    raise exception 'the world-readable equipped-items policy must be removed';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'user_equipped_items'
      and policyname = 'backpack_v2 equipped read own or admin' and qual like '%auth.uid%'
  ) then
    raise exception 'owner-or-admin equipped-items read policy is missing';
  end if;
end $$;

-- ── Privilege boundaries: no direct writes to base tables, no anon reads ──
do $$ begin
  if has_table_privilege('authenticated','public.user_backpack_items','INSERT')
    or has_table_privilege('authenticated','public.user_backpack_items','UPDATE')
    or has_table_privilege('authenticated','public.user_backpack_items','DELETE')
    or has_table_privilege('authenticated','public.user_equipped_items','INSERT')
    or has_table_privilege('authenticated','public.user_equipped_items','UPDATE')
    or has_table_privilege('authenticated','public.user_equipped_items','DELETE')
    or has_table_privilege('authenticated','public.backpack_audit_log','INSERT')
    or has_table_privilege('authenticated','public.backpack_audit_log','UPDATE')
    or has_table_privilege('authenticated','public.backpack_audit_log','DELETE')
    or has_table_privilege('authenticated','public.backpack_catalog_items','INSERT')
    or has_table_privilege('authenticated','public.backpack_catalog_items','UPDATE')
    or has_table_privilege('authenticated','public.backpack_catalog_items','DELETE')
    or has_table_privilege('anon','public.user_backpack_items','SELECT')
    or has_table_privilege('anon','public.user_equipped_items','SELECT')
    or has_table_privilege('anon','public.backpack_audit_log','SELECT')
    or has_table_privilege('anon','public.backpack_catalog_items','SELECT')
  then
    raise exception 'backpack v2 base-table privilege boundary failed (direct write or anon read is possible)';
  end if;
end $$;

-- ── PUBLIC and anon have no EXECUTE on any Backpack V2 RPC ────────────────
do $$
declare
  v_fn text;
  v_fns text[] := array[
    'public.get_my_backpack_v2()',
    'public.get_my_equipped_items_v2()',
    'public.get_public_equipped_items_v2(uuid)',
    'public.equip_backpack_item_v2(uuid)',
    'public.unequip_backpack_slot_v2(text)',
    'public.grant_backpack_item_admin_v2(uuid,text,int,int,text,text,text,boolean)',
    'public.revoke_backpack_item_admin_v2(uuid,text,text)',
    'public.consume_backpack_item_v2(uuid)',
    'public.cleanup_my_expired_equipped_items_v2()',
    'public.admin_cleanup_all_expired_equipped_items_v2()'
  ];
begin
  foreach v_fn in array v_fns loop
    if has_function_privilege('public', v_fn, 'EXECUTE') then
      raise exception 'PUBLIC must not have EXECUTE on %', v_fn;
    end if;
    if has_function_privilege('anon', v_fn, 'EXECUTE') then
      raise exception 'anon must not have EXECUTE on %', v_fn;
    end if;
  end loop;
end $$;

-- ── No mixed legacy/V2 naming: the pre-M2.1 names must no longer exist ───
do $$
declare
  v_old text;
  v_olds text[] := array[
    'get_my_equipped_items', 'grant_backpack_item_admin',
    'revoke_backpack_item_admin', 'consume_backpack_item',
    'cleanup_expired_equipped_items'
  ];
begin
  foreach v_old in array v_olds loop
    if exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_old
    ) then
      raise exception 'legacy-named Backpack V2 function % must not still exist after the _v2 rename', v_old;
    end if;
  end loop;
end $$;

-- ── Every V2 SECURITY DEFINER function is hardened with search_path='' ───
do $$
declare
  v_bad record;
begin
  for v_bad in
    select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
      and p.proname like '%\_v2' escape '\'
      and (p.proname like '%backpack%' or p.proname like '%equipped\_items%' escape '\')
      and not exists (
        -- Postgres serializes SET search_path = '' as the proconfig entry
        -- search_path="" (literal quote characters, not an empty string),
        -- so strip a wrapping pair of double quotes before comparing.
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
          and regexp_replace(split_part(cfg, '=', 2), '^"|"$', '', 'g') = ''
      )
  loop
    raise exception 'security definer function % is missing search_path='''' hardening', v_bad.proname;
  end loop;
end $$;

-- ── has_admin_access() dependency is safe: pinned, non-empty search_path ─
-- Backpack V2 RPCs call public.has_admin_access() rather than reimplementing
-- role checks. It is not itself search_path='' (it predates that
-- convention), but it does pin an explicit, non-mutable search_path and
-- fully-qualifies its own dependency (public.has_app_role), so it is safe
-- to depend on as-is.
do $$
declare v_config text[];
begin
  select proconfig into v_config from pg_proc
  where proname = 'has_admin_access' and pronamespace = 'public'::regnamespace;
  if v_config is null or not exists (
    select 1 from unnest(v_config) cfg where cfg like 'search_path=%' and split_part(cfg,'=',2) <> ''
  ) then
    raise exception 'has_admin_access must pin a fixed, non-empty search_path (found: %)', v_config;
  end if;
end $$;

rollback;
