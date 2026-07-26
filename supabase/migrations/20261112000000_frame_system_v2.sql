-- ============================================================================
-- FRAME SYSTEM V2 — catalog, ownership, selection, admin, legacy compat.
--
-- STRICTLY ADDITIVE. Nothing is dropped, renamed, or hard-deleted:
--   * public.avatar_frames, public.user_avatar_frames, profiles FK and every
--     legacy RPC keep working unchanged;
--   * v2 selection still writes profiles.selected_avatar_frame_key, so every
--     existing renderer keeps working;
--   * selection enforcement ships in LOG-ONLY mode (frame_settings_v2), so no
--     current user flow can break until enforcement is explicitly enabled.
-- Rollback: drop the *_v2 objects listed at the bottom of this file — no
-- legacy object is modified except additive rows in avatar_frames (vip_1..9).
-- ============================================================================

-- ── 1. Catalog ──────────────────────────────────────────────────────────────

create table if not exists public.frame_catalog (
  id uuid primary key default gen_random_uuid(),
  code text unique not null check (code ~ '^[a-z0-9_]+$'),
  name text not null,
  localized_names jsonb not null default '{}'::jsonb,
  category text not null default 'custom' check (category in (
    'vip','normal','luxury','admin','super_admin','agency_owner','host',
    'recharge_owner','room_owner','event','achievement','seasonal',
    'special_edition','purchased','reward','custom'
  )),
  vip_level int check (vip_level between 1 and 9),
  rarity text not null default 'common'
    check (rarity in ('common','rare','epic','legendary','mythic')),
  asset_type text not null default 'painter'
    check (asset_type in ('bundled','network','painter')),
  asset_url text,
  thumbnail_url text,
  animation_url text,
  is_animated boolean not null default false,
  is_active boolean not null default true,
  sort_order int not null default 0,
  unlock_type text not null default 'free' check (unlock_type in (
    'free','vip_level','role','level','purchase','reward','admin_grant','event'
  )),
  unlock_value text,
  required_role text,
  required_level int,
  required_vip_level int,
  starts_at timestamptz,
  expires_at timestamptz,
  legacy_frame_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists frame_catalog_active_sort_idx
  on public.frame_catalog (is_active, sort_order);
create index if not exists frame_catalog_category_idx
  on public.frame_catalog (category);
create index if not exists frame_catalog_legacy_key_idx
  on public.frame_catalog (legacy_frame_key);

alter table public.frame_catalog enable row level security;

drop policy if exists "frames_v2 catalog read active" on public.frame_catalog;
create policy "frames_v2 catalog read active"
  on public.frame_catalog for select to authenticated
  using (is_active = true or public.has_admin_access());

create or replace function public.frames_v2_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists frame_catalog_touch on public.frame_catalog;
create trigger frame_catalog_touch
  before update on public.frame_catalog
  for each row execute function public.frames_v2_touch_updated_at();

-- ── 2. Legacy key map ───────────────────────────────────────────────────────

create table if not exists public.frame_legacy_map (
  legacy_key text primary key,
  code text not null references public.frame_catalog(code) on update cascade,
  created_at timestamptz not null default now()
);

alter table public.frame_legacy_map enable row level security;

drop policy if exists "frames_v2 legacy map read" on public.frame_legacy_map;
create policy "frames_v2 legacy map read"
  on public.frame_legacy_map for select to authenticated using (true);

-- ── 3. Ownership ────────────────────────────────────────────────────────────

create table if not exists public.user_frames (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  frame_id uuid not null references public.frame_catalog(id),
  source text not null default 'admin_grant' check (source in (
    'purchase','reward','admin_grant','event','role','legacy_migration'
  )),
  granted_by uuid,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid,
  revoke_reason text
);

-- One ACTIVE ownership per (user, frame); revoked rows stay as history.
create unique index if not exists user_frames_active_unique
  on public.user_frames (user_id, frame_id) where revoked_at is null;
create index if not exists user_frames_user_idx
  on public.user_frames (user_id) where revoked_at is null;

alter table public.user_frames enable row level security;

drop policy if exists "frames_v2 ownership read own" on public.user_frames;
create policy "frames_v2 ownership read own"
  on public.user_frames for select to authenticated
  using (user_id = auth.uid() or public.has_admin_access());
-- No insert/update/delete policies: writes go through SECURITY DEFINER RPCs.

-- ── 4. Audit history ────────────────────────────────────────────────────────

create table if not exists public.frame_ownership_audit (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  frame_code text,
  action text not null check (action in (
    'grant','revoke','select','clear','migrate','violation'
  )),
  actor_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists frame_ownership_audit_user_idx
  on public.frame_ownership_audit (user_id, created_at desc);

alter table public.frame_ownership_audit enable row level security;

drop policy if exists "frames_v2 audit read" on public.frame_ownership_audit;
create policy "frames_v2 audit read"
  on public.frame_ownership_audit for select to authenticated
  using (user_id = auth.uid() or public.has_admin_access());

-- ── 5. Staged enforcement switch (log-only by default) ──────────────────────

create table if not exists public.frame_settings_v2 (
  id int primary key default 1 check (id = 1),
  enforce_selection boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.frame_settings_v2 (id) values (1) on conflict (id) do nothing;

alter table public.frame_settings_v2 enable row level security;
drop policy if exists "frames_v2 settings admin read" on public.frame_settings_v2;
create policy "frames_v2 settings admin read"
  on public.frame_settings_v2 for select to authenticated
  using (public.has_admin_access());

-- ── 6. Entitlement helpers ──────────────────────────────────────────────────

create or replace function public.frames_v2_effective_vip(p_user_id uuid)
returns int language sql stable security definer set search_path = public as $$
  select case
    when p.vip_level is null or p.vip_level <= 0 then 0
    when p.vip_expires_at is not null and p.vip_expires_at <= now() then 0
    else least(p.vip_level, 9)
  end
  from public.profiles p where p.id = p_user_id;
$$;

create or replace function public.frames_v2_resolve_code(p_raw text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select m.code from public.frame_legacy_map m where m.legacy_key = p_raw),
    p_raw
  );
$$;

-- Central business rule: may p_user_id WEAR frame p_raw right now?
-- Preserves current rules: normal/luxury are free; VIP tiers need an active
-- matching VIP level; role frames need the server-side role; everything else
-- needs an unexpired, unrevoked ownership row (v2 or legacy).
create or replace function public.frames_v2_user_can_use(
  p_user_id uuid,
  p_raw text
) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_code text := public.frames_v2_resolve_code(p_raw);
  v_frame public.frame_catalog%rowtype;
  v_legacy public.avatar_frames%rowtype;
begin
  if p_user_id is null then return false; end if;
  if p_raw is null or length(trim(p_raw)) = 0 then return true; end if;

  select * into v_frame from public.frame_catalog where code = v_code;

  if v_frame.id is null then
    -- Unknown to v2: fall back to legacy catalog semantics (normal/luxury
    -- frames are free today). Unknown everywhere → not allowed.
    select * into v_legacy from public.avatar_frames where frame_key = p_raw;
    if v_legacy.id is null then return false; end if;
    if v_legacy.category in ('normal','luxury') then return true; end if;
    return coalesce(v_legacy.required_vip_level, v_legacy.vip_level, 0)
      <= public.frames_v2_effective_vip(p_user_id);
  end if;

  if not v_frame.is_active then return false; end if;
  if v_frame.starts_at is not null and now() < v_frame.starts_at then
    return false;
  end if;
  if v_frame.expires_at is not null and now() >= v_frame.expires_at then
    return false;
  end if;

  -- Only vip_level-unlock frames are gated by required_vip_level. Role and
  -- admin_grant frames (custom_admin, custom_super_admin, custom_srood_live)
  -- inherit a non-null required_vip_level from their legacy avatar_frames
  -- vip_level column, but that column is not meaningful for their unlock
  -- semantics and must not block role/ownership-based access.
  if v_frame.unlock_type = 'vip_level'
     and v_frame.required_vip_level is not null
     and public.frames_v2_effective_vip(p_user_id) < v_frame.required_vip_level
  then
    return false;
  end if;

  if v_frame.required_role is not null then
    if not exists (
      select 1 from public.app_user_roles r
      where r.user_id = p_user_id and r.role = v_frame.required_role
    ) then
      return false;
    end if;
  end if;

  return case v_frame.unlock_type
    when 'free' then true
    when 'vip_level' then true   -- gated by required_vip_level above
    when 'role' then true        -- gated by required_role above
    else exists (
      -- v2 ownership …
      select 1 from public.user_frames uf
      where uf.user_id = p_user_id
        and uf.frame_id = v_frame.id
        and uf.revoked_at is null
        and (uf.expires_at is null or uf.expires_at > now())
      union all
      -- … or legacy ownership (kept valid until cleanup approval) …
      select 1 from public.user_avatar_frames uaf
      where uaf.user_id = p_user_id
        and (uaf.frame_key = p_raw or uaf.frame_key = v_code
             or uaf.frame_key = v_frame.legacy_frame_key)
        and (uaf.expires_at is null or uaf.expires_at > now())
      union all
      -- … or a gamification-store frame sitting in the backpack
      select 1 from public.backpack_items b
      where b.user_id = p_user_id
        and b.item_type = 'avatar_frame'
        and b.metadata->>'frame_key' in (p_raw, v_code)
    )
  end;
end $$;

-- ── 7. Selection guard trigger (LOG-ONLY until enforcement is enabled) ─────

create or replace function public.frames_v2_guard_selection()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_enforce boolean;
begin
  if new.selected_avatar_frame_key is null
     or new.selected_avatar_frame_key is not distinct from
        old.selected_avatar_frame_key
  then
    return new;
  end if;

  if public.frames_v2_user_can_use(new.id, new.selected_avatar_frame_key) then
    return new;
  end if;

  insert into public.frame_ownership_audit (user_id, frame_code, action, actor_id, details)
  values (
    new.id, new.selected_avatar_frame_key, 'violation', auth.uid(),
    jsonb_build_object('previous', old.selected_avatar_frame_key)
  );

  select enforce_selection into v_enforce from public.frame_settings_v2 where id = 1;
  if coalesce(v_enforce, false) then
    raise exception 'frame_not_allowed';
  end if;
  return new;
end $$;

drop trigger if exists frames_v2_guard_selection_trg on public.profiles;
create trigger frames_v2_guard_selection_trg
  before update of selected_avatar_frame_key on public.profiles
  for each row execute function public.frames_v2_guard_selection();

-- ── 8. User RPCs ────────────────────────────────────────────────────────────

create or replace function public.get_frame_catalog_v2()
returns setof public.frame_catalog
language sql stable security definer set search_path = public as $$
  select * from public.frame_catalog
  where is_active = true
    and (starts_at is null or starts_at <= now())
    and (expires_at is null or expires_at > now())
  order by sort_order, code;
$$;

create or replace function public.get_my_frames_v2()
returns table (
  code text, name text, category text, vip_level int,
  source text, expires_at timestamptz, is_equipped boolean, can_use boolean
) language sql stable security definer set search_path = public as $$
  select
    fc.code, fc.name, fc.category, fc.vip_level,
    uf.source, uf.expires_at,
    (p.selected_avatar_frame_key = fc.code
     or p.selected_avatar_frame_key = fc.legacy_frame_key) as is_equipped,
    public.frames_v2_user_can_use(auth.uid(), fc.code) as can_use
  from public.frame_catalog fc
  left join public.user_frames uf
    on uf.frame_id = fc.id and uf.user_id = auth.uid() and uf.revoked_at is null
  left join public.profiles p on p.id = auth.uid()
  where fc.is_active = true
    and (
      uf.id is not null
      or fc.unlock_type in ('free','vip_level','role')
    )
  order by fc.sort_order;
$$;

create or replace function public.select_my_frame_v2(p_code text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if p_code is null or length(trim(p_code)) = 0 then
    update public.profiles
      set selected_avatar_frame_key = null, updated_at = now()
      where id = v_uid;
    insert into public.frame_ownership_audit (user_id, action, actor_id)
      values (v_uid, 'clear', v_uid);
    return true;
  end if;

  v_code := public.frames_v2_resolve_code(trim(p_code));

  if not public.frames_v2_user_can_use(v_uid, v_code) then
    insert into public.frame_ownership_audit (user_id, frame_code, action, actor_id)
      values (v_uid, v_code, 'violation', v_uid);
    raise exception 'frame_not_allowed';
  end if;

  -- Selection pointer stays in the legacy column so every current renderer
  -- keeps working. All v2 catalog codes exist in avatar_frames (seeded
  -- below), so the legacy FK is always satisfied.
  update public.profiles
    set selected_avatar_frame_key = v_code, updated_at = now()
    where id = v_uid;

  insert into public.frame_ownership_audit (user_id, frame_code, action, actor_id)
    values (v_uid, v_code, 'select', v_uid);
  return true;
end $$;

-- ── 9. Admin RPCs (reuses has_admin_access + admin_audit_logs) ─────────────

create or replace function public.admin_upsert_frame_v2(
  p_code text, p_name text, p_category text,
  p_vip_level int default null,
  p_rarity text default 'common',
  p_asset_type text default 'painter',
  p_asset_url text default null,
  p_thumbnail_url text default null,
  p_animation_url text default null,
  p_is_animated boolean default false,
  p_is_active boolean default true,
  p_sort_order int default 0,
  p_unlock_type text default 'free',
  p_unlock_value text default null,
  p_required_role text default null,
  p_required_level int default null,
  p_required_vip_level int default null,
  p_starts_at timestamptz default null,
  p_expires_at timestamptz default null,
  p_localized_names jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not public.has_admin_access() then raise exception 'not_authorized'; end if;

  insert into public.frame_catalog (
    code, name, localized_names, category, vip_level, rarity, asset_type,
    asset_url, thumbnail_url, animation_url, is_animated, is_active,
    sort_order, unlock_type, unlock_value, required_role, required_level,
    required_vip_level, starts_at, expires_at
  ) values (
    p_code, p_name, coalesce(p_localized_names, '{}'::jsonb), p_category,
    p_vip_level, p_rarity, p_asset_type, p_asset_url, p_thumbnail_url,
    p_animation_url, p_is_animated, p_is_active, p_sort_order, p_unlock_type,
    p_unlock_value, p_required_role, p_required_level, p_required_vip_level,
    p_starts_at, p_expires_at
  )
  on conflict (code) do update set
    name = excluded.name,
    localized_names = excluded.localized_names,
    category = excluded.category,
    vip_level = excluded.vip_level,
    rarity = excluded.rarity,
    asset_type = excluded.asset_type,
    asset_url = excluded.asset_url,
    thumbnail_url = excluded.thumbnail_url,
    animation_url = excluded.animation_url,
    is_animated = excluded.is_animated,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    unlock_type = excluded.unlock_type,
    unlock_value = excluded.unlock_value,
    required_role = excluded.required_role,
    required_level = excluded.required_level,
    required_vip_level = excluded.required_vip_level,
    starts_at = excluded.starts_at,
    expires_at = excluded.expires_at
  returning id into v_id;

  -- Legacy FK compatibility: every selectable v2 code needs a row in
  -- avatar_frames (profiles.selected_avatar_frame_key FK). Additive upsert;
  -- legacy check constraint only allows normal/luxury/vip categories.
  insert into public.avatar_frames
    (frame_key, name, category, vip_level, required_vip_level, asset_url, is_active, sort_order)
  values (
    p_code, p_name,
    case when p_category in ('normal','luxury','vip') then p_category else 'luxury' end,
    p_vip_level, p_required_vip_level, p_asset_url, p_is_active, p_sort_order
  )
  on conflict (frame_key) do update set
    name = excluded.name,
    is_active = excluded.is_active,
    required_vip_level = excluded.required_vip_level,
    sort_order = excluded.sort_order;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'upsert_frame_v2', 'frame_catalog', p_code,
          jsonb_build_object('category', p_category, 'active', p_is_active));
  return v_id;
end $$;

create or replace function public.admin_assign_frame_v2(
  p_user_id uuid,
  p_code text,
  p_source text default 'admin_grant',
  p_expires_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_frame public.frame_catalog%rowtype;
  v_id uuid;
begin
  if not public.has_admin_access() then raise exception 'not_authorized'; end if;

  select * into v_frame
    from public.frame_catalog
    where code = public.frames_v2_resolve_code(p_code);
  if v_frame.id is null then raise exception 'frame_not_found'; end if;

  insert into public.user_frames (user_id, frame_id, source, granted_by, expires_at)
  values (p_user_id, v_frame.id, p_source, auth.uid(), p_expires_at)
  on conflict (user_id, frame_id) where revoked_at is null
  do update set expires_at = excluded.expires_at
  returning id into v_id;

  insert into public.frame_ownership_audit (user_id, frame_code, action, actor_id, details)
  values (p_user_id, v_frame.code, 'grant', auth.uid(),
          jsonb_build_object('source', p_source, 'expires_at', p_expires_at));
  insert into public.admin_audit_logs (admin_user_id, target_user_id, action, entity_type, entity_id)
  values (auth.uid(), p_user_id, 'assign_frame_v2', 'user_frames', v_frame.code);
  return v_id;
end $$;

create or replace function public.admin_revoke_frame_v2(
  p_user_id uuid,
  p_code text,
  p_reason text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_frame public.frame_catalog%rowtype;
begin
  if not public.has_admin_access() then raise exception 'not_authorized'; end if;

  select * into v_frame
    from public.frame_catalog
    where code = public.frames_v2_resolve_code(p_code);
  if v_frame.id is null then raise exception 'frame_not_found'; end if;

  update public.user_frames
    set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = p_reason
    where user_id = p_user_id and frame_id = v_frame.id and revoked_at is null;

  -- If the user is wearing it, take it off (falls back to implicit VIP frame
  -- client-side). Uses the same trigger-guarded column update as normal flow.
  update public.profiles
    set selected_avatar_frame_key = null, updated_at = now()
    where id = p_user_id
      and selected_avatar_frame_key in (v_frame.code, v_frame.legacy_frame_key);

  insert into public.frame_ownership_audit (user_id, frame_code, action, actor_id, details)
  values (p_user_id, v_frame.code, 'revoke', auth.uid(),
          jsonb_build_object('reason', p_reason));
  insert into public.admin_audit_logs (admin_user_id, target_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), p_user_id, 'revoke_frame_v2', 'user_frames', v_frame.code,
          jsonb_build_object('reason', p_reason));
  return true;
end $$;

create or replace function public.admin_frame_ownership_history_v2(
  p_user_id uuid default null,
  p_limit int default 200
) returns setof public.frame_ownership_audit
language sql stable security definer set search_path = public as $$
  select * from public.frame_ownership_audit
  where public.has_admin_access()
    and (p_user_id is null or user_id = p_user_id)
  order by created_at desc
  limit least(greatest(coalesce(p_limit, 200), 1), 1000);
$$;

create or replace function public.admin_set_frame_enforcement_v2(p_enforce boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.has_admin_access() then raise exception 'not_authorized'; end if;
  update public.frame_settings_v2 set enforce_selection = p_enforce, updated_at = now() where id = 1;
  insert into public.admin_audit_logs (admin_user_id, action, entity_type, metadata)
  values (auth.uid(), 'set_frame_enforcement_v2', 'frame_settings_v2',
          jsonb_build_object('enforce', p_enforce));
  return true;
end $$;

-- Migration status: how much of the legacy world maps into v2.
create or replace function public.frames_v2_migration_report()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.has_admin_access() then jsonb_build_object(
    'legacy_catalog_rows', (select count(*) from public.avatar_frames),
    'v2_catalog_rows', (select count(*) from public.frame_catalog),
    'legacy_keys_unmapped', (
      select coalesce(jsonb_agg(af.frame_key), '[]'::jsonb)
      from public.avatar_frames af
      where not exists (select 1 from public.frame_catalog fc
                        where fc.code = af.frame_key or fc.legacy_frame_key = af.frame_key)
        and not exists (select 1 from public.frame_legacy_map m
                        where m.legacy_key = af.frame_key)
    ),
    'selected_keys_unmapped', (
      select coalesce(jsonb_agg(distinct p.selected_avatar_frame_key), '[]'::jsonb)
      from public.profiles p
      where p.selected_avatar_frame_key is not null
        and not exists (select 1 from public.frame_catalog fc
                        where fc.code = p.selected_avatar_frame_key
                           or fc.legacy_frame_key = p.selected_avatar_frame_key)
        and not exists (select 1 from public.frame_legacy_map m
                        where m.legacy_key = p.selected_avatar_frame_key)
    ),
    'legacy_ownership_rows', (select count(*) from public.user_avatar_frames),
    'v2_ownership_rows', (select count(*) from public.user_frames),
    'enforcement_enabled', (select enforce_selection from public.frame_settings_v2 where id = 1)
  ) else null end;
$$;

-- ── 10. Seed: mirror legacy catalog into v2, add VIP tiers, map aliases ─────

-- 10a. Every existing avatar_frames row becomes a v2 catalog row (code =
--      legacy frame_key, so current selections resolve 1:1).
insert into public.frame_catalog (
  code, name, category, vip_level, rarity, asset_type, asset_url,
  is_active, sort_order, unlock_type, required_role, required_vip_level,
  legacy_frame_key
)
select
  af.frame_key,
  af.name,
  case af.frame_key
    when 'custom_admin' then 'admin'
    when 'custom_super_admin' then 'super_admin'
    when 'custom_srood_live' then 'special_edition'
    else af.category
  end,
  af.vip_level,
  case when af.category = 'vip' then 'rare'
       when af.category = 'luxury' then 'epic'
       else 'common' end,
  case when af.asset_url like 'assets/%' then 'bundled'
       when af.asset_url like 'http%' then 'network'
       else 'painter' end,
  af.asset_url,
  af.is_active,
  af.sort_order,
  case af.frame_key
    when 'custom_admin' then 'role'
    when 'custom_super_admin' then 'role'
    when 'custom_srood_live' then 'admin_grant'
    else case when af.category = 'vip' then 'vip_level' else 'free' end
  end,
  case af.frame_key
    when 'custom_admin' then 'admin'
    when 'custom_super_admin' then 'super_admin'
    else null
  end,
  coalesce(af.required_vip_level,
           case when af.category = 'vip' then af.vip_level end),
  af.frame_key
from public.avatar_frames af
on conflict (code) do nothing;

-- 10b. VIP tiers 1–9 as first-class v2 frames.
insert into public.frame_catalog (
  code, name, localized_names, category, vip_level, rarity, asset_type,
  asset_url, is_animated, sort_order, unlock_type, required_vip_level
)
select
  'vip_' || n,
  (array['Bronze Sentinel','Silver Meridian','Royal Aurum','Emerald Court',
         'Ruby Sovereign','Sapphire Regalia','Imperial Amethyst',
         'Black Diamond','Srood Mythic'])[n],
  jsonb_build_object('ar', 'إطار VIP ' || n),
  'vip', n,
  case when n >= 8 then 'mythic' when n >= 6 then 'legendary'
       when n >= 4 then 'epic' else 'rare' end,
  'bundled',
  'assets/images/vip_frames/' ||
    (array['11','2','3','vip4','5','6','7','88','99'])[n] || '.png',
  n >= 6,
  200 + n * 10,
  'vip_level', n
from generate_series(1, 9) as n
on conflict (code) do nothing;

-- 10c. Same VIP tier codes into the LEGACY catalog so the profiles FK
--      accepts them and the old picker/renderers can use them (additive
--      rows only — the sole change to a legacy table).
insert into public.avatar_frames
  (frame_key, name, category, vip_level, required_vip_level, is_active, sort_order)
select
  'vip_' || n,
  (array['Bronze Sentinel','Silver Meridian','Royal Aurum','Emerald Court',
         'Ruby Sovereign','Sapphire Regalia','Imperial Amethyst',
         'Black Diamond','Srood Mythic'])[n],
  'vip', n, n, true, 200 + n * 10
from generate_series(1, 9) as n
on conflict (frame_key) do nothing;

-- 10d. Alias map: legacy named VIP frames → v2 tier codes, painter aliases,
--      plus identity rows for every legacy key.
insert into public.frame_legacy_map (legacy_key, code) values
  ('vip_bronze_star', 'vip_1'),
  ('vip_silver_flame', 'vip_2'),
  ('vip_gold_crown', 'vip_3'),
  ('vip_platinum_diamond', 'vip_4'),
  ('vip_royal_king', 'vip_5'),
  ('vip_elite', 'vip_6'),
  ('vip_mythic', 'vip_7'),
  ('vip_emperor', 'vip_8'),
  ('vip_celestial', 'vip_9'),
  ('ruby_royal', 'luxury_ruby_royal'),
  ('ruby_royal_dark', 'luxury_ruby_royal_dark')
on conflict (legacy_key) do nothing;

insert into public.frame_legacy_map (legacy_key, code)
select af.frame_key, af.frame_key
from public.avatar_frames af
join public.frame_catalog fc on fc.code = af.frame_key
on conflict (legacy_key) do nothing;

-- 10e. Backfill ownership: copy legacy user_avatar_frames into user_frames
--      (source legacy_migration). Legacy rows are NOT modified or deleted.
insert into public.user_frames (user_id, frame_id, source, granted_at, expires_at)
select uaf.user_id, fc.id, 'legacy_migration', uaf.purchased_at, uaf.expires_at
from public.user_avatar_frames uaf
join public.frame_legacy_map m on m.legacy_key = uaf.frame_key
join public.frame_catalog fc on fc.code = m.code
on conflict (user_id, frame_id) where revoked_at is null do nothing;

insert into public.frame_ownership_audit (user_id, frame_code, action, details)
select uf.user_id, fc.code, 'migrate',
       jsonb_build_object('from', 'user_avatar_frames')
from public.user_frames uf
join public.frame_catalog fc on fc.id = uf.frame_id
where uf.source = 'legacy_migration'
  and not exists (
    select 1 from public.frame_ownership_audit a
    where a.user_id = uf.user_id
      and a.frame_code = fc.code
      and a.action = 'migrate'
  );

-- ── 11. Grants ──────────────────────────────────────────────────────────────

grant select on public.frame_catalog to authenticated;
grant select on public.frame_legacy_map to authenticated;
grant select on public.user_frames to authenticated;
grant select on public.frame_ownership_audit to authenticated;
grant select on public.frame_settings_v2 to authenticated;

revoke all on function public.get_frame_catalog_v2() from public;
revoke all on function public.get_my_frames_v2() from public;
revoke all on function public.select_my_frame_v2(text) from public;
revoke all on function public.frames_v2_user_can_use(uuid, text) from public;
revoke all on function public.frames_v2_effective_vip(uuid) from public;
revoke all on function public.frames_v2_resolve_code(text) from public;
revoke all on function public.admin_upsert_frame_v2(text, text, text, int, text, text, text, text, text, boolean, boolean, int, text, text, text, int, int, timestamptz, timestamptz, jsonb) from public;
revoke all on function public.admin_assign_frame_v2(uuid, text, text, timestamptz) from public;
revoke all on function public.admin_revoke_frame_v2(uuid, text, text) from public;
revoke all on function public.admin_frame_ownership_history_v2(uuid, int) from public;
revoke all on function public.admin_set_frame_enforcement_v2(boolean) from public;
revoke all on function public.frames_v2_migration_report() from public;

grant execute on function public.get_frame_catalog_v2() to authenticated;
grant execute on function public.get_my_frames_v2() to authenticated;
grant execute on function public.select_my_frame_v2(text) to authenticated;
grant execute on function public.admin_upsert_frame_v2(text, text, text, int, text, text, text, text, text, boolean, boolean, int, text, text, text, int, int, timestamptz, timestamptz, jsonb) to authenticated;
grant execute on function public.admin_assign_frame_v2(uuid, text, text, timestamptz) to authenticated;
grant execute on function public.admin_revoke_frame_v2(uuid, text, text) to authenticated;
grant execute on function public.admin_frame_ownership_history_v2(uuid, int) to authenticated;
grant execute on function public.admin_set_frame_enforcement_v2(boolean) to authenticated;
grant execute on function public.frames_v2_migration_report() to authenticated;

-- ── Rollback inventory (manual, requires explicit approval) ────────────────
-- drop trigger frames_v2_guard_selection_trg on public.profiles;
-- drop function frames_v2_guard_selection, select_my_frame_v2,
--   get_my_frames_v2, get_frame_catalog_v2, frames_v2_user_can_use,
--   frames_v2_effective_vip, frames_v2_resolve_code, admin_upsert_frame_v2,
--   admin_assign_frame_v2, admin_revoke_frame_v2,
--   admin_frame_ownership_history_v2, admin_set_frame_enforcement_v2,
--   frames_v2_migration_report, frames_v2_touch_updated_at;
-- drop table frame_ownership_audit, user_frames, frame_legacy_map,
--   frame_settings_v2, frame_catalog;
-- delete from avatar_frames where frame_key in ('vip_1'..'vip_9');  -- only
--   if no profile selects them (FK is ON DELETE SET NULL, so even this is safe).
