-- Startup Promo / Launch Interstitial
-- Full-screen promotional image shown once on app open.

create table if not exists public.startup_promos (
  id               uuid        primary key default gen_random_uuid(),
  title            text        not null,
  image_url        text        not null,
  storage_path     text,
  is_active        boolean     not null default false,
  starts_at        timestamptz,
  ends_at          timestamptz,
  duration_seconds int         not null default 5,
  frequency        text        not null default 'once_per_day',
  priority         int         not null default 0,
  created_by       uuid        references auth.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table public.startup_promos enable row level security;

-- Users can read active, non-expired promos.
drop policy if exists "startup_promos_select_active" on public.startup_promos;
create policy "startup_promos_select_active"
  on public.startup_promos for select to authenticated
  using (
    is_active = true
    and (starts_at is null or starts_at <= now())
    and (ends_at   is null or ends_at   >  now())
  );

-- Admins can read all promos (for the dashboard).
drop policy if exists "startup_promos_select_admin" on public.startup_promos;
create policy "startup_promos_select_admin"
  on public.startup_promos for select to authenticated
  using (public.has_admin_access());

drop policy if exists "startup_promos_insert" on public.startup_promos;
create policy "startup_promos_insert"
  on public.startup_promos for insert to authenticated
  with check (public.has_admin_access());

drop policy if exists "startup_promos_update" on public.startup_promos;
create policy "startup_promos_update"
  on public.startup_promos for update to authenticated
  using (public.has_admin_access());

drop policy if exists "startup_promos_delete" on public.startup_promos;
create policy "startup_promos_delete"
  on public.startup_promos for delete to authenticated
  using (public.has_admin_access());

grant select, insert, update, delete on public.startup_promos to authenticated;

-- ── RPC: get_active_startup_promo ──────────────────────────────────────────
-- Returns the single highest-priority active promo (safe for regular users).

drop function if exists public.get_active_startup_promo();
create or replace function public.get_active_startup_promo()
returns table (
  id               uuid,
  title            text,
  image_url        text,
  duration_seconds int,
  frequency        text,
  priority         int,
  updated_at       timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    id,
    title,
    image_url,
    duration_seconds,
    frequency,
    priority,
    updated_at
  from public.startup_promos
  where
    is_active = true
    and (starts_at is null or starts_at <= now())
    and (ends_at   is null or ends_at   >  now())
    and image_url is not null
    and image_url <> ''
  order by priority desc, created_at desc
  limit 1;
$$;

grant execute on function public.get_active_startup_promo() to authenticated;

-- ── RPC: admin_list_startup_promos ─────────────────────────────────────────
drop function if exists public.admin_list_startup_promos();
create or replace function public.admin_list_startup_promos()
returns setof public.startup_promos
language sql
security definer
set search_path = public
stable
as $$
  select * from public.startup_promos
  order by priority desc, created_at desc;
$$;

grant execute on function public.admin_list_startup_promos() to authenticated;

-- ── RPC: admin_save_startup_promo ──────────────────────────────────────────
drop function if exists public.admin_save_startup_promo(uuid, text, text, text, boolean, timestamptz, timestamptz, int, text, int);
create or replace function public.admin_save_startup_promo(
  p_id               uuid        default null,
  p_title            text        default null,
  p_image_url        text        default null,
  p_storage_path     text        default null,
  p_is_active        boolean     default false,
  p_starts_at        timestamptz default null,
  p_ends_at          timestamptz default null,
  p_duration_seconds int         default 5,
  p_frequency        text        default 'once_per_day',
  p_priority         int         default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_actor uuid := auth.uid();
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  if p_id is not null then
    update public.startup_promos
    set
      title            = coalesce(p_title, title),
      image_url        = coalesce(p_image_url, image_url),
      storage_path     = coalesce(p_storage_path, storage_path),
      is_active        = p_is_active,
      starts_at        = p_starts_at,
      ends_at          = p_ends_at,
      duration_seconds = p_duration_seconds,
      frequency        = p_frequency,
      priority         = p_priority,
      updated_at       = now()
    where id = p_id
    returning id into v_id;
  else
    insert into public.startup_promos (
      title, image_url, storage_path, is_active,
      starts_at, ends_at, duration_seconds, frequency, priority, created_by
    ) values (
      p_title, p_image_url, p_storage_path, p_is_active,
      p_starts_at, p_ends_at, p_duration_seconds, p_frequency, p_priority, v_actor
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

grant execute on function public.admin_save_startup_promo(uuid, text, text, text, boolean, timestamptz, timestamptz, int, text, int) to authenticated;

-- ── RPC: admin_delete_startup_promo ────────────────────────────────────────
drop function if exists public.admin_delete_startup_promo(uuid);
create or replace function public.admin_delete_startup_promo(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;
  delete from public.startup_promos where id = p_id;
end;
$$;

grant execute on function public.admin_delete_startup_promo(uuid) to authenticated;
