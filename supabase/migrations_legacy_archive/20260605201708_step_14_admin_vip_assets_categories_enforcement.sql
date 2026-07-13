alter table public.profiles
add column if not exists is_golden_id boolean not null default false,
add column if not exists golden_id_expires_at timestamptz null;

alter table public.gifts
add column if not exists category text not null default 'hot',
add column if not exists required_vip_level integer not null default 0,
add column if not exists animation_url text null,
add column if not exists is_featured boolean not null default false;

alter table public.avatar_frames
add column if not exists required_vip_level integer,
add column if not exists is_featured boolean not null default false;

update public.avatar_frames
set required_vip_level = vip_level
where required_vip_level is null
  and vip_level is not null;

create table if not exists public.vip_packages (
  id uuid primary key default gen_random_uuid(),
  vip_level integer not null unique check (vip_level between 1 and 5),
  code text not null unique,
  name text not null,
  arabic_name text null,
  price_coins integer not null default 0 check (price_coins >= 0),
  duration_days integer not null default 30 check (duration_days > 0),
  badge_label text null,
  entrance_banner_key text null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.entrance_banners (
  id uuid primary key default gen_random_uuid(),
  banner_key text not null unique,
  name text not null,
  arabic_name text null,
  vip_level integer null check (vip_level between 1 and 5),
  asset_url text null,
  gradient_start text null,
  gradient_end text null,
  message_template text null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gift_categories (
  id uuid primary key default gen_random_uuid(),
  category_key text not null unique,
  name text not null,
  arabic_name text null,
  icon text null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_user_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  note text not null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.vip_packages enable row level security;
alter table public.entrance_banners enable row level security;
alter table public.gift_categories enable row level security;
alter table public.admin_user_notes enable row level security;

drop policy if exists "Admins can view vip packages" on public.vip_packages;
create policy "Admins can view vip packages"
on public.vip_packages for select to authenticated
using (public.has_admin_access());

drop policy if exists "Admins can view entrance banners" on public.entrance_banners;
create policy "Admins can view entrance banners"
on public.entrance_banners for select to authenticated
using (public.has_admin_access());

drop policy if exists "Admins can view gift categories" on public.gift_categories;
create policy "Admins can view gift categories"
on public.gift_categories for select to authenticated
using (public.has_admin_access());

drop policy if exists "Admins can view user notes" on public.admin_user_notes;
create policy "Admins can view user notes"
on public.admin_user_notes for select to authenticated
using (public.has_admin_access());

grant select on public.vip_packages to authenticated;
grant select on public.entrance_banners to authenticated;
grant select on public.gift_categories to authenticated;
grant select on public.admin_user_notes to authenticated;

insert into public.gift_categories (
  category_key,
  name,
  arabic_name,
  icon,
  is_active,
  sort_order
)
values
  ('event', 'Event', 'ÙØ¹Ø§Ù„ÙŠØ§Øª', 'event', true, 10),
  ('hot', 'Hot', 'Ø§Ù„Ø£ÙƒØ«Ø± Ø±ÙˆØ§Ø¬Ø§Ù‹', 'local_fire_department', true, 20),
  ('lucky', 'Lucky', 'Ø§Ù„Ø­Ø¸', 'casino', true, 30),
  ('vip', 'VIP', 'VIP', 'workspace_premium', true, 40)
on conflict (category_key) do update set
  name = excluded.name,
  arabic_name = excluded.arabic_name,
  icon = excluded.icon,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.entrance_banners (
  banner_key,
  name,
  arabic_name,
  vip_level,
  gradient_start,
  gradient_end,
  message_template,
  is_active,
  sort_order
)
values
  ('vip_1_gold', 'VIP Gold Entry', 'Ø¯Ø®ÙˆÙ„ Ø°Ù‡Ø¨ÙŠ', 1, '#3A2408', '#DDAA3B', '{name} entered with VIP shine', true, 10),
  ('vip_2_flame', 'VIP Flame Entry', 'Ø¯Ø®ÙˆÙ„ Ù†Ø§Ø±ÙŠ', 2, '#401018', '#FF6F7E', '{name} entered with flame energy', true, 20),
  ('vip_3_royal', 'VIP Royal Entry', 'Ø¯Ø®ÙˆÙ„ Ù…Ù„ÙƒÙŠ', 3, '#2A1042', '#8B26D9', '{name} entered like royalty', true, 30),
  ('vip_4_diamond', 'VIP Diamond Entry', 'Ø¯Ø®ÙˆÙ„ Ø£Ù„Ù…Ø§Ø³ÙŠ', 4, '#0D2B3A', '#4CC9F0', '{name} entered silently', true, 40),
  ('vip_5_king', 'VIP King Entry', 'Ø¯Ø®ÙˆÙ„ Ø§Ù„Ù…Ù„Ùƒ', 5, '#31000B', '#FFD15C', '{name} entered with royal power', true, 50)
on conflict (banner_key) do update set
  name = excluded.name,
  arabic_name = excluded.arabic_name,
  vip_level = excluded.vip_level,
  gradient_start = excluded.gradient_start,
  gradient_end = excluded.gradient_end,
  message_template = excluded.message_template,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.vip_packages (
  vip_level,
  code,
  name,
  arabic_name,
  price_coins,
  duration_days,
  badge_label,
  entrance_banner_key,
  is_active,
  sort_order
)
values
  (1, 'vip_1_bronze', 'VIP 1 Bronze', 'VIP 1 Ø¨Ø±ÙˆÙ†Ø²ÙŠ', 1000, 30, 'VIP 1', 'vip_1_gold', true, 10),
  (2, 'vip_2_silver', 'VIP 2 Silver', 'VIP 2 ÙØ¶ÙŠ', 3000, 30, 'VIP 2', 'vip_2_flame', true, 20),
  (3, 'vip_3_gold', 'VIP 3 Gold', 'VIP 3 Ø°Ù‡Ø¨ÙŠ', 8000, 30, 'VIP 3', 'vip_3_royal', true, 30),
  (4, 'vip_4_diamond', 'VIP 4 Diamond', 'VIP 4 Ø£Ù„Ù…Ø§Ø³ÙŠ', 18000, 30, 'VIP 4', 'vip_4_diamond', true, 40),
  (5, 'vip_5_royal', 'VIP 5 Royal King', 'VIP 5 Ù…Ù„ÙƒÙŠ', 40000, 30, 'VIP 5', 'vip_5_king', true, 50)
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
  updated_at = now();

create or replace function public.user_has_active_restriction(
  p_restriction_type text,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_user_restrictions r
    where r.user_id = coalesce(p_user_id, auth.uid())
      and r.restriction_type = lower(trim(p_restriction_type))
      and r.is_active
      and (r.expires_at is null or r.expires_at > now())
  );
$$;

create or replace function public.admin_set_user_golden_id(
  p_user_id uuid,
  p_public_user_id text,
  p_is_golden boolean default true,
  p_expires_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_app_role('super_admin') then
    raise exception 'not_authorized';
  end if;

  update public.profiles
  set public_user_id = nullif(trim(coalesce(p_public_user_id, public_user_id)), ''),
      is_golden_id = coalesce(p_is_golden, true),
      golden_id_expires_at = p_expires_at
  where id = p_user_id;

  perform public.admin_record_audit(
    'set_golden_id',
    'profiles',
    p_user_id::text,
    p_user_id,
    jsonb_build_object('public_user_id', p_public_user_id, 'is_golden_id', p_is_golden)
  );
end;
$$;

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
  v_level integer := greatest(0, least(coalesce(p_vip_level, 0), 5));
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('support_admin')) then
    raise exception 'not_authorized';
  end if;

  update public.profiles
  set vip_level = v_level,
      vip_started_at = case when v_level > 0 then now() else null end,
      vip_expires_at = case when v_level > 0 then now() + make_interval(days => greatest(coalesce(p_days, 30), 1)) else null end,
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

create or replace function public.admin_list_avatar_frames(
  p_limit integer default 200
)
returns table (
  id uuid,
  frame_key text,
  name text,
  category text,
  vip_level integer,
  required_vip_level integer,
  asset_url text,
  is_active boolean,
  is_featured boolean,
  sort_order integer,
  usage_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    af.id,
    af.frame_key,
    af.name,
    af.category,
    af.vip_level,
    af.required_vip_level,
    af.asset_url,
    af.is_active,
    af.is_featured,
    af.sort_order,
    count(p.id)
  from public.avatar_frames af
  left join public.profiles p on p.selected_avatar_frame_key = af.frame_key
  where public.has_admin_access()
  group by af.id
  order by af.category, af.sort_order, af.name
  limit greatest(1, least(coalesce(p_limit, 200), 300));
$$;

create or replace function public.admin_update_avatar_frame(
  p_frame_key text,
  p_name text,
  p_category text,
  p_vip_level integer default null,
  p_required_vip_level integer default null,
  p_asset_url text default null,
  p_is_active boolean default true,
  p_is_featured boolean default false,
  p_sort_order integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('content_admin')) then
    raise exception 'not_authorized';
  end if;

  insert into public.avatar_frames (
    frame_key,
    name,
    category,
    vip_level,
    required_vip_level,
    asset_url,
    is_active,
    is_featured,
    sort_order
  )
  values (
    lower(trim(p_frame_key)),
    trim(p_name),
    lower(trim(p_category)),
    p_vip_level,
    p_required_vip_level,
    nullif(trim(coalesce(p_asset_url, '')), ''),
    coalesce(p_is_active, true),
    coalesce(p_is_featured, false),
    coalesce(p_sort_order, 0)
  )
  on conflict (frame_key) do update set
    name = excluded.name,
    category = excluded.category,
    vip_level = excluded.vip_level,
    required_vip_level = excluded.required_vip_level,
    asset_url = excluded.asset_url,
    is_active = excluded.is_active,
    is_featured = excluded.is_featured,
    sort_order = excluded.sort_order
  returning id into v_id;

  perform public.admin_record_audit(
    'update_avatar_frame',
    'avatar_frames',
    lower(trim(p_frame_key)),
    null,
    jsonb_build_object('name', p_name, 'category', p_category)
  );

  return v_id;
end;
$$;

create or replace function public.admin_list_vip_packages()
returns table (
  id uuid,
  vip_level integer,
  code text,
  name text,
  arabic_name text,
  price_coins integer,
  duration_days integer,
  badge_label text,
  entrance_banner_key text,
  is_active boolean,
  sort_order integer
)
language sql
stable
security definer
set search_path = public
as $$
  select id, vip_level, code, name, arabic_name, price_coins, duration_days,
         badge_label, entrance_banner_key, is_active, sort_order
  from public.vip_packages
  where public.has_admin_access()
  order by sort_order, vip_level;
$$;

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
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('content_admin')) then
    raise exception 'not_authorized';
  end if;

  insert into public.vip_packages (
    vip_level, code, name, arabic_name, price_coins, duration_days,
    badge_label, entrance_banner_key, is_active, sort_order, updated_at
  )
  values (
    greatest(1, least(p_vip_level, 5)),
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
    v_id::text,
    null,
    jsonb_build_object('vip_level', p_vip_level, 'price_coins', p_price_coins)
  );

  return v_id;
end;
$$;

create or replace function public.admin_list_entrance_banners()
returns table (
  id uuid,
  banner_key text,
  name text,
  arabic_name text,
  vip_level integer,
  asset_url text,
  gradient_start text,
  gradient_end text,
  message_template text,
  is_active boolean,
  sort_order integer
)
language sql
stable
security definer
set search_path = public
as $$
  select id, banner_key, name, arabic_name, vip_level, asset_url,
         gradient_start, gradient_end, message_template, is_active, sort_order
  from public.entrance_banners
  where public.has_admin_access()
  order by sort_order, vip_level nulls last;
$$;

create or replace function public.admin_update_entrance_banner(
  p_banner_key text,
  p_name text,
  p_arabic_name text default null,
  p_vip_level integer default null,
  p_asset_url text default null,
  p_gradient_start text default null,
  p_gradient_end text default null,
  p_message_template text default null,
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
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('content_admin')) then
    raise exception 'not_authorized';
  end if;

  insert into public.entrance_banners (
    banner_key, name, arabic_name, vip_level, asset_url, gradient_start,
    gradient_end, message_template, is_active, sort_order, updated_at
  )
  values (
    lower(trim(p_banner_key)),
    trim(p_name),
    nullif(trim(coalesce(p_arabic_name, '')), ''),
    p_vip_level,
    nullif(trim(coalesce(p_asset_url, '')), ''),
    nullif(trim(coalesce(p_gradient_start, '')), ''),
    nullif(trim(coalesce(p_gradient_end, '')), ''),
    nullif(trim(coalesce(p_message_template, '')), ''),
    coalesce(p_is_active, true),
    coalesce(p_sort_order, 0),
    now()
  )
  on conflict (banner_key) do update set
    name = excluded.name,
    arabic_name = excluded.arabic_name,
    vip_level = excluded.vip_level,
    asset_url = excluded.asset_url,
    gradient_start = excluded.gradient_start,
    gradient_end = excluded.gradient_end,
    message_template = excluded.message_template,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    updated_at = now()
  returning id into v_id;

  perform public.admin_record_audit(
    'update_entrance_banner',
    'entrance_banners',
    lower(trim(p_banner_key)),
    null,
    jsonb_build_object('name', p_name, 'vip_level', p_vip_level)
  );

  return v_id;
end;
$$;

create or replace function public.admin_list_gift_categories()
returns table (
  id uuid,
  category_key text,
  name text,
  arabic_name text,
  icon text,
  is_active boolean,
  sort_order integer
)
language sql
stable
security definer
set search_path = public
as $$
  select id, category_key, name, arabic_name, icon, is_active, sort_order
  from public.gift_categories
  where public.has_admin_access()
  order by sort_order, name;
$$;

create or replace function public.admin_update_gift_category(
  p_category_key text,
  p_name text,
  p_arabic_name text default null,
  p_icon text default null,
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
begin
  if not (public.has_app_role('super_admin') or public.has_app_role('content_admin')) then
    raise exception 'not_authorized';
  end if;

  insert into public.gift_categories (
    category_key, name, arabic_name, icon, is_active, sort_order, updated_at
  )
  values (
    lower(trim(p_category_key)),
    trim(p_name),
    nullif(trim(coalesce(p_arabic_name, '')), ''),
    nullif(trim(coalesce(p_icon, '')), ''),
    coalesce(p_is_active, true),
    coalesce(p_sort_order, 0),
    now()
  )
  on conflict (category_key) do update set
    name = excluded.name,
    arabic_name = excluded.arabic_name,
    icon = excluded.icon,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    updated_at = now()
  returning id into v_id;

  perform public.admin_record_audit(
    'update_gift_category',
    'gift_categories',
    lower(trim(p_category_key)),
    null,
    jsonb_build_object('name', p_name)
  );

  return v_id;
end;
$$;

create or replace function public.admin_add_user_note(
  p_user_id uuid,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  insert into public.admin_user_notes (user_id, note, created_by)
  values (p_user_id, trim(p_note), auth.uid())
  returning id into v_id;

  perform public.admin_record_audit(
    'add_user_note',
    'admin_user_notes',
    v_id::text,
    p_user_id,
    '{}'::jsonb
  );

  return v_id;
end;
$$;

grant execute on function public.user_has_active_restriction(text, uuid) to authenticated;
grant execute on function public.admin_set_user_golden_id(uuid, text, boolean, timestamptz) to authenticated;
grant execute on function public.admin_grant_vip(uuid, integer, integer, text) to authenticated;
grant execute on function public.admin_list_avatar_frames(integer) to authenticated;
grant execute on function public.admin_update_avatar_frame(text, text, text, integer, integer, text, boolean, boolean, integer) to authenticated;
grant execute on function public.admin_list_vip_packages() to authenticated;
grant execute on function public.admin_update_vip_package(integer, text, text, text, integer, integer, text, text, boolean, integer) to authenticated;
grant execute on function public.admin_list_entrance_banners() to authenticated;
grant execute on function public.admin_update_entrance_banner(text, text, text, integer, text, text, text, text, boolean, integer) to authenticated;
grant execute on function public.admin_list_gift_categories() to authenticated;
grant execute on function public.admin_update_gift_category(text, text, text, text, boolean, integer) to authenticated;
grant execute on function public.admin_add_user_note(uuid, text) to authenticated;
