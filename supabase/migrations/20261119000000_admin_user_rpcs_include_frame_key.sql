-- =============================================================================
-- Additive: expose selected_avatar_frame_key on the admin user-lookup RPCs
-- (admin_search_users + admin_find_user_for_grants) so the Admin Panel and
-- VIP Center admin search cards can render each user's equipped frame
-- (Frame System v2 migration) instead of a plain circle avatar.
--
-- Postgres does not allow CREATE OR REPLACE FUNCTION to change the OUT
-- column list of a RETURNS TABLE function, so each function is dropped and
-- recreated. Only the function bodies/signatures are redefined here — no
-- data or tables are touched.
-- =============================================================================

drop function if exists public.admin_search_users(text, integer);

create function public.admin_search_users(
  p_query text default null,
  p_limit integer default 50
)
returns table (
  user_id uuid,
  public_user_id text,
  display_name text,
  username text,
  avatar_url text,
  frame_key text,
  vip_level integer,
  coins_balance integer,
  diamonds_balance integer,
  roles text[],
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.public_user_id,
    p.display_name,
    p.username,
    p.avatar_url,
    p.selected_avatar_frame_key,
    coalesce(p.vip_level, 0),
    coalesce(w.coins_balance, 0),
    coalesce(w.diamonds_balance, 0),
    coalesce(
      array_remove(array_agg(distinct aur.role), null),
      array[]::text[]
    ),
    p.created_at
  from public.profiles p
  left join public.wallets w on w.user_id = p.id
  left join public.app_user_roles aur on aur.user_id = p.id
  where public.has_admin_access()
    and (
      nullif(trim(coalesce(p_query, '')), '') is null
      or p.public_user_id ilike '%' || trim(p_query) || '%'
      or p.display_name ilike '%' || trim(p_query) || '%'
      or p.username ilike '%' || trim(p_query) || '%'
      or p.id::text ilike '%' || trim(p_query) || '%'
    )
  group by
    p.id,
    p.public_user_id,
    p.display_name,
    p.username,
    p.avatar_url,
    p.selected_avatar_frame_key,
    p.vip_level,
    w.coins_balance,
    w.diamonds_balance,
    p.created_at
  order by p.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

grant execute on function public.admin_search_users(text, integer) to authenticated;


drop function if exists public.admin_find_user_for_grants(text, integer);

create function public.admin_find_user_for_grants(
  p_query  text,
  p_limit  integer default 10
)
returns table (
  user_id      uuid,
  username     text,
  display_name text,
  golden_id    text,
  avatar_url   text,
  frame_key    text,
  vip_level    integer,
  vip_until    timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query  text := trim(coalesce(p_query, ''));
  v_limit  int  := greatest(1, least(coalesce(p_limit, 10), 50));
  v_is_uuid boolean;
begin
  if not public.has_admin_access() then
    raise exception 'not_authorized';
  end if;

  if v_query = '' then
    return;
  end if;

  -- Safe UUID detection — regex only, no cast attempted before confirmation.
  v_is_uuid := v_query ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  return query
  select
    p.id,
    p.username,
    p.display_name,
    p.public_user_id,   -- this is the "golden_id" / public short-code
    p.avatar_url,
    p.selected_avatar_frame_key,
    coalesce(p.vip_level, 0),
    p.vip_expires_at
  from public.profiles p
  where
    case
      -- Branch 1: query looks like a UUID → exact id match
      when v_is_uuid then
        p.id = v_query::uuid

      -- Branch 2: exact golden-ID / public-user-id match (e.g. "007")
      when p.public_user_id = v_query then
        true

      -- Branch 3: fuzzy name / username / partial UUID-text match
      else
        p.public_user_id ilike '%' || v_query || '%'
        or p.username     ilike '%' || v_query || '%'
        or p.display_name ilike '%' || v_query || '%'
        or p.id::text     ilike '%' || v_query || '%'
    end
  order by
    -- Exact matches first
    (p.public_user_id = v_query) desc,
    (v_is_uuid and p.id = v_query::uuid) desc,
    p.created_at desc
  limit v_limit;
end;
$$;

grant  execute on function public.admin_find_user_for_grants(text, integer) to authenticated;
revoke execute on function public.admin_find_user_for_grants(text, integer) from anon;
