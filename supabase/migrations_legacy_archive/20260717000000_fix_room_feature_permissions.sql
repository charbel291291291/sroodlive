-- ============================================================================
-- Fix room feature permissions
-- Allows authenticated users to read room music tracks and PK state.
-- Keeps writes protected by existing RPCs/policies.
-- ============================================================================

grant select on table public.room_music_tracks to authenticated;
grant select on table public.room_team_pk_sessions to authenticated;
grant select on table public.room_team_pk_members to authenticated;

alter table public.room_music_tracks enable row level security;
alter table public.room_team_pk_sessions enable row level security;
alter table public.room_team_pk_members enable row level security;

drop policy if exists room_music_tracks_select_authenticated on public.room_music_tracks;
create policy room_music_tracks_select_authenticated
on public.room_music_tracks
for select
to authenticated
using (true);

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

-- Lucky bags / red envelopes visibility
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'red_envelopes'
  ) then
    grant select, insert, update on table public.red_envelopes to authenticated;
    execute 'alter table public.red_envelopes enable row level security';

    drop policy if exists red_envelopes_select_authenticated on public.red_envelopes;
    create policy red_envelopes_select_authenticated
    on public.red_envelopes
    for select
    to authenticated
    using (true);
  end if;
end $$;
