-- ─────────────────────────────────────────────────────────────────────────────
-- Per-user private conversation state: pin / archive / delete
--
-- Each row belongs to one (conversation, user) pair.
-- Users can only see and modify their own rows (RLS enforced).
-- Deleting a conversation here hides it only for the requesting user;
-- the other participant's messages are unaffected.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.private_conversation_states (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null
                    references public.private_conversations(id) on delete cascade,
  user_id         uuid        not null
                    references auth.users(id) on delete cascade,
  is_pinned       boolean     not null default false,
  is_archived     boolean     not null default false,
  is_deleted      boolean     not null default false,
  pinned_at       timestamptz,
  archived_at     timestamptz,
  deleted_at      timestamptz,
  updated_at      timestamptz not null default now(),
  unique(conversation_id, user_id)
);

alter table public.private_conversation_states enable row level security;

-- Users may only read, write, and delete their own state rows.
drop policy if exists "users manage own conversation states"
  on public.private_conversation_states;

create policy "users manage own conversation states"
  on public.private_conversation_states
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete
  on public.private_conversation_states to authenticated;
