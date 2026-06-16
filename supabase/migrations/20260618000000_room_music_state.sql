-- ─────────────────────────────────────────────────────────────────────────────
-- Room Music State
-- Stores the shared music playback state for a live room.
-- One row per room (upserted by room_id).
-- Host/owner/admin writes; active members read.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.room_music_state (
  id               uuid primary key default gen_random_uuid(),
  room_id          uuid not null unique references public.rooms(id) on delete cascade,
  track_id         text,
  track_title      text,
  track_artist     text,
  track_url        text,
  is_playing       boolean not null default false,
  -- Absolute UTC timestamp when playback started at position_seconds.
  started_at       timestamptz,
  paused_at        timestamptz,
  -- Playback position (seconds) at the moment started_at / paused_at was set.
  position_seconds integer not null default 0,
  updated_by       uuid references auth.users(id) on delete set null,
  updated_at       timestamptz not null default now()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
create index if not exists room_music_state_room_id_idx
  on public.room_music_state (room_id);

-- ── RLS ───────────────────────────────────────────────────────────────────────
alter table public.room_music_state enable row level security;

-- Active room members may read.
create policy "Active room members read music state"
  on public.room_music_state
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_members rm
      where rm.room_id = room_music_state.room_id
        and rm.user_id = auth.uid()
        and rm.left_at is null
    )
  );

-- Room managers (owner/host/admin) may insert, update, delete.
create policy "Room managers control music state"
  on public.room_music_state
  for all
  to authenticated
  using (
    public.is_room_manager(room_id, auth.uid())
  )
  with check (
    public.is_room_manager(room_id, auth.uid())
  );

-- ── Realtime ──────────────────────────────────────────────────────────────────
-- Add to Supabase realtime publication so clients receive live updates.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and tablename = 'room_music_state'
  ) then
    alter publication supabase_realtime add table public.room_music_state;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: set_room_music_state
-- Called by host/owner to play, pause, or change track.
-- Upserts by room_id and returns the updated row.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.set_room_music_state(
  p_room_id        uuid,
  p_track_id       text,
  p_track_title    text,
  p_track_artist   text,
  p_track_url      text,
  p_is_playing     boolean,
  p_position_seconds integer default 0
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_now         timestamptz := now();
  v_started_at  timestamptz;
  v_paused_at   timestamptz;
  v_result      json;
begin
  -- Auth guard
  if v_uid is null then
    raise exception 'unauthenticated';
  end if;

  -- Permission guard
  if not public.is_room_manager(p_room_id, v_uid) then
    raise exception 'not_room_manager';
  end if;

  -- Derive timestamps
  if p_is_playing then
    -- Anchor started_at so clients can compute currentPosition =
    --   p_position_seconds + (now - started_at)
    v_started_at := v_now;
    v_paused_at  := null;
  else
    v_started_at := null;
    v_paused_at  := v_now;
  end if;

  insert into public.room_music_state (
    room_id, track_id, track_title, track_artist, track_url,
    is_playing, started_at, paused_at, position_seconds,
    updated_by, updated_at
  )
  values (
    p_room_id, p_track_id, p_track_title, p_track_artist, p_track_url,
    p_is_playing, v_started_at, v_paused_at, p_position_seconds,
    v_uid, v_now
  )
  on conflict (room_id) do update set
    track_id         = excluded.track_id,
    track_title      = excluded.track_title,
    track_artist     = excluded.track_artist,
    track_url        = excluded.track_url,
    is_playing       = excluded.is_playing,
    started_at       = excluded.started_at,
    paused_at        = excluded.paused_at,
    position_seconds = excluded.position_seconds,
    updated_by       = excluded.updated_by,
    updated_at       = excluded.updated_at
  returning to_json(room_music_state.*) into v_result;

  return v_result;
end;
$$;

grant execute on function public.set_room_music_state(uuid, text, text, text, text, boolean, integer)
  to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: stop_room_music
-- Called by host to stop music and clear playback state.
-- Keeps track metadata (title, url) for easy restart but sets is_playing=false
-- and clears started_at so clients stop.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.stop_room_music(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_result json;
begin
  if v_uid is null then
    raise exception 'unauthenticated';
  end if;

  if not public.is_room_manager(p_room_id, v_uid) then
    raise exception 'not_room_manager';
  end if;

  update public.room_music_state
  set
    is_playing       = false,
    started_at       = null,
    paused_at        = null,
    position_seconds = 0,
    track_id         = null,
    track_title      = null,
    track_artist     = null,
    track_url        = null,
    updated_by       = v_uid,
    updated_at       = now()
  where room_id = p_room_id
  returning to_json(room_music_state.*) into v_result;

  -- If no row existed yet, return a synthetic stopped state.
  if v_result is null then
    v_result := json_build_object(
      'room_id', p_room_id,
      'is_playing', false,
      'track_id', null,
      'updated_at', now()
    );
  end if;

  return v_result;
end;
$$;

grant execute on function public.stop_room_music(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: get_room_music_state
-- Called on join/reconnect to sync late joiners.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_room_music_state(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_result json;
begin
  if v_uid is null then
    raise exception 'unauthenticated';
  end if;

  -- Must be an active member to read music state.
  if not exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = v_uid
      and rm.left_at is null
  ) then
    raise exception 'not_room_member';
  end if;

  select to_json(ms.*)
  into v_result
  from public.room_music_state ms
  where ms.room_id = p_room_id;

  return v_result; -- null if no music state exists
end;
$$;

grant execute on function public.get_room_music_state(uuid) to authenticated;
