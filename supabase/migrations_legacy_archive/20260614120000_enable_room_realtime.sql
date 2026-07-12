-- Enable Supabase Realtime for room gifts & members safely.
-- This migration is idempotent, so it will not fail if tables are already in the publication.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'gift_transactions'
  ) then
    alter publication supabase_realtime add table public.gift_transactions;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_members'
  ) then
    alter publication supabase_realtime add table public.room_members;
  end if;
end $$;

alter table public.gift_transactions replica identity full;
alter table public.room_members replica identity full;
