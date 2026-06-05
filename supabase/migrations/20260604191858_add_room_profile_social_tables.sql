create table if not exists public.user_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint user_follows_no_self check (follower_id <> following_id)
);

alter table public.user_follows enable row level security;

drop policy if exists "user_follows_select" on public.user_follows;
drop policy if exists "user_follows_insert_own" on public.user_follows;
drop policy if exists "user_follows_delete_own" on public.user_follows;

create policy "user_follows_select"
on public.user_follows
for select
to authenticated
using (true);

create policy "user_follows_insert_own"
on public.user_follows
for insert
to authenticated
with check (auth.uid() = follower_id);

create policy "user_follows_delete_own"
on public.user_follows
for delete
to authenticated
using (auth.uid() = follower_id);

grant select, insert, delete on public.user_follows to authenticated;

create table if not exists public.user_reminders (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references auth.users(id) on delete cascade,
  to_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

alter table public.user_reminders enable row level security;

drop policy if exists "user_reminders_select_related" on public.user_reminders;
drop policy if exists "user_reminders_insert_own" on public.user_reminders;

create policy "user_reminders_select_related"
on public.user_reminders
for select
to authenticated
using (auth.uid() = from_user_id or auth.uid() = to_user_id);

create policy "user_reminders_insert_own"
on public.user_reminders
for insert
to authenticated
with check (auth.uid() = from_user_id);

grant select, insert on public.user_reminders to authenticated;
