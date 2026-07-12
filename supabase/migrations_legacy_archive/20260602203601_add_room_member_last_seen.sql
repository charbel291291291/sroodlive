alter table public.room_members
add column if not exists last_seen_at timestamptz not null default now();

update public.room_members
set last_seen_at = now()
where left_at is null;
