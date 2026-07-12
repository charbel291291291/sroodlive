create table if not exists public.room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  message_type text not null default 'text',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_room_messages_room_created
  on public.room_messages(room_id, created_at desc);

create index if not exists idx_room_messages_sender
  on public.room_messages(sender_id);

alter table public.room_messages enable row level security;

drop policy if exists "room_messages_read" on public.room_messages;
create policy "room_messages_read"
  on public.room_messages for select
  using (auth.uid() is not null);

drop policy if exists "room_messages_insert_own" on public.room_messages;
create policy "room_messages_insert_own"
  on public.room_messages for insert
  with check (auth.uid() = sender_id);

drop policy if exists "room_messages_update_own" on public.room_messages;
create policy "room_messages_update_own"
  on public.room_messages for update
  using (auth.uid() = sender_id)
  with check (auth.uid() = sender_id);

drop policy if exists "room_messages_delete_own" on public.room_messages;
create policy "room_messages_delete_own"
  on public.room_messages for delete
  using (auth.uid() = sender_id);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_messages'
  ) then
    alter publication supabase_realtime add table public.room_messages;
  end if;
end $$;

alter table public.room_messages replica identity full;

grant select, insert, update, delete on public.room_messages to authenticated;
