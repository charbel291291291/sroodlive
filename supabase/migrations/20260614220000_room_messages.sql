-- room_messages: realtime chat for live rooms.
-- Lightweight, ephemeral-friendly; cleared per-room by moderators.

create table if not exists public.room_messages (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null,
  sender_id    uuid not null references auth.users(id) on delete cascade,
  message      text not null check (char_length(message) between 1 and 300),
  message_type text not null default 'text',  -- 'text' | 'system'
  metadata     jsonb not null default '{}',
  created_at   timestamptz not null default now()
);

create index if not exists idx_room_messages_room_created
  on public.room_messages (room_id, created_at desc);

-- RLS
alter table public.room_messages enable row level security;

-- Read: any authenticated user (we rely on room membership at app layer)
create policy "room_messages_read"
  on public.room_messages for select
  using (auth.uid() is not null);

-- Insert: only as yourself
create policy "room_messages_insert_own"
  on public.room_messages for insert
  with check (auth.uid() = sender_id);

-- Delete/update: only service role (mod clear-chat via RPC)
-- Normal users cannot delete individual messages.

-- Add to realtime publication so clients receive push events.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'room_messages'
  ) then
    alter publication supabase_realtime add table public.room_messages;
  end if;
end $$;
