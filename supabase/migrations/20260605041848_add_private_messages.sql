create table if not exists public.private_conversations (
  id uuid primary key default gen_random_uuid(),
  user_one_id uuid not null references auth.users(id) on delete cascade,
  user_two_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message text null,
  last_message_at timestamptz null,
  constraint private_conversations_users_not_same check (user_one_id <> user_two_id)
);

create unique index if not exists private_conversations_unique_pair
on public.private_conversations (
  least(user_one_id, user_two_id),
  greatest(user_one_id, user_two_id)
);

alter table public.private_conversations enable row level security;

drop policy if exists "private_conversations_select_member" on public.private_conversations;
drop policy if exists "private_conversations_insert_member" on public.private_conversations;
drop policy if exists "private_conversations_update_member" on public.private_conversations;

create policy "private_conversations_select_member"
on public.private_conversations
for select
to authenticated
using (auth.uid() = user_one_id or auth.uid() = user_two_id);

create policy "private_conversations_insert_member"
on public.private_conversations
for insert
to authenticated
with check (auth.uid() = user_one_id or auth.uid() = user_two_id);

create policy "private_conversations_update_member"
on public.private_conversations
for update
to authenticated
using (auth.uid() = user_one_id or auth.uid() = user_two_id)
with check (auth.uid() = user_one_id or auth.uid() = user_two_id);

grant select, insert, update on public.private_conversations to authenticated;

create table if not exists public.private_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.private_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz null,
  constraint private_messages_body_not_empty check (length(trim(body)) > 0),
  constraint private_messages_users_not_same check (sender_id <> receiver_id)
);

create index if not exists private_messages_conversation_created_idx
on public.private_messages (conversation_id, created_at);

alter table public.private_messages enable row level security;

drop policy if exists "private_messages_select_related" on public.private_messages;
drop policy if exists "private_messages_insert_sender" on public.private_messages;
drop policy if exists "private_messages_update_read_receiver" on public.private_messages;

create policy "private_messages_select_related"
on public.private_messages
for select
to authenticated
using (auth.uid() = sender_id or auth.uid() = receiver_id);

create policy "private_messages_insert_sender"
on public.private_messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1
    from public.private_conversations c
    where c.id = conversation_id
      and (
        (c.user_one_id = sender_id and c.user_two_id = receiver_id)
        or (c.user_two_id = sender_id and c.user_one_id = receiver_id)
      )
  )
);

create policy "private_messages_update_read_receiver"
on public.private_messages
for update
to authenticated
using (auth.uid() = receiver_id)
with check (auth.uid() = receiver_id);

grant select, insert, update on public.private_messages to authenticated;
