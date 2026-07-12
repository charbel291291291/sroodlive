-- Room music reliability and storage hardening.

-- Track metadata is room-scoped again. The broad authenticated policy from
-- 20260720000000 exposed every room's titles and URLs.
drop policy if exists room_music_tracks_select_authenticated
  on public.room_music_tracks;

drop policy if exists "Room music: uploader can insert" on storage.objects;
drop policy if exists "Room music: managers can insert" on storage.objects;
create policy "Room music: managers can insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'room_music'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and coalesce((storage.foldername(name))[2], '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
    and public.is_room_manager(
      ((storage.foldername(name))[2])::uuid,
      (select auth.uid())
    )
  );

-- Clear stale ownership immediately when the controlling room member leaves.
create or replace function public._release_departed_music_controller()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE'
     or (new.left_at is not null and old.left_at is null) then
    update public.room_music_state
    set controller_user_id = null,
        updated_at = now()
    where room_id = old.room_id
      and controller_user_id = old.user_id;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public._release_departed_music_controller()
  from public, anon, authenticated;

drop trigger if exists release_departed_music_controller
  on public.room_members;
create trigger release_departed_music_controller
after update of left_at or delete on public.room_members
for each row execute function public._release_departed_music_controller();

create or replace function public.set_room_music_state(
  p_room_id uuid,
  p_track_id text,
  p_track_title text,
  p_track_artist text,
  p_track_url text,
  p_is_playing boolean,
  p_position_seconds integer default 0,
  p_auto_replay boolean default false
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_state public.room_music_state;
  v_controller_active boolean := false;
  v_controller uuid;
  v_result json;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if not public.is_room_manager(p_room_id, v_uid) then
    raise exception 'not_room_manager';
  end if;
  if nullif(trim(coalesce(p_track_url, '')), '') is null
     or p_track_url !~ '^https?://' then
    raise exception 'invalid_track_url';
  end if;
  if length(coalesce(p_track_title, '')) > 200
     or length(coalesce(p_track_artist, '')) > 200
     or length(p_track_url) > 2048 then
    raise exception 'invalid_track_metadata';
  end if;
  if coalesce(p_position_seconds, 0) < 0
     or coalesce(p_position_seconds, 0) > 86400 then
    raise exception 'invalid_position';
  end if;

  select *
  into v_state
  from public.room_music_state
  where room_id = p_room_id
  for update;

  if v_state.controller_user_id is not null then
    select exists (
      select 1
      from public.room_members rm
      where rm.room_id = p_room_id
        and rm.user_id = v_state.controller_user_id
        and rm.left_at is null
    ) into v_controller_active;
  end if;

  if v_state.id is null
     or v_state.controller_user_id is null
     or not v_controller_active then
    v_controller := v_uid;
  elsif v_state.controller_user_id = v_uid
        or public.is_super_admin(v_uid) then
    v_controller := v_state.controller_user_id;
  else
    raise exception 'not_music_controller';
  end if;

  insert into public.room_music_state (
    room_id, track_id, track_title, track_artist, track_url,
    is_playing, started_at, paused_at, position_seconds,
    controller_user_id, auto_replay, updated_by, updated_at
  )
  values (
    p_room_id,
    nullif(trim(coalesce(p_track_id, '')), ''),
    nullif(trim(coalesce(p_track_title, '')), ''),
    nullif(trim(coalesce(p_track_artist, '')), ''),
    trim(p_track_url),
    p_is_playing,
    case when p_is_playing then v_now else null end,
    case when p_is_playing then null else v_now end,
    coalesce(p_position_seconds, 0),
    v_controller,
    p_auto_replay,
    v_uid,
    v_now
  )
  on conflict (room_id) do update set
    track_id = excluded.track_id,
    track_title = excluded.track_title,
    track_artist = excluded.track_artist,
    track_url = excluded.track_url,
    is_playing = excluded.is_playing,
    started_at = excluded.started_at,
    paused_at = excluded.paused_at,
    position_seconds = excluded.position_seconds,
    controller_user_id = excluded.controller_user_id,
    auto_replay = excluded.auto_replay,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning to_json(room_music_state.*) into v_result;

  return v_result;
end;
$$;

create or replace function public.stop_room_music(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_state public.room_music_state;
  v_controller_active boolean := false;
  v_result json;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;

  select *
  into v_state
  from public.room_music_state
  where room_id = p_room_id
  for update;

  if v_state.id is null or v_state.controller_user_id is null then
    return json_build_object(
      'room_id', p_room_id, 'is_playing', false,
      'track_id', null, 'controller_user_id', null, 'updated_at', now()
    );
  end if;

  select exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = v_state.controller_user_id
      and rm.left_at is null
  ) into v_controller_active;

  if v_state.controller_user_id <> v_uid
     and not public.is_super_admin(v_uid)
     and not (
       not v_controller_active
       and public.is_room_manager(p_room_id, v_uid)
     ) then
    raise exception 'not_music_controller';
  end if;

  update public.room_music_state
  set is_playing = false,
      started_at = null,
      paused_at = null,
      position_seconds = 0,
      track_id = null,
      track_title = null,
      track_artist = null,
      track_url = null,
      controller_user_id = null,
      auto_replay = false,
      updated_by = v_uid,
      updated_at = now()
  where room_id = p_room_id
  returning to_json(room_music_state.*) into v_result;

  return v_result;
end;
$$;

create or replace function public.get_room_music_state(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_result json;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if not exists (
    select 1 from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = v_uid
      and rm.left_at is null
  ) then
    raise exception 'not_room_member';
  end if;

  select (
    to_jsonb(ms)
    || jsonb_build_object('server_now', now())
    || case
      when ms.controller_user_id is not null
       and not exists (
         select 1 from public.room_members controller
         where controller.room_id = p_room_id
           and controller.user_id = ms.controller_user_id
           and controller.left_at is null
       )
      then jsonb_build_object('controller_user_id', null)
      else '{}'::jsonb
    end
  )::json
  into v_result
  from public.room_music_state ms
  where ms.room_id = p_room_id;

  return v_result;
end;
$$;

revoke all on function public.set_room_music_state(
  uuid, text, text, text, text, boolean, integer, boolean
) from public, anon;
grant execute on function public.set_room_music_state(
  uuid, text, text, text, text, boolean, integer, boolean
) to authenticated;
revoke all on function public.stop_room_music(uuid) from public, anon;
grant execute on function public.stop_room_music(uuid) to authenticated;
revoke all on function public.get_room_music_state(uuid) from public, anon;
grant execute on function public.get_room_music_state(uuid) to authenticated;

-- Harden track creation and return the storage path on delete so the client can
-- remove the object after the database authorization succeeds.
create or replace function public.add_room_music_track(
  p_room_id uuid,
  p_title text,
  p_track_url text,
  p_artist text default null,
  p_storage_path text default null,
  p_source text default 'upload',
  p_duration_seconds integer default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_result json;
  v_title text := trim(coalesce(p_title, ''));
  v_url text := trim(coalesce(p_track_url, ''));
  v_source text := lower(trim(coalesce(p_source, 'upload')));
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if not public.is_room_manager(p_room_id, v_uid) then
    raise exception 'not_room_manager';
  end if;
  if length(v_title) not between 1 and 200 then
    raise exception 'invalid_track_title';
  end if;
  if v_url !~ '^https?://' or length(v_url) > 2048 then
    raise exception 'invalid_track_url';
  end if;
  if v_source not in ('upload', 'url') then
    raise exception 'invalid_track_source';
  end if;
  if p_duration_seconds is not null
     and p_duration_seconds not between 1 and 86400 then
    raise exception 'invalid_track_duration';
  end if;
  if v_source = 'upload' and (
    p_storage_path is null
    or split_part(p_storage_path, '/', 1) <> v_uid::text
    or split_part(p_storage_path, '/', 2) <> p_room_id::text
  ) then
    raise exception 'invalid_storage_path';
  end if;

  insert into public.room_music_tracks (
    room_id, uploaded_by, title, artist, track_url,
    storage_path, source, duration_seconds
  )
  values (
    p_room_id, v_uid, v_title,
    nullif(trim(coalesce(p_artist, '')), ''),
    v_url, p_storage_path, v_source, p_duration_seconds
  )
  returning to_json(room_music_tracks.*) into v_result;

  return v_result;
end;
$$;

drop function if exists public.delete_room_music_track(uuid);
create function public.delete_room_music_track(p_track_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_track public.room_music_tracks;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;

  select *
  into v_track
  from public.room_music_tracks
  where id = p_track_id
  for update;

  if v_track.id is null then raise exception 'track_not_found'; end if;
  if v_uid <> v_track.uploaded_by
     and not public.is_room_manager(v_track.room_id, v_uid) then
    raise exception 'forbidden';
  end if;

  update public.room_music_tracks
  set is_active = false
  where id = p_track_id;

  return v_track.storage_path;
end;
$$;

revoke all on function public.add_room_music_track(
  uuid, text, text, text, text, text, integer
) from public, anon;
grant execute on function public.add_room_music_track(
  uuid, text, text, text, text, text, integer
) to authenticated;
revoke all on function public.delete_room_music_track(uuid) from public, anon;
grant execute on function public.delete_room_music_track(uuid)
  to authenticated;

-- Bound the personal library query and remove implicit PUBLIC execute.
create or replace function public.get_user_music_tracks(
  p_limit integer default 100
)
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
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$$;

revoke all on function public.get_user_music_tracks(integer)
  from public, anon;
grant execute on function public.get_user_music_tracks(integer)
  to authenticated;
