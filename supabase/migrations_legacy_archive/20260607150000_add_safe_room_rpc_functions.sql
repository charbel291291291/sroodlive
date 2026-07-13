-- Phase 2 Security: Add safe RPC functions for room operations
-- These functions ensure room ownership verification before allowing member modifications

create or replace function public.update_room_member_role(
  p_room_id uuid,
  p_user_id uuid,
  p_role text,
  p_seat_number integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_room record;
begin
  if v_caller_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_role not in ('speaker', 'listener') then
    raise exception 'invalid_role';
  end if;

  -- Verify room exists and caller is the owner
  select id, owner_id into v_room
  from public.rooms
  where id = p_room_id;

  if v_room is null then
    raise exception 'room_not_found';
  end if;

  if v_room.owner_id != v_caller_id then
    raise exception 'not_room_owner';
  end if;

  -- Verify target member exists in room
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id
      and user_id = p_user_id
      and left_at is null
  ) then
    raise exception 'member_not_in_room';
  end if;

  -- Update member role and seat if needed
  update public.room_members
  set role = p_role,
      seat_number = case when p_role = 'speaker' then p_seat_number else null end,
      updated_at = now()
  where room_id = p_room_id
    and user_id = p_user_id;
end;
$$;

grant execute on function public.update_room_member_role(uuid, uuid, text, integer) to authenticated;

-- Safe function to update member seat number
create or replace function public.update_room_member_seat(
  p_room_id uuid,
  p_user_id uuid,
  p_seat_number integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_room record;
begin
  if v_caller_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Verify room exists and caller is the owner
  select id, owner_id into v_room
  from public.rooms
  where id = p_room_id;

  if v_room is null then
    raise exception 'room_not_found';
  end if;

  if v_room.owner_id != v_caller_id then
    raise exception 'not_room_owner';
  end if;

  -- Verify target member exists in room
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id
      and user_id = p_user_id
      and left_at is null
  ) then
    raise exception 'member_not_in_room';
  end if;

  -- Update seat number
  update public.room_members
  set seat_number = p_seat_number,
      updated_at = now()
  where room_id = p_room_id
    and user_id = p_user_id;
end;
$$;

grant execute on function public.update_room_member_seat(uuid, uuid, integer) to authenticated;

-- Safe function to remove member from room
create or replace function public.remove_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_room record;
  v_now timestamptz := now();
begin
  if v_caller_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Verify room exists and caller is the owner
  select id, owner_id into v_room
  from public.rooms
  where id = p_room_id;

  if v_room is null then
    raise exception 'room_not_found';
  end if;

  if v_room.owner_id != v_caller_id then
    raise exception 'not_room_owner';
  end if;

  -- Verify target member exists in room
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id
      and user_id = p_user_id
      and left_at is null
  ) then
    raise exception 'member_not_in_room';
  end if;

  -- Mark member as left
  update public.room_members
  set is_muted = true,
      seat_number = null,
      left_at = v_now,
      last_seen_at = v_now,
      updated_at = v_now
  where room_id = p_room_id
    and user_id = p_user_id
    and left_at is null;
end;
$$;

grant execute on function public.remove_room_member(uuid, uuid) to authenticated;

-- Verify that room_members table has RLS enabled.
-- Uses pg_class.relrowsecurity (standard Postgres catalog).
do $$
declare
  v_rls_enabled boolean;
begin
  select relrowsecurity
  into v_rls_enabled
  from pg_class
  where oid = 'public.room_members'::regclass;

  if v_rls_enabled is null then
    raise exception 'SECURITY: table public.room_members does not exist.';
  end if;

  if not v_rls_enabled then
    raise exception 'SECURITY: room_members table must have RLS enabled. Run: ALTER TABLE public.room_members ENABLE ROW LEVEL SECURITY;';
  end if;
end;
$$;

-- Add comment for audit
comment on function public.update_room_member_role(uuid, uuid, text, integer) is
  'Safe RPC function for room owners to update member roles. Verifies room ownership before proceeding. Always use this instead of direct UPDATE.';

comment on function public.update_room_member_seat(uuid, uuid, integer) is
  'Safe RPC function for room owners to update member seat positions. Verifies room ownership before proceeding. Always use this instead of direct UPDATE.';

comment on function public.remove_room_member(uuid, uuid) is
  'Safe RPC function for room owners to remove members from rooms. Verifies room ownership before proceeding. Always use this instead of direct UPDATE.';
