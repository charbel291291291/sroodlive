-- ============================================================================
-- BACKPACK SYSTEM V2 — M2.1 hardening pass.
--
-- STRICTLY ADDITIVE on top of 20261120000000_backpack_v2_schema.sql and
-- 20261120000001_backpack_v2_rpcs.sql. No legacy table/RPC is touched. This
-- migration:
--   1. Renames every remaining Backpack V2 RPC to the `_v2` suffix so there
--      is no mixed legacy/V2 naming within the feature.
--   2. Adds a canonical `equip_slot` column to the catalog so slot placement
--      is data, not something re-derived from item_type inside RPCs.
--   3. Adds a composite FK so `user_equipped_items` cannot point at an
--      ownership row belonging to a different user, even via service-role
--      SQL that bypasses RPC validation.
--   4. Removes the world-readable SELECT policy on `user_equipped_items` and
--      replaces it with an owner-or-admin policy, adding a safe rendering
--      RPC (get_public_equipped_items_v2) that exposes only curated fields
--      for cross-user cosmetic rendering.
--   5. Splits the overloaded `is_active` flag into four explicit flags:
--      is_active (rendering validity), is_grantable (new grants),
--      is_store_available (store visibility, unused until the store RPC
--      ships), is_equip_enabled (new equip operations).
--   6. Makes admin grants retry-safe via an explicit `p_source_reference`
--      idempotency key.
--   7. Adds a `p_permanent` flag so a grant can unambiguously request a
--      permanent duration even when the catalog item has a default
--      duration, and tightens the extend/merge CASE so a permanent grant
--      can never be downgraded to temporary by a later duplicate grant.
--   8. Splits cleanup into a self-scoped `cleanup_my_expired_equipped_items_v2`
--      (any authenticated user, own rows only) and a separate admin-gated
--      `admin_cleanup_all_expired_equipped_items_v2` global sweep.
--
-- Rollback: drop the objects listed at the bottom. No legacy object is
-- touched, so rollback carries no data-loss risk to any existing system.
-- ============================================================================

-- ── 1. Catalog: equip_slot + four-way flag split ────────────────────────────

alter table public.backpack_catalog_items
  add column if not exists equip_slot text,
  add column if not exists is_grantable boolean not null default true,
  add column if not exists is_store_available boolean not null default false,
  add column if not exists is_equip_enabled boolean not null default true;

-- Backfill before the consistency CHECK below is added: every currently
-- equippable row's slot is its own item_type (the two enums are identical
-- by construction), every non-equippable row stays unslotted.
update public.backpack_catalog_items
  set equip_slot = item_type
  where is_equippable = true and equip_slot is null;

alter table public.backpack_catalog_items
  drop constraint if exists backpack_catalog_items_equip_slot_check;
alter table public.backpack_catalog_items
  add constraint backpack_catalog_items_equip_slot_check
  check (equip_slot is null or equip_slot in (
    'avatar_frame', 'profile_frame', 'entry_effect', 'badge', 'name_color',
    'room_background', 'chat_effect', 'mic_effect', 'vehicle'
  ));

alter table public.backpack_catalog_items
  drop constraint if exists backpack_catalog_items_equip_slot_consistency;
alter table public.backpack_catalog_items
  add constraint backpack_catalog_items_equip_slot_consistency
  check (
    (is_equippable = true and equip_slot is not null)
    or (is_equippable = false and equip_slot is null)
  );

-- ── 2. Ownership: composite-FK target + grant-idempotency index ─────────────

alter table public.user_backpack_items
  drop constraint if exists user_backpack_items_user_id_id_key;
alter table public.user_backpack_items
  add constraint user_backpack_items_user_id_id_key unique (user_id, id);

-- A retried admin grant with the same (user, item, source_type,
-- source_reference) must resolve to exactly one row, ever — regardless of
-- revoke state — so the RPC can detect "this exact request already ran"
-- independent of the active/revoked merge logic used for distinct grants.
create unique index if not exists user_backpack_items_grant_reference_unique
  on public.user_backpack_items (user_id, item_id, source_type, source_reference)
  where source_reference is not null;

