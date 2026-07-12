-- ─────────────────────────────────────────────────────────────────────────────
-- User Music Library
-- Lets hosts read ALL tracks they have ever uploaded (across all rooms),
-- so their personal library persists from room to room.
-- ─────────────────────────────────────────────────────────────────────────────

-- RLS: users can always read their own uploaded tracks, regardless of whether
-- they are still a member of that room.
drop policy if exists "Users read own uploaded tracks" on public.room_music_tracks;
create policy "Users read own uploaded tracks"
  on public.room_music_tracks
  for select
  to authenticated
  using (uploaded_by = auth.uid());

-- Index to make the per-user query fast.
create index if not exists room_music_tracks_uploaded_by_idx
  on public.room_music_tracks (uploaded_by, is_active, created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: get_user_music_tracks
-- Returns all active tracks uploaded by the calling user, newest first.
-- Used to populate the host's personal "My Library" in the music panel.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_user_music_tracks(p_limit integer default 100)
returns setof public.room_music_tracks
language sql
security definer
set search_path = public
stable
as $$
  select *
  from public.room_music_tracks
  where uploaded_by = auth.uid()
    and is_active = true
  order by created_at desc
  limit p_limit;
$$;

grant execute on function public.get_user_music_tracks(integer) to authenticated;
