-- ─────────────────────────────────────────────────────────────────────────────
-- Standardize VIP system to levels 1–9 only.
-- VIP 9 is permanently removed. Any level-10 record is remapped to level 9.
-- All check constraints are tightened to 0–9 (profiles) or 1–9 (plans/packages).
-- All affected RPCs are updated to clamp at 9.
-- Migration is idempotent.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Remap any existing VIP 9 users to VIP 9 ────────────────────────────

update public.profiles
set vip_level = 9
where vip_level > 9;

-- ── 2. Tighten profiles check constraint ───────────────────────────────────

alter table public.profiles
  drop constraint if exists profiles_vip_level_range;

alter table public.profiles
  add constraint profiles_vip_level_range
  check (vip_level between 0 and 9);

-- ── 3. Remove VIP 9 from vip_packages, tighten constraint ────────────────

delete from public.vip_packages where vip_level > 9;

alter table public.vip_packages
  drop constraint if exists vip_packages_vip_level_check;

alter table public.vip_packages
  add constraint vip_packages_vip_level_check
  check (vip_level between 1 and 9);

-- ── 4. Remove VIP 9 from vip_plans, tighten constraint ───────────────────

delete from public.vip_plans where level > 9;

alter table public.vip_plans
  drop constraint if exists vip_plans_level_check;

alter table public.vip_plans
  add constraint vip_plans_level_check
  check (level between 1 and 9);

-- ── 5. Remove VIP 9 entrance banners, tighten constraint ─────────────────

delete from public.entrance_banners where vip_level > 9;

alter table public.entrance_banners
  drop constraint if exists entrance_banners_vip_level_check;

alter table public.entrance_banners
  add constraint entrance_banners_vip_level_check
  check (vip_level is null or vip_level between 1 and 9);

-- ── 6. Remap avatar frames and badges above 9 ──────────────────────────────

update public.avatar_frames
  set required_vip_level = 9
  where required_vip_level > 9;

update public.badges
  set required_vip_level = 9
  where required_vip_level is not null and required_vip_level > 9;

alter table public.badges
  drop constraint if exists badges_required_vip_level_check;

alter table public.badges
  add constraint badges_required_vip_level_check
  check (required_vip_level is null or required_vip_level between 1 and 9);

-- ── 7. Update admin_grant_vip — clamp level to 9 ───────────────────────────

create or replace function public.admin_grant_vip(
  p_user_id uuid,
  p_vip_level integer,
  p_days integer default 30,
  p_title text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level integer := greatest(0, least(coalesce(p_vip_level, 0), 9));
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('support_admin')) then
    raise exception 'not_authorized';
  end if;

  update public.profiles
  set vip_level = v_level,
      vip_started_at = case when v_level > 0 then now() else null end,
      vip_expires_at = case
        when v_level > 0 then now() + make_interval(days => greatest(coalesce(p_days, 30), 1))
        else null
      end,
      vip_title = nullif(trim(coalesce(p_title, '')), '')
  where id = p_user_id;

  perform public.admin_record_audit(
    'grant_vip',
    'profiles',
    p_user_id::text,
    p_user_id,
    jsonb_build_object('vip_level', v_level, 'days', p_days, 'title', p_title)
  );
end;
$$;

-- ── 8. Update admin_update_vip_package — clamp level to 9 ──────────────────

create or replace function public.admin_update_vip_package(
  p_vip_level integer,
  p_code text,
  p_name text,
  p_arabic_name text default null,
  p_price_coins integer default 0,
  p_duration_days integer default 30,
  p_badge_label text default null,
  p_entrance_banner_key text default null,
  p_is_active boolean default true,
  p_sort_order integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_level integer := greatest(1, least(coalesce(p_vip_level, 1), 9));
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('content_admin')) then
    raise exception 'not_authorized';
  end if;

  insert into public.vip_packages (
    vip_level, code, name, arabic_name, price_coins, duration_days,
    badge_label, entrance_banner_key, is_active, sort_order, updated_at
  )
  values (
    v_level,
    lower(trim(p_code)),
    trim(p_name),
    nullif(trim(coalesce(p_arabic_name, '')), ''),
    greatest(coalesce(p_price_coins, 0), 0),
    greatest(coalesce(p_duration_days, 30), 1),
    nullif(trim(coalesce(p_badge_label, '')), ''),
    nullif(trim(coalesce(p_entrance_banner_key, '')), ''),
    coalesce(p_is_active, true),
    coalesce(p_sort_order, 0),
    now()
  )
  on conflict (vip_level) do update set
    code = excluded.code,
    name = excluded.name,
    arabic_name = excluded.arabic_name,
    price_coins = excluded.price_coins,
    duration_days = excluded.duration_days,
    badge_label = excluded.badge_label,
    entrance_banner_key = excluded.entrance_banner_key,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    updated_at = now()
  returning id into v_id;

  perform public.admin_record_audit(
    'update_vip_package',
    'vip_packages',
    v_level::text,
    null,
    jsonb_build_object('vip_level', v_level, 'price_coins', p_price_coins)
  );

  return v_id;
end;
$$;

-- ── 9. Ensure entrance banners 1–9 remain active ───────────────────────────

update public.entrance_banners
  set is_active = true
  where vip_level between 1 and 9;

