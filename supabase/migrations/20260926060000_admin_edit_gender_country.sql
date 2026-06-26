-- ============================================================
-- Admin: allow editing gender and country for any user
-- ============================================================
-- 1. Extends admin_user_detail to return gender and country.
-- 2. Extends admin_update_user_profile with p_gender / p_country.
--    Admin bypasses the one-time-change lock and resets the flag
--    so the user still gets their own one change later.
-- Only super_admin and support_admin may call either function.
-- ============================================================

-- 1. Extend admin_user_detail to include gender and country
-- Must drop first because return type (table columns) is changing.
drop function if exists public.admin_user_detail(uuid);

create function public.admin_user_detail(p_user_id uuid)
returns table (
  user_id                   uuid,
  email                     text,
  public_user_id            text,
  display_name              text,
  username                  text,
  avatar_url                text,
  bio                       text,
  date_of_birth             date,
  gender                    text,
  country                   text,
  vip_level                 integer,
  vip_title                 text,
  vip_started_at            timestamptz,
  vip_expires_at            timestamptz,
  selected_avatar_frame_key text,
  coins_balance             integer,
  diamonds_balance          integer,
  lifetime_coins_charged    integer,
  lifetime_coins_spent      integer,
  lifetime_diamonds_earned  integer,
  roles                     text[],
  active_restrictions       jsonb,
  created_at                timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    u.email::text,
    p.public_user_id,
    p.display_name,
    p.username,
    p.avatar_url,
    p.bio,
    p.date_of_birth,
    p.gender,
    p.country,
    coalesce(p.vip_level, 0),
    p.vip_title,
    p.vip_started_at,
    p.vip_expires_at,
    p.selected_avatar_frame_key,
    coalesce(w.coins_balance, 0),
    coalesce(w.diamonds_balance, 0),
    coalesce(w.lifetime_coins_charged, 0),
    coalesce(w.lifetime_coins_spent, 0),
    coalesce(w.lifetime_diamonds_earned, 0),
    coalesce(array_remove(array_agg(distinct aur.role), null), array[]::text[]),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'type', r.restriction_type,
            'reason', r.reason,
            'expires_at', r.expires_at,
            'created_at', r.created_at
          )
          order by r.created_at desc
        )
        from public.admin_user_restrictions r
        where r.user_id = p.id
          and r.is_active
          and (r.expires_at is null or r.expires_at > now())
      ),
      '[]'::jsonb
    ),
    p.created_at
  from public.profiles p
  left join auth.users u on u.id = p.id
  left join public.wallets w on w.user_id = p.id
  left join public.app_user_roles aur on aur.user_id = p.id
  where public.has_admin_access()
    and p.id = p_user_id
  group by p.id, u.email, p.public_user_id, p.display_name, p.username,
           p.avatar_url, p.bio, p.date_of_birth, p.gender, p.country,
           p.vip_level, p.vip_title, p.vip_started_at, p.vip_expires_at,
           p.selected_avatar_frame_key, w.coins_balance, w.diamonds_balance,
           w.lifetime_coins_charged, w.lifetime_coins_spent,
           w.lifetime_diamonds_earned, p.created_at;
$$;

grant execute on function public.admin_user_detail(uuid) to authenticated;

-- ============================================================
-- 2. Extend admin_update_user_profile with gender and country
-- ============================================================

create or replace function public.admin_update_user_profile(
  p_user_id      uuid,
  p_display_name text    default null,
  p_username     text    default null,
  p_avatar_url   text    default null,
  p_bio          text    default null,
  p_vip_level    integer default null,
  p_gender       text    default null,
  p_country      text    default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gender  text := nullif(trim(coalesce(p_gender,  '')), '');
  v_country text := nullif(trim(coalesce(p_country, '')), '');
begin
  if not (
    public.has_app_role('super_admin')
    or public.has_app_role('support_admin')
  ) then
    raise exception 'not_authorized';
  end if;

  update public.profiles
  set
    display_name  = coalesce(p_display_name, display_name),
    username      = coalesce(p_username,     username),
    avatar_url    = coalesce(p_avatar_url,   avatar_url),
    bio           = coalesce(p_bio,          bio),
    vip_level     = coalesce(p_vip_level,    vip_level),
    vip_started_at = case
      when p_vip_level is null then vip_started_at
      when p_vip_level > 0 and vip_level <> p_vip_level then now()
      when p_vip_level = 0 then null
      else vip_started_at
    end,
    vip_expires_at = case
      when p_vip_level is null then vip_expires_at
      when p_vip_level = 0 then null
      else vip_expires_at
    end,
    -- Admin override: set value and reset the one-time lock so user can still change once.
    gender               = case when v_gender  is not null then v_gender  else gender  end,
    gender_changed_once  = case when v_gender  is not null then false      else gender_changed_once  end,
    gender_changed_at    = case when v_gender  is not null then now()      else gender_changed_at    end,
    country              = case when v_country is not null then v_country  else country end,
    country_changed_once = case when v_country is not null then false      else country_changed_once end,
    country_changed_at   = case when v_country is not null then now()      else country_changed_at   end,
    updated_at = now()
  where id = p_user_id;

  perform public.admin_record_audit(
    'update_user_profile',
    'profiles',
    p_user_id::text,
    p_user_id,
    jsonb_build_object(
      'vip_level', p_vip_level,
      'gender',    v_gender,
      'country',   v_country
    )
  );
end;
$$;

grant execute on function public.admin_update_user_profile(uuid, text, text, text, text, integer, text, text) to authenticated;
