-- ============================================================
-- Room-level mute: is_room_muted on rooms table
-- ============================================================
-- Adds a room-wide mute flag. When true, only the owner and
-- moderators can open a mic; listeners are blocked with a clear
-- bilingual message on the client.
--
-- Per-member is_muted / force_muted are unchanged and continue
-- to handle individual seat mutes independently.
-- ============================================================

-- 1. Add column
alter table public.rooms
  add column if not exists is_room_muted boolean not null default false;

-- 2. RPC: only the room owner or a moderator may toggle it.
--    Updates updated_at so the existing realtime subscription fires.
create or replace function public.set_room_muted(
  p_room_id uuid,
  p_is_muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caller must be owner or an active moderator/host
  if not exists (
    select 1
    from   public.room_members
    where  room_id = p_room_id
      and  user_id = auth.uid()
      and  role    in ('host', 'moderator')
      and  status  = 'active'
  ) then
    raise exception 'set_room_muted: caller is not owner or moderator';
  end if;

  update public.rooms
  set    is_room_muted = p_is_muted,
         updated_at    = now()
  where  id = p_room_id;
end;
$$;

grant execute on function public.set_room_muted(uuid, boolean) to authenticated;
