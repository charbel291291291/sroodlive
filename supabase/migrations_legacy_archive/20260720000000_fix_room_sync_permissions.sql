-- ============================================================================
-- Fix room sync permissions (music, mute, red envelopes, PK)
-- Idempotent — safe to run multiple times.
-- ============================================================================

-- ── 1. room_members ──────────────────────────────────────────────────────────

-- Full identity needed so Realtime UPDATE events carry the complete row.
alter table public.room_members replica identity full;

-- Table-level grants (idempotent).
grant select, update on table public.room_members to authenticated;

-- Add to Realtime publication if not already there.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_members'
  ) then
    alter publication supabase_realtime add table public.room_members;
  end if;
end $$;

-- All authenticated users may read room_members (needed so room_music_state
-- RLS sub-query "exists(select 1 from room_members where user_id = auth.uid())"
-- works for every subscriber).
alter table public.room_members enable row level security;

drop policy if exists room_members_select_authenticated on public.room_members;
create policy room_members_select_authenticated
  on public.room_members
  for select
  to authenticated
  using (true);

-- Users may update only their own active row (mute toggle).
drop policy if exists room_members_update_own_mute on public.room_members;
create policy room_members_update_own_mute
  on public.room_members
  for update
  to authenticated
  using  (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 2. set_my_room_mute_status RPC ───────────────────────────────────────────

create or replace function public.set_my_room_mute_status(
  p_room_id uuid,
  p_is_muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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

-- ── 3. room_music_state ───────────────────────────────────────────────────────

alter table public.room_music_state replica identity full;

grant select on table public.room_music_state to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_music_state'
  ) then
    alter publication supabase_realtime add table public.room_music_state;
  end if;
end $$;

-- ── 4. room_music_tracks ─────────────────────────────────────────────────────

alter table public.room_music_tracks enable row level security;

grant select on table public.room_music_tracks to authenticated;

drop policy if exists room_music_tracks_select_authenticated on public.room_music_tracks;
create policy room_music_tracks_select_authenticated
  on public.room_music_tracks
  for select
  to authenticated
  using (true);

-- ── 5. room_team_pk_sessions / members ───────────────────────────────────────

alter table public.room_team_pk_sessions enable row level security;
alter table public.room_team_pk_members  enable row level security;

grant select on table public.room_team_pk_sessions to authenticated;
grant select on table public.room_team_pk_members  to authenticated;

drop policy if exists room_team_pk_sessions_select_authenticated on public.room_team_pk_sessions;
create policy room_team_pk_sessions_select_authenticated
  on public.room_team_pk_sessions
  for select
  to authenticated
  using (true);

drop policy if exists room_team_pk_members_select_authenticated on public.room_team_pk_members;
create policy room_team_pk_members_select_authenticated
  on public.room_team_pk_members
  for select
  to authenticated
  using (true);

-- ── 6. red_envelopes ─────────────────────────────────────────────────────────

do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'red_envelopes'
  ) then
    execute 'alter table public.red_envelopes replica identity full';
    execute 'grant select on table public.red_envelopes to authenticated';

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'red_envelopes'
    ) then
      execute 'alter publication supabase_realtime add table public.red_envelopes';
    end if;
  end if;
end $$;
