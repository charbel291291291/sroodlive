-- ============================================================================
-- Fix room realtime sync
-- Music, mic/member changes, lucky bags/red envelopes, gifts, and room messages.
-- ============================================================================

do $$
declare
  t text;
  tables text[] := array[
    'room_music_state',
    'room_members',
    'red_envelopes',
    'gift_transactions',
    'room_messages'
  ];
begin
  foreach t in array tables loop
    if exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = t
    ) then
      execute format('alter table public.%I replica identity full', t);

      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end if;
  end loop;
end $$;
