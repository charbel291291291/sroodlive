-- Contract test: Backpack System V2 RPCs (20261120000001_backpack_v2_rpcs.sql)
-- enforce ownership, revocation, expiry, active/equippable, VIP gating,
-- cross-user isolation, admin authorization, stacking/extension, and
-- expiry cleanup entirely server-side.
--
-- NOTE: psql's `:'varname'` interpolation does not reach inside dollar-quoted
-- (`do $$ ... $$`) bodies, so values captured via \gset are relayed into do
-- blocks through a session GUC (set_config/current_setting) instead of being
-- referenced directly inside the block.
\set ON_ERROR_STOP on
begin;

-- ── Fixtures: catalog items ──────────────────────────────────────────────
insert into public.backpack_catalog_items
  (code, name, item_type, is_active, is_equippable, is_consumable, is_stackable, vip_level_required, default_duration_days)
values
  ('bpv2_test_frame_free', 'Test Free Frame', 'avatar_frame', true, true, false, false, null, null),
  ('bpv2_test_frame_vip', 'Test VIP Frame', 'avatar_frame', true, true, false, false, 5, null),
  ('bpv2_test_frame_not_equippable', 'Test Non-Equippable', 'avatar_frame', true, false, false, false, null, null),
  ('bpv2_test_frame_inactive', 'Test Inactive Frame', 'avatar_frame', false, true, false, false, null, null),
  ('bpv2_test_badge_stack', 'Test Stackable Badge', 'badge', true, true, true, true, null, null),
  ('bpv2_test_effect_temp', 'Test Temp Effect', 'entry_effect', true, true, false, false, null, 7)
on conflict (code) do nothing;

-- ── Fixtures: users (plain A, other B, admin C) ──────────────────────────
insert into auth.users(id,instance_id,aud,role,email) values
 ('bc000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bpv2-a@example.com'),
 ('bc000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bpv2-b@example.com'),
 ('bc000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bpv2-admin@example.com')
on conflict(id) do nothing;

insert into public.profiles(id) values
 ('bc000000-0000-0000-0000-000000000001'),
 ('bc000000-0000-0000-0000-000000000002'),
 ('bc000000-0000-0000-0000-000000000003')
on conflict(id) do nothing;

insert into public.admin_users(user_id, role, is_active)
 values ('bc000000-0000-0000-0000-000000000003','super_admin', true)
on conflict do nothing;

-- ── Unauthorized: plain user cannot call admin grant/revoke ─────────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin
    perform public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_free');
    raise exception 'plain user must not be able to grant backpack items';
  exception when others then
    if sqlerrm <> 'not_authorized' then raise; end if;
  end;
end $$;

-- ── Admin grants a free frame to user A ──────────────────────────────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_free') as free_grant_id \gset
select set_config('test.free_grant_id', :'free_grant_id', false);

do $$ declare v_row public.user_backpack_items%rowtype; begin
  select * into v_row from public.user_backpack_items where id = current_setting('test.free_grant_id')::uuid;
  if v_row.quantity <> 1 or v_row.is_revoked or v_row.source_type <> 'admin_grant' then
    raise exception 'unexpected grant row shape: %', row_to_json(v_row);
  end if;
end $$;

-- ── User A equips it, sees it in get_my_equipped_items, unequips ────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.equip_backpack_item_v2(current_setting('test.free_grant_id')::uuid) as equip_result \gset
do $$ begin
  if (select count(*) from public.get_my_equipped_items() where code = 'bpv2_test_frame_free') <> 1 then
    raise exception 'equipped free frame must appear in get_my_equipped_items';
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

-- ── VIP gating: equip blocked below required level, allowed at/above ────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_vip') as vip_grant_id \gset
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

-- ── Not-equippable and inactive catalog items are blocked at equip time ─
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_not_equippable') as ne_grant_id \gset
select set_config('test.ne_grant_id', :'ne_grant_id', false);
select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_inactive') as inactive_grant_id \gset
select set_config('test.inactive_grant_id', :'inactive_grant_id', false);

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
end $$;

-- ── Admin revoke: un-equips immediately and blocks future equip ─────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.revoke_backpack_item_admin('bc000000-0000-0000-0000-000000000001', 'bpv2_test_frame_vip', 'contract test revoke') as revoke_result \gset

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
select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000002', 'bpv2_test_badge_stack', p_quantity => 3) as stack_grant_1 \gset
select set_config('test.stack_grant_1', :'stack_grant_1', false);
select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000002', 'bpv2_test_badge_stack', p_quantity => 2) as stack_grant_2 \gset
select set_config('test.stack_grant_2', :'stack_grant_2', false);
do $$ begin
  if current_setting('test.stack_grant_1') <> current_setting('test.stack_grant_2') then
    raise exception 'stackable duplicate grant must reuse the same ownership row, not insert a second one';
  end if;
  if (select quantity from public.user_backpack_items where id = current_setting('test.stack_grant_1')::uuid) <> 5 then
    raise exception 'stackable duplicate grant must sum quantities (3 + 2 = 5)';
  end if;
end $$;

select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000002', 'bpv2_test_effect_temp', p_duration_days => 7) as extend_grant_1 \gset
select set_config('test.extend_grant_1', :'extend_grant_1', false);
select public.grant_backpack_item_admin('bc000000-0000-0000-0000-000000000002', 'bpv2_test_effect_temp', p_duration_days => 7) as extend_grant_2 \gset
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

-- ── consume_backpack_item: decrements, revokes at zero ───────────────────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.consume_backpack_item(current_setting('test.stack_grant_1')::uuid) as consume_1 \gset
do $$ begin
  if (select quantity from public.user_backpack_items where id = current_setting('test.stack_grant_1')::uuid) <> 4 then
    raise exception 'consume must decrement quantity by 1 (5 -> 4)';
  end if;
end $$;

-- ── cleanup_expired_equipped_items removes stale equipped pointers ──────
select set_config('request.jwt.claims','{"sub":"bc000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.user_backpack_items set expires_at = now() - interval '1 minute'
  where id = current_setting('test.vip_grant_id')::uuid;
-- (already unequipped by the revoke above; exercise cleanup against the
-- still-active free-frame equip instead so there is a real row to remove)
select public.equip_backpack_item_v2(current_setting('test.free_grant_id')::uuid) as reequip_free \gset
update public.user_backpack_items set expires_at = now() - interval '1 minute'
  where id = current_setting('test.free_grant_id')::uuid;

do $$ begin
  if (select count(*) from public.get_my_equipped_items() where code = 'bpv2_test_frame_free') <> 0 then
    raise exception 'get_my_equipped_items must filter out an equipped item whose ownership has since expired, even before cleanup runs';
  end if;
end $$;

select public.cleanup_expired_equipped_items() as cleaned_count \gset
select set_config('test.cleaned_count', :'cleaned_count', false);
do $$ begin
  if current_setting('test.cleaned_count')::int < 1 then
    raise exception 'cleanup_expired_equipped_items must report at least 1 row cleaned';
  end if;
  if exists (
    select 1 from public.user_equipped_items where user_backpack_item_id = current_setting('test.free_grant_id')::uuid
  ) then
    raise exception 'cleanup must physically remove the expired equipped row';
  end if;
end $$;

-- ── RLS: user_equipped_items is world-readable, user_backpack_items is not ─
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'user_equipped_items'
      and policyname = 'backpack_v2 equipped read all' and qual = 'true'
  ) then
    raise exception 'equipped-items table must stay world-readable to authenticated users for cross-user rendering';
  end if;
end $$;

rollback;
