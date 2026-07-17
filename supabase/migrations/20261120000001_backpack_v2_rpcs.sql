-- ============================================================================
-- BACKPACK SYSTEM V2 — RPCs (Phase 3 required set).
--
-- STRICTLY ADDITIVE, hardened per the task's explicit requirement:
--   * every function uses `set search_path = ''` with fully-qualified
--     `public.`/`auth.` references (a deliberate departure from this repo's
--     prevailing `set search_path = public` convention seen in
--     frame_system_v2.sql — matches the one function in this codebase that
--     already does this correctly, admin_record_audit).
--   * every function is REVOKEd from PUBLIC then GRANTed only to
--     `authenticated`; admin-only functions still grant to `authenticated`
--     and gate internally via has_admin_access() (same pattern as
--     admin_assign_frame_v2/admin_revoke_frame_v2) — there is no
--     service_role-only convention elsewhere in this repo to diverge from.
--   * equip/consume/grant/revoke never trust a client-supplied user id for
--     "who am I" — only auth.uid(). Admin RPCs take an explicit p_user_id
--     target (that's the point of an admin action) but every admin RPC
--     re-checks has_admin_access() itself, server-side, before touching it.
--   * VIP gating reuses the existing frames_v2_effective_vip() resolver
--     (frame_system_v2.sql) rather than inventing a second VIP-level query —
--     it is already the canonical "effective VIP right now" source of truth
--     app-wide (accounts for vip_expires_at).
--   * equip/unequip route slot_type from the catalog item's own item_type
--     (which shares the exact enum with slot_type by construction), so a
--     caller cannot mismatch an item into the wrong slot — there is no
--     client-supplied slot parameter to equip at all.
--
-- Named `*_v2` on equip/unequip specifically to avoid colliding with the
-- existing legacy `public.equip_backpack_item(uuid)` RPC, which continues
-- to operate on the legacy `public.backpack_items` table untouched.
--
-- Scope note: this migration implements exactly the 8 RPCs named in the
-- task's Phase 3 spec (get_my_backpack, get_my_equipped_items,
-- equip_backpack_item[_v2], unequip_backpack_slot[_v2],
-- grant_backpack_item_admin, revoke_backpack_item_admin,
-- consume_backpack_item, cleanup_expired_equipped_items).
--
-- get_my_backpack is also named `*_v2` (get_my_backpack_v2) for the same
-- reason as equip/unequip: `public.get_my_backpack()` already exists
-- (20261030000000_gamification_read_contract.sql, legacy backpack_items/
-- store_items shape) with a different return type, and `create or replace`
-- cannot change an existing function's return type. get_my_equipped_items
-- has no such collision and keeps its plain name.
-- grant_backpack_item_admin already implements "extend" as its repeat-grant
-- behavior (non-stackable → extend expires_at, stackable → add quantity),
-- so no separate "extend" RPC is needed. "restore" (un-revoke) and the rest
-- of the Phase 8 admin CRUD surface are deliberately deferred to the M7
-- admin-surface milestone — out of scope for this schema+RPC checkpoint.
-- ============================================================================

-- ── 1. get_my_backpack_v2 — caller's own active (non-revoked) ownership ────

