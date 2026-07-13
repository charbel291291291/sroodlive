-- ============================================================================
-- Fix rooms table for Realtime delivery of seat count / config changes.
-- Without REPLICA IDENTITY FULL the UPDATE payload carries no column values.
-- Without the publication entry no events are sent to subscribers at all.
-- ============================================================================

-- Full row in UPDATE payloads so Flutter can read max_seats etc.
alter table public.rooms replica identity full;

-- Authenticated users must be able to SELECT rooms for Realtime to work.
grant select on table public.rooms to authenticated;

-- Enable RLS if not already on (no-op if already enabled).
alter table public.rooms enable row level security;

-- Allow any authenticated user to read any room row.
drop policy if exists rooms_select_authenticated on public.rooms;
create policy rooms_select_authenticated
  on public.rooms
  for select
  to authenticated
  using (true);

-- Add rooms to the Realtime publication (idempotent).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'rooms'
  ) then
    alter publication supabase_realtime add table public.rooms;
  end if;
end $$;