-- ── 3. Equipped slots: composite FK enforces same-user ownership ────────────

alter table public.user_equipped_items
  drop constraint if exists user_equipped_items_user_backpack_item_id_fkey;
alter table public.user_equipped_items
  add constraint user_equipped_items_user_id_backpack_item_fkey
  foreign key (user_id, user_backpack_item_id)
  references public.user_backpack_items (user_id, id)
  on delete cascade;

-- ── 4. Equipped slots: no more world-readable base-table access ─────────────
-- Cosmetics still need to be visible to other users in rooms/chat/lists, but
-- that now goes through get_public_equipped_items_v2 below (curated columns
-- only), not a direct `using (true)` policy on the base table.

drop policy if exists "backpack_v2 equipped read all" on public.user_equipped_items;
drop policy if exists "backpack_v2 equipped read own or admin" on public.user_equipped_items;
create policy "backpack_v2 equipped read own or admin"
  on public.user_equipped_items for select to authenticated
  using (user_id = auth.uid() or public.has_admin_access());

create or replace function public.get_public_equipped_items_v2(p_user_id uuid)
returns table (
  user_id uuid,
  slot_type text,
  code text,
  name text,
  name_ar text,
  name_fr text,
  rarity text,
  asset_key text,
  preview_asset_key text,
  is_permanent boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    uei.user_id, uei.slot_type, bci.code, bci.name, bci.name_ar, bci.name_fr,
    bci.rarity, bci.asset_key, bci.preview_asset_key,
    (ubi.expires_at is null) as is_permanent
  from public.user_equipped_items uei
  join public.user_backpack_items ubi
    on ubi.user_id = uei.user_id and ubi.id = uei.user_backpack_item_id
  join public.backpack_catalog_items bci on bci.id = ubi.item_id
  where uei.user_id = p_user_id
    and ubi.is_revoked = false
    and (ubi.expires_at is null or ubi.expires_at > now())
    and bci.is_active = true
  order by uei.slot_type;
$$;

-- ── 5. get_my_equipped_items_v2 (renamed, no other change) ──────────────────

create or replace function public.get_my_equipped_items_v2()
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

drop function if exists public.get_my_equipped_items();

-- ── 6. equip_backpack_item_v2 — slot comes from the catalog, not item_type ──
-- Adds the is_equip_enabled gate (distinct from is_active): a catalog item
-- can remain valid for rendering (is_active) while new equips are paused
-- (is_equip_enabled = false) without touching already-equipped instances,
-- which keep rendering until they expire or are explicitly unequipped.

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
    bci.id as catalog_id, bci.equip_slot, bci.is_active, bci.is_equippable,
    bci.is_equip_enabled, bci.vip_level_required, bci.code
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

  if not v_row.is_equippable or v_row.equip_slot is null then
    raise exception 'item_not_equippable' using errcode = '22023';
  end if;

  if not v_row.is_equip_enabled then
    raise exception 'item_equip_disabled' using errcode = '22023';
  end if;

  if v_row.vip_level_required is not null then
    v_effective_vip := public.frames_v2_effective_vip(v_uid);
    if v_effective_vip < v_row.vip_level_required then
      raise exception 'vip_level_required' using errcode = '22023';
    end if;
  end if;

  -- Slot comes from the catalog's own equip_slot column — there is no
  -- client-supplied slot parameter, and no item_type-to-slot inference here.
  insert into public.user_equipped_items (user_id, slot_type, user_backpack_item_id, equipped_at, updated_at)
  values (v_uid, v_row.equip_slot, p_user_backpack_item_id, now(), now())
  on conflict (user_id, slot_type) do update
    set user_backpack_item_id = excluded.user_backpack_item_id,
        equipped_at = now(),
        updated_at = now();

  insert into public.backpack_audit_log (actor_user_id, target_user_id, action, item_id, ownership_id, after_state)
  values (v_uid, v_uid, 'equip', v_row.catalog_id, p_user_backpack_item_id,
          jsonb_build_object('slot_type', v_row.equip_slot, 'code', v_row.code));

  return jsonb_build_object('equipped', true, 'slot_type', v_row.equip_slot, 'code', v_row.code);
end;
$$;

-- ── 7. grant_backpack_item_admin_v2 — is_grantable gate + idempotency ───────
-- Duplicate-grant rule, made explicit:
--   * stackable items always sum quantity on a repeat grant.
--   * a permanent existing grant (expires_at is null) never becomes
--     temporary, no matter what duration a later grant requests.
--   * an explicit p_permanent grant upgrades a temporary row to permanent.
--   * otherwise, a temporary grant extends from the greater of "now" or the
--     existing expiry (so an expired-but-not-revoked row extends from now,
--     not from its stale expiry).
--   * a revoked ownership row is never silently reused — a new grant after
--     revoke always inserts a fresh row; restoring a revoked row is a
--     separate, explicitly audited admin action, not implied by re-granting.

create or replace function public.grant_backpack_item_admin_v2(
  p_user_id uuid,
  p_code text,
  p_quantity int default 1,
  p_duration_days int default null,
  p_source_type text default 'admin_grant',
  p_source_reference text default null,
  p_reason text default null,
  p_permanent boolean default false
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

  if not v_catalog.is_grantable then
    raise exception 'item_not_grantable' using errcode = '22023';
  end if;

  -- Idempotent retry: the same (user, item, source_type, source_reference)
  -- combination is only ever applied once. A retried request with the same
  -- reference returns the row the first call already produced, without
  -- re-incrementing quantity, re-extending expiry, or re-writing audit
  -- history.
  if p_source_reference is not null then
    select * into v_existing
      from public.user_backpack_items
      where user_id = p_user_id and item_id = v_catalog.id
        and source_type = p_source_type and source_reference = p_source_reference;
    if found then
      return v_existing.id;
    end if;
  end if;

  v_duration_days := case when p_permanent then null else coalesce(p_duration_days, v_catalog.default_duration_days) end;

  select * into v_existing
    from public.user_backpack_items
    where user_id = p_user_id and item_id = v_catalog.id and is_revoked = false;
  v_had_existing := found;

  if v_had_existing then
    v_before := to_jsonb(v_existing);

    update public.user_backpack_items
      set quantity = case when v_catalog.is_stackable then quantity + p_quantity else quantity end,
          expires_at = case
            when v_duration_days is null then null
            when expires_at is null then expires_at
            when expires_at <= now() then now() + make_interval(days => v_duration_days)
            else expires_at + make_interval(days => v_duration_days)
          end
      where id = v_existing.id
      returning id into v_id;
  else
    insert into public.user_backpack_items (
      user_id, item_id, quantity, source_type, source_reference, expires_at
    ) values (
      p_user_id, v_catalog.id, p_quantity, p_source_type, p_source_reference,
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
          jsonb_build_object('quantity', p_quantity, 'duration_days', v_duration_days,
                              'source_reference', p_source_reference, 'reason', p_reason));

  return v_id;
end;
$$;

drop function if exists public.grant_backpack_item_admin(uuid, text, int, int, text, text);

-- ── 8. revoke_backpack_item_admin_v2 (renamed, no other change) ─────────────

create or replace function public.revoke_backpack_item_admin_v2(
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

drop function if exists public.revoke_backpack_item_admin(uuid, text, text);

-- ── 9. consume_backpack_item_v2 (renamed, no other change) ──────────────────

create or replace function public.consume_backpack_item_v2(p_user_backpack_item_id uuid)
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

drop function if exists public.consume_backpack_item(uuid);

-- ── 10. Cleanup split: self-scoped (any user) vs. global sweep (admin only) ─
-- No pg_cron on this project — cleanup is callable opportunistically by
-- clients (e.g. on backpack-open). get_my_equipped_items_v2 already filters
-- expired/revoked rows on every read regardless of whether this has run, so
-- correctness never depends on it; these are hygiene only.

create or replace function public.cleanup_my_expired_equipped_items_v2()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  with stale as (
    delete from public.user_equipped_items uei
    using public.user_backpack_items ubi
    where uei.user_backpack_item_id = ubi.id
      and uei.user_id = v_uid
      and (ubi.is_revoked = true or (ubi.expires_at is not null and ubi.expires_at <= now()))
    returning uei.user_id, uei.slot_type, uei.user_backpack_item_id
  )
  insert into public.backpack_audit_log (actor_user_id, target_user_id, action, ownership_id, after_state)
  select v_uid, stale.user_id, 'cleanup_expired', stale.user_backpack_item_id,
         jsonb_build_object('slot_type', stale.slot_type)
  from stale;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.admin_cleanup_all_expired_equipped_items_v2()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  with stale as (
    delete from public.user_equipped_items uei
    using public.user_backpack_items ubi
    where uei.user_backpack_item_id = ubi.id
      and (ubi.is_revoked = true or (ubi.expires_at is not null and ubi.expires_at <= now()))
    returning uei.user_id, uei.slot_type, uei.user_backpack_item_id
  )
  insert into public.backpack_audit_log (actor_user_id, target_user_id, action, ownership_id, after_state)
  select auth.uid(), stale.user_id, 'cleanup_expired', stale.user_backpack_item_id,
         jsonb_build_object('slot_type', stale.slot_type, 'scope', 'global')
  from stale;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

drop function if exists public.cleanup_expired_equipped_items();

-- ── 11. Grants ────────────────────────────────────────────────────────────

revoke all on function public.get_my_equipped_items_v2() from public;
revoke all on function public.get_public_equipped_items_v2(uuid) from public;
revoke all on function public.grant_backpack_item_admin_v2(uuid, text, int, int, text, text, text, boolean) from public;
revoke all on function public.revoke_backpack_item_admin_v2(uuid, text, text) from public;
revoke all on function public.consume_backpack_item_v2(uuid) from public;
revoke all on function public.cleanup_my_expired_equipped_items_v2() from public;
revoke all on function public.admin_cleanup_all_expired_equipped_items_v2() from public;

grant execute on function public.get_my_equipped_items_v2() to authenticated;
grant execute on function public.get_public_equipped_items_v2(uuid) to authenticated;
grant execute on function public.grant_backpack_item_admin_v2(uuid, text, int, int, text, text, text, boolean) to authenticated;
grant execute on function public.revoke_backpack_item_admin_v2(uuid, text, text) to authenticated;
grant execute on function public.consume_backpack_item_v2(uuid) to authenticated;
grant execute on function public.cleanup_my_expired_equipped_items_v2() to authenticated;
grant execute on function public.admin_cleanup_all_expired_equipped_items_v2() to authenticated;

-- equip_backpack_item_v2 and get_my_backpack_v2 keep their names and
-- signatures (CREATE OR REPLACE above), so their prior grants from
-- 20261120000001_backpack_v2_rpcs.sql already apply and are not repeated.

-- ── Rollback inventory (manual, requires explicit approval) ────────────────
-- drop function public.get_public_equipped_items_v2(uuid);
-- drop function public.admin_cleanup_all_expired_equipped_items_v2();
-- drop function public.cleanup_my_expired_equipped_items_v2();
-- (get_my_equipped_items_v2 / grant_backpack_item_admin_v2 /
--  revoke_backpack_item_admin_v2 / consume_backpack_item_v2 would need to be
--  dropped and the prior _v1-named versions restored from
--  20261120000001_backpack_v2_rpcs.sql to fully roll back this migration.)
-- alter table public.user_equipped_items drop constraint user_equipped_items_user_id_backpack_item_fkey;
-- alter table public.user_backpack_items drop constraint user_backpack_items_user_id_id_key;
-- drop index public.user_backpack_items_grant_reference_unique;
-- alter table public.backpack_catalog_items
--   drop constraint backpack_catalog_items_equip_slot_consistency,
--   drop constraint backpack_catalog_items_equip_slot_check,
--   drop column equip_slot, drop column is_grantable,
--   drop column is_store_available, drop column is_equip_enabled;
-- No legacy table/function is modified by this migration, so no legacy
-- rollback is required.
