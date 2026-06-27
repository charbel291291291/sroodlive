-- Admin: assign a custom golden public_room_code to a room.
--
-- Also updates admin_list_rooms to return public_room_code so the
-- current code is visible in the admin panel room list.

-- â”€â”€ 1. admin_set_room_public_code â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

create or replace function public.admin_set_room_public_code(
  p_room_id uuid,
  p_code    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    public.has_app_role('super_admin')
    or public.has_app_role('support_admin')
  ) then
    raise exception 'not_authorized';
  end if;

  -- Validate: exactly 5 digits, first digit non-zero (matches existing constraint)
  if p_code !~ '^[1-9][0-9]{4}$' then
    raise exception 'invalid_room_code: must be a 5-digit number between 10000 and 99999';
  end if;

  -- Check room exists
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'room_not_found';
  end if;

  -- Uniqueness is enforced by the rooms_public_room_code_key constraint;
  -- let PostgreSQL raise the natural duplicate-key error if already taken.
  update public.rooms
  set public_room_code = p_code,
      updated_at       = now()
  where id = p_room_id;

  perform public.admin_record_audit(
    'set_room_public_code'::text,
    'rooms'::text,
    p_room_id::text,
    auth.uid()::uuid,
    jsonb_build_object('public_room_code', p_code)::jsonb
  );
end;
$$;

grant execute on function public.admin_set_room_public_code(uuid, text) to authenticated;

-- â”€â”€ 2. Rebuild admin_list_rooms to include public_room_code â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

drop function if exists public.admin_list_rooms(integer);

create function public.admin_list_rooms(
  p_limit integer default 50
)
returns table (
  id                 uuid,
  name               text,
  description        text,
  owner_id           uuid,
  owner_public_user_id text,
  owner_name         text,
  language           text,
  max_seats          integer,
  is_private         boolean,
  is_locked          boolean,
  is_closed          boolean,
  closed_at          timestamptz,
  closed_reason      text,
  active_members     bigint,
  public_room_code   text,
  created_at         timestamptz
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
    r.created_at
  from public.rooms r
  left join public.profiles p on p.id = r.owner_id
  where public.has_admin_access()
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

grant execute on function public.admin_list_rooms(integer) to authenticated;
