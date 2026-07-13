-- Rebuild admin_list_rooms with p_include_deleted filter.
-- By default (p_include_deleted = false) soft-deleted rooms are excluded so the
-- admin Rooms list stays clean. Passing true surfaces them for audit purposes.

drop function if exists public.admin_list_rooms(integer);
drop function if exists public.admin_list_rooms(integer, boolean);

create function public.admin_list_rooms(
  p_limit           integer default 50,
  p_include_deleted boolean default false
)
returns table (
  id                   uuid,
  name                 text,
  description          text,
  owner_id             uuid,
  owner_public_user_id text,
  owner_name           text,
  language             text,
  max_seats            integer,
  is_private           boolean,
  is_locked            boolean,
  is_closed            boolean,
  closed_at            timestamptz,
  closed_reason        text,
  active_members       bigint,
  public_room_code     text,
  archived_at          timestamptz,
  deleted_at           timestamptz,
  created_at           timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.name,
    r.description,
    r.owner_id,
    p.public_user_id,
    coalesce(nullif(p.display_name, ''), nullif(p.username, '')),
    r.language,
    coalesce(r.max_seats, r.max_members, 12),
    coalesce(r.is_private, false),
    coalesce(r.is_locked, false),
    coalesce(r.is_closed, false),
    r.closed_at,
    r.closed_reason,
    (
      select count(*)
      from public.room_members rm
      where rm.room_id = r.id
        and rm.left_at is null
        and rm.last_seen_at >= now() - interval '60 seconds'
    )::bigint,
    r.public_room_code,
    r.archived_at,
    r.deleted_at,
    r.created_at
  from public.rooms r
  left join public.profiles p on p.id = r.owner_id
  where public.has_admin_access()
    and (p_include_deleted or r.deleted_at is null)
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

grant execute on function public.admin_list_rooms(integer, boolean) to authenticated;
