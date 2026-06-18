-- Migration: add force_muted column to room_members
--
-- Root cause: is_muted is the only mute field. A user muted by the owner can
-- call set_my_room_mute_status(p_is_muted = false) to clear the mute because
-- there is no distinction between owner-forced mute and self-mute.
--
-- Fix:
--   force_muted = true  →  set only by owner via owner_mute_member
--   force_muted = false →  cleared only by owner when they unmute
--   set_my_room_mute_status now rejects unmute when force_muted = true
--
-- Idempotent: ADD COLUMN IF NOT EXISTS + CREATE OR REPLACE are safe to re-run.

-- ── 1. Add column ─────────────────────────────────────────────────────────────
alter table public.room_members
  add column if not exists force_muted boolean not null default false;

-- ── 2. owner_mute_member: also write force_muted ──────────────────────────────
create or replace function public.owner_mute_member(
  p_room_id  uuid,
  p_user_id  uuid,
  p_is_muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_owner  uuid;
begin
  if v_caller is null then
    raise exception 'not_authenticated';
  end if;

  select owner_id into v_owner from public.rooms where id = p_room_id;

  if v_owner is null then
    raise exception 'room_not_found';
  end if;

  if v_owner != v_caller then
    raise exception 'not_room_owner';
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_user_id and left_at is null
  ) then
    raise exception 'member_not_in_room';
  end if;

  update public.room_members
  set is_muted    = p_is_muted,
      force_muted = p_is_muted,
      updated_at  = now()
  where room_id = p_room_id and user_id = p_user_id and left_at is null;
end;
$$;

grant execute on function public.owner_mute_member(uuid, uuid, boolean) to authenticated;

-- ── 3. set_my_room_mute_status: block self-unmute when force_muted ────────────
create or replace function public.set_my_room_mute_status(
  p_room_id uuid,
  p_is_muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_force_muted boolean;
begin
  -- If the user wants to unmute, check whether they are force-muted by owner.
  if not p_is_muted then
    select force_muted
    into   v_force_muted
    from   public.room_members
    where  room_id = p_room_id
      and  user_id = auth.uid()
      and  left_at is null;

    if v_force_muted = true then
      raise exception 'force_muted';
    end if;
  end if;

  update public.room_members
  set    is_muted     = p_is_muted,
         last_seen_at = now()
  where  room_id  = p_room_id
    and  user_id  = auth.uid()
    and  left_at  is null;

  if not found then
    raise exception 'no_active_member';
  end if;
end;
$$;

grant execute on function public.set_my_room_mute_status(uuid, boolean) to authenticated;