create or replace function public.get_my_backpack_v2()
returns table (
  ownership_id uuid,
  item_id uuid,
  code text,
  name text,
  name_ar text,
  name_fr text,
  item_type text,
  rarity text,
  asset_key text,
  preview_asset_key text,
  quantity int,
  source_type text,
  acquired_at timestamptz,
  expires_at timestamptz,
  is_equippable boolean,
  is_consumable boolean,
  is_stackable boolean,
  is_expired boolean,
  metadata jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    ubi.id, ubi.item_id, bci.code, bci.name, bci.name_ar, bci.name_fr,
    bci.item_type, bci.rarity, bci.asset_key, bci.preview_asset_key,
    ubi.quantity, ubi.source_type, ubi.acquired_at, ubi.expires_at,
    bci.is_equippable, bci.is_consumable, bci.is_stackable,
    (ubi.expires_at is not null and ubi.expires_at <= now()) as is_expired,
    ubi.metadata
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.user_id = auth.uid() and ubi.is_revoked = false
  order by bci.item_type, bci.sort_order, ubi.acquired_at desc;
$$;

-- ── 2. get_my_equipped_items — caller's own equipped slots ─────────────────
-- Expiry/revocation is re-checked here on every read (WHERE filter), so
-- rendering correctness never depends solely on cleanup_expired_equipped_items
-- having run.

create or replace function public.get_my_equipped_items()
returns table (
  slot_type text,
  ownership_id uuid,
  item_id uuid,
  code text,
  name text,
  name_ar text,
  name_fr text,
  rarity text,
  asset_key text,
  preview_asset_key text,
  equipped_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    uei.slot_type, ubi.id, bci.id, bci.code, bci.name, bci.name_ar, bci.name_fr,
    bci.rarity, bci.asset_key, bci.preview_asset_key, uei.equipped_at, ubi.expires_at
  from public.user_equipped_items uei
  join public.user_backpack_items ubi on ubi.id = uei.user_backpack_item_id
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where uei.user_id = auth.uid()
    and ubi.is_revoked = false
    and (ubi.expires_at is null or ubi.expires_at > now())
    and bci.is_active = true
  order by uei.slot_type;
$$;

-- ── 3. equip_backpack_item_v2 ───────────────────────────────────────────────

create or replace function public.equip_backpack_item_v2(p_user_backpack_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row record;
  v_effective_vip int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select
    ubi.id as ownership_id, ubi.is_revoked, ubi.expires_at,
    bci.id as catalog_id, bci.item_type, bci.is_active, bci.is_equippable,
    bci.vip_level_required, bci.code
  into v_row
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.id = p_user_backpack_item_id and ubi.user_id = v_uid;

  if not found then
    -- Covers both "doesn't exist" and "belongs to someone else": cross-user
    -- ownership is never revealed by a different error.
    raise exception 'backpack_item_not_found' using errcode = 'P0002';
  end if;

  if v_row.is_revoked then
    raise exception 'item_revoked' using errcode = '22023';
  end if;

  if v_row.expires_at is not null and v_row.expires_at <= now() then
    raise exception 'item_expired' using errcode = '22023';
  end if;

  if not v_row.is_active then
    raise exception 'item_not_active' using errcode = '22023';
  end if;

  if not v_row.is_equippable then
    raise exception 'item_not_equippable' using errcode = '22023';
  end if;

  if v_row.vip_level_required is not null then
    v_effective_vip := public.frames_v2_effective_vip(v_uid);
    if v_effective_vip < v_row.vip_level_required then
      raise exception 'vip_level_required' using errcode = '22023';
    end if;
  end if;

  -- Slot is the item's own type, not a client-supplied value — one row per
  -- (user, slot) is enforced by the table's primary key.
  insert into public.user_equipped_items (user_id, slot_type, user_backpack_item_id, equipped_at, updated_at)
  values (v_uid, v_row.item_type, p_user_backpack_item_id, now(), now())
  on conflict (user_id, slot_type) do update
    set user_backpack_item_id = excluded.user_backpack_item_id,
        equipped_at = now(),
        updated_at = now();

  insert into public.backpack_audit_log (actor_user_id, target_user_id, action, item_id, ownership_id, after_state)
  values (v_uid, v_uid, 'equip', v_row.catalog_id, p_user_backpack_item_id,
          jsonb_build_object('slot_type', v_row.item_type, 'code', v_row.code));

  return jsonb_build_object('equipped', true, 'slot_type', v_row.item_type, 'code', v_row.code);
end;
$$;

-- ── 4. unequip_backpack_slot_v2 ─────────────────────────────────────────────

create or replace function public.unequip_backpack_slot_v2(p_slot_type text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ownership_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_slot_type is null or p_slot_type not in (
    'avatar_frame', 'profile_frame', 'entry_effect', 'badge', 'name_color',
    'room_background', 'chat_effect', 'mic_effect', 'vehicle'
  ) then
    raise exception 'invalid_slot_type' using errcode = '22023';
  end if;

  delete from public.user_equipped_items
    where user_id = v_uid and slot_type = p_slot_type
    returning user_backpack_item_id into v_ownership_id;

  if v_ownership_id is null then
    return false;
  end if;

  insert into public.backpack_audit_log (actor_user_id, target_user_id, action, ownership_id)
  values (v_uid, v_uid, 'unequip', v_ownership_id);

  return true;
end;
$$;

-- ── 5. grant_backpack_item_admin ────────────────────────────────────────────
-- Duplicate-grant rule: non-stackable items extend expires_at (adds the new
-- duration on top of remaining time, or from now() if already expired;
-- permanent items with no duration stay permanent). Stackable/consumable
-- items increment quantity instead of touching expiry.

create or replace function public.grant_backpack_item_admin(
  p_user_id uuid,
  p_code text,
  p_quantity int default 1,
  p_duration_days int default null,
  p_source_type text default 'admin_grant',
  p_reason text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_catalog public.backpack_catalog_items%rowtype;
  v_existing public.user_backpack_items%rowtype;
  v_had_existing boolean;
  v_duration_days int;
  v_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  if p_user_id is null then
    raise exception 'invalid_target_user' using errcode = '22023';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity' using errcode = '22023';
  end if;

  if p_source_type not in ('purchase', 'admin_grant', 'event_reward', 'vip_reward', 'legacy_migration') then
    raise exception 'invalid_source_type' using errcode = '22023';
  end if;

  select * into v_catalog from public.backpack_catalog_items where code = p_code;
  if not found then
    raise exception 'catalog_item_not_found' using errcode = 'P0002';
  end if;
  -- Deliberately not gated on is_active: an admin may grant a retired/
  -- limited catalog item (e.g. as a reward or legacy-migration backfill).
  -- is_active is enforced at equip time instead, which is the actual
  -- security boundary for what a user can wear.

  v_duration_days := coalesce(p_duration_days, v_catalog.default_duration_days);

  select * into v_existing
    from public.user_backpack_items
    where user_id = p_user_id and item_id = v_catalog.id and is_revoked = false;
  v_had_existing := found;

  if v_had_existing then
    v_before := to_jsonb(v_existing);

    if v_catalog.is_stackable then
      update public.user_backpack_items
        set quantity = quantity + p_quantity,
            expires_at = case
              when v_duration_days is null then expires_at
              when expires_at is null then expires_at
              when expires_at <= now() then now() + make_interval(days => v_duration_days)
              else expires_at + make_interval(days => v_duration_days)
            end
        where id = v_existing.id
        returning id into v_id;
    else
      update public.user_backpack_items
        set expires_at = case
              when v_duration_days is null then expires_at
              when expires_at is null then expires_at
              when expires_at <= now() then now() + make_interval(days => v_duration_days)
              else expires_at + make_interval(days => v_duration_days)
            end
        where id = v_existing.id
        returning id into v_id;
    end if;
  else
    insert into public.user_backpack_items (
      user_id, item_id, quantity, source_type, source_reference, expires_at
    ) values (
      p_user_id, v_catalog.id, p_quantity, p_source_type, p_reason,
      case when v_duration_days is null then null else now() + make_interval(days => v_duration_days) end
    )
    returning id into v_id;
  end if;

  select to_jsonb(ubi) into v_after from public.user_backpack_items ubi where ubi.id = v_id;

  insert into public.backpack_audit_log (
    actor_user_id, target_user_id, action, item_id, ownership_id, before_state, after_state, reason
  ) values (
    auth.uid(), p_user_id,
    case when v_had_existing then 'extend_expiry' else 'grant' end,
    v_catalog.id, v_id, v_before, v_after, p_reason
  );

  insert into public.admin_audit_logs (admin_user_id, target_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), p_user_id, 'grant_backpack_item', 'user_backpack_items', v_catalog.code,
          jsonb_build_object('quantity', p_quantity, 'duration_days', v_duration_days, 'reason', p_reason));

  return v_id;
end;
$$;

-- ── 6. revoke_backpack_item_admin ───────────────────────────────────────────

create or replace function public.revoke_backpack_item_admin(
  p_user_id uuid,
  p_code text,
  p_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_catalog public.backpack_catalog_items%rowtype;
  v_ownership public.user_backpack_items%rowtype;
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select * into v_catalog from public.backpack_catalog_items where code = p_code;
  if not found then
    raise exception 'catalog_item_not_found' using errcode = 'P0002';
  end if;

  select * into v_ownership
    from public.user_backpack_items
    where user_id = p_user_id and item_id = v_catalog.id and is_revoked = false;
  if not found then
    raise exception 'ownership_not_found' using errcode = 'P0002';
  end if;

  update public.user_backpack_items
    set is_revoked = true, revoked_at = now(), revoked_reason = p_reason
    where id = v_ownership.id;

  -- ON DELETE CASCADE on user_backpack_item_id only fires on row DELETE, not
  -- this UPDATE — a revoked-but-equipped item must be unequipped explicitly
  -- so it stops rendering immediately rather than waiting on cleanup.
  delete from public.user_equipped_items
    where user_backpack_item_id = v_ownership.id;

  insert into public.backpack_audit_log (
    actor_user_id, target_user_id, action, item_id, ownership_id, before_state, reason
  ) values (
    auth.uid(), p_user_id, 'revoke', v_catalog.id, v_ownership.id, to_jsonb(v_ownership), p_reason
  );

  insert into public.admin_audit_logs (admin_user_id, target_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), p_user_id, 'revoke_backpack_item', 'user_backpack_items', v_catalog.code,
          jsonb_build_object('reason', p_reason));

  return true;
end;
$$;

-- ── 7. consume_backpack_item ────────────────────────────────────────────────

create or replace function public.consume_backpack_item(p_user_backpack_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row record;
  v_new_qty int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select
    ubi.id, ubi.quantity, ubi.is_revoked, ubi.expires_at,
    bci.id as catalog_id, bci.is_consumable
  into v_row
  from public.user_backpack_items ubi
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where ubi.id = p_user_backpack_item_id and ubi.user_id = v_uid;

  if not found then
    raise exception 'backpack_item_not_found' using errcode = 'P0002';
  end if;

  if not v_row.is_consumable then
    raise exception 'item_not_consumable' using errcode = '22023';
  end if;

  if v_row.is_revoked then
    raise exception 'item_revoked' using errcode = '22023';
  end if;

  if v_row.expires_at is not null and v_row.expires_at <= now() then
    raise exception 'item_expired' using errcode = '22023';
  end if;

  v_new_qty := v_row.quantity - 1;

  if v_new_qty <= 0 then
    update public.user_backpack_items
      set is_revoked = true, revoked_at = now(), revoked_reason = 'consumed'
      where id = v_row.id;
    delete from public.user_equipped_items where user_backpack_item_id = v_row.id;
  else
    update public.user_backpack_items set quantity = v_new_qty where id = v_row.id;
  end if;

  insert into public.backpack_audit_log (actor_user_id, target_user_id, action, item_id, ownership_id, after_state)
  values (v_uid, v_uid, 'consume', v_row.catalog_id, v_row.id,
          jsonb_build_object('remaining_quantity', greatest(v_new_qty, 0)));

  return jsonb_build_object('consumed', true, 'remaining_quantity', greatest(v_new_qty, 0));
end;
$$;

-- ── 8. cleanup_expired_equipped_items ───────────────────────────────────────
-- No pg_cron on this project — callable opportunistically by any
-- authenticated client (e.g. on backpack-open) rather than a scheduled job.
-- Purely hygiene: get_my_equipped_items already filters expired/revoked rows
-- on every read regardless of whether this has run, so correctness never
-- depends on it.

create or replace function public.cleanup_expired_equipped_items()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  with stale as (
    delete from public.user_equipped_items uei
    using public.user_backpack_items ubi
    where uei.user_backpack_item_id = ubi.id
      and (ubi.is_revoked = true or (ubi.expires_at is not null and ubi.expires_at <= now()))
    returning uei.user_id, uei.slot_type, uei.user_backpack_item_id
  )
  insert into public.backpack_audit_log (actor_user_id, target_user_id, action, ownership_id, after_state)
  select auth.uid(), stale.user_id, 'cleanup_expired', stale.user_backpack_item_id,
         jsonb_build_object('slot_type', stale.slot_type)
  from stale;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ── 9. Grants ────────────────────────────────────────────────────────────────

revoke all on function public.get_my_backpack_v2() from public;
revoke all on function public.get_my_equipped_items() from public;
revoke all on function public.equip_backpack_item_v2(uuid) from public;
revoke all on function public.unequip_backpack_slot_v2(text) from public;
revoke all on function public.grant_backpack_item_admin(uuid, text, int, int, text, text) from public;
revoke all on function public.revoke_backpack_item_admin(uuid, text, text) from public;
revoke all on function public.consume_backpack_item(uuid) from public;
revoke all on function public.cleanup_expired_equipped_items() from public;

grant execute on function public.get_my_backpack_v2() to authenticated;
grant execute on function public.get_my_equipped_items() to authenticated;
grant execute on function public.equip_backpack_item_v2(uuid) to authenticated;
grant execute on function public.unequip_backpack_slot_v2(text) to authenticated;
grant execute on function public.grant_backpack_item_admin(uuid, text, int, int, text, text) to authenticated;
grant execute on function public.revoke_backpack_item_admin(uuid, text, text) to authenticated;
grant execute on function public.consume_backpack_item(uuid) to authenticated;
grant execute on function public.cleanup_expired_equipped_items() to authenticated;

-- ── Rollback inventory (manual, requires explicit approval) ────────────────
-- drop function public.get_my_backpack_v2();
-- drop function public.get_my_equipped_items();
-- drop function public.equip_backpack_item_v2(uuid);
-- drop function public.unequip_backpack_slot_v2(text);
-- drop function public.grant_backpack_item_admin(uuid, text, int, int, text, text);
-- drop function public.revoke_backpack_item_admin(uuid, text, text);
-- drop function public.consume_backpack_item(uuid);
-- drop function public.cleanup_expired_equipped_items();
-- No legacy function is modified by this migration, so no legacy rollback is
-- required.
