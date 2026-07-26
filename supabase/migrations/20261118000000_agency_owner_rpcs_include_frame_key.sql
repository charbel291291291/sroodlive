-- =============================================================================
-- Additive: expose selected_avatar_frame_key and vip_level on the agency
-- owner RPCs (host roster + pending applications) so the Agency Owner
-- screen can render each user's equipped frame (Frame System v2 migration)
-- instead of a plain circle avatar.
--
-- Postgres does not allow CREATE OR REPLACE FUNCTION to change the OUT
-- column list of a RETURNS TABLE function, so each function is dropped and
-- recreated. Only the function bodies/signatures are redefined here — no
-- data or tables are touched.
-- =============================================================================

drop function if exists public.agency_owner_list_hosts();

create function public.agency_owner_list_hosts()
returns table (
  user_id      uuid,
  display_name text,
  avatar_url   text,
  frame_key    text,
  vip_level    integer,
  status       text,
  joined_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_owner uuid := auth.uid();
begin
  if v_owner is null then raise exception 'not_authenticated'; end if;
  return query
  select
    h.host_user_id,
    p.display_name,
    p.avatar_url,
    p.selected_avatar_frame_key,
    coalesce(p.vip_level, 0),
    h.status,
    h.joined_at
  from public.agency_hosts h
  join public.agencies a on a.id = h.agency_id and a.owner_user_id = v_owner
  left join public.profiles p on p.id = h.host_user_id
  where h.status = 'active'
  order by h.joined_at desc;
end;
$$;
revoke all on function public.agency_owner_list_hosts() from public, anon;
grant execute on function public.agency_owner_list_hosts() to authenticated;


drop function if exists public.agency_owner_list_pending_applications();

create function public.agency_owner_list_pending_applications()
returns table (
  application_id uuid,
  user_id        uuid,
  display_name   text,
  avatar_url     text,
  frame_key      text,
  vip_level      integer,
  message        text,
  phone          text,
  country        text,
  created_at     timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_owner uuid := auth.uid();
begin
  if v_owner is null then raise exception 'not_authenticated'; end if;
  return query
  select
    ap.id,
    ap.user_id,
    p.display_name,
    p.avatar_url,
    p.selected_avatar_frame_key,
    coalesce(p.vip_level, 0),
    ap.message,
    ap.phone,
    ap.country,
    ap.created_at
  from public.agency_applications ap
  -- Owner scope: only applications whose target agency the caller owns. Apps
  -- for other agencies are never returned.
  join public.agencies a on a.id = ap.agency_id and a.owner_user_id = v_owner
  left join public.profiles p on p.id = ap.user_id
  where ap.application_type = 'join_agency'
    and ap.status = 'pending'
  order by ap.created_at desc;
end;
$$;
revoke all on function public.agency_owner_list_pending_applications() from public, anon;
grant execute on function public.agency_owner_list_pending_applications() to authenticated;
