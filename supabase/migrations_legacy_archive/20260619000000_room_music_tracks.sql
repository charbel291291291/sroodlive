-- ─────────────────────────────────────────────────────────────────────────────
-- Room Music Tracks + Storage Bucket
-- Saves audio tracks uploaded (or linked) by the host into a per-room library.
-- All active members can read; only room managers can insert/delete.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Storage bucket ────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'room_music',
  'room_music',
  true,
  15728640,   -- 15 MB
  array[
    'audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/aac',
    'audio/mp4',  'audio/m4a', 'audio/ogg'
  ]
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Storage policies
drop policy if exists "Room music: authenticated can read"  on storage.objects;
drop policy if exists "Room music: uploader can insert"     on storage.objects;
drop policy if exists "Room music: uploader can update"     on storage.objects;
drop policy if exists "Room music: uploader can delete"     on storage.objects;

create policy "Room music: authenticated can read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'room_music');

-- Path format: {user_id}/{room_id}/{timestamp}_{filename}
-- The first folder segment must equal the caller's own uid.
create policy "Room music: uploader can insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'room_music'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Room music: uploader can update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'room_music'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Room music: uploader can delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'room_music'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── Table: room_music_tracks ──────────────────────────────────────────────────

create table if not exists public.room_music_tracks (
  id               uuid primary key default gen_random_uuid(),
  room_id          uuid not null references public.rooms(id) on delete cascade,
  uploaded_by      uuid not null references auth.users(id) on delete cascade,
  title            text not null,
  artist           text,
  track_url        text not null,
  storage_path     text,
  source           text not null default 'upload',
  duration_seconds integer,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

create index if not exists room_music_tracks_room_id_idx
  on public.room_music_tracks (room_id, is_active, created_at desc);

alter table public.room_music_tracks enable row level security;

-- Active room members can read room tracks.
drop policy if exists "Active members read room music tracks" on public.room_music_tracks;
create policy "Active members read room music tracks"
  on public.room_music_tracks
  for select
  to authenticated
  using (
    exists (
      select 1 from public.room_members rm
      where rm.room_id = room_music_tracks.room_id
        and rm.user_id = auth.uid()
        and rm.left_at is null
    )
  );

-- Room managers (owner/host/admin) can insert, update, delete.
drop policy if exists "Room managers manage room music tracks" on public.room_music_tracks;
create policy "Room managers manage room music tracks"
  on public.room_music_tracks
  for all
  to authenticated
  using  (public.is_room_manager(room_id, auth.uid()))
  with check (public.is_room_manager(room_id, auth.uid()));

-- ── Realtime ──────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'room_music_tracks'
  ) then
    alter publication supabase_realtime add table public.room_music_tracks;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: add_room_music_track
-- Called after uploading a file or pasting a URL.
-- Requires caller to be a room manager.
-- Returns the inserted row as JSON.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.add_room_music_track(
  p_room_id          uuid,
  p_title            text,
  p_track_url        text,
  p_artist           text    default null,
  p_storage_path     text    default null,
  p_source           text    default 'upload',
  p_duration_seconds integer default null
)
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

  insert into public.room_music_tracks (
    room_id, uploaded_by, title, artist, track_url,
    storage_path, source, duration_seconds
  )
  values (
    p_room_id, v_uid, p_title, p_artist, p_track_url,
    p_storage_path, p_source, p_duration_seconds
  )
  returning to_json(room_music_tracks.*) into v_result;

  return v_result;
end;
$$;

grant execute on function public.add_room_music_track(uuid, text, text, text, text, text, integer)
  to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: delete_room_music_track
-- Soft-deletes (sets is_active = false) a track. Only the uploader or
-- a room manager can delete.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.delete_room_music_track(p_track_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_room_id uuid;
  v_uploader uuid;
begin
  if v_uid is null then
    raise exception 'unauthenticated';
  end if;

  select room_id, uploaded_by into v_room_id, v_uploader
  from public.room_music_tracks
  where id = p_track_id;

  if not found then
    raise exception 'track_not_found';
  end if;

  if v_uid != v_uploader and not public.is_room_manager(v_room_id, v_uid) then
    raise exception 'forbidden';
  end if;

  update public.room_music_tracks
  set is_active = false
  where id = p_track_id;
end;
$$;

grant execute on function public.delete_room_music_track(uuid) to authenticated;
