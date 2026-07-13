alter table public.rooms
add column if not exists is_live boolean not null default false;

alter table public.rooms
add column if not exists ended_at timestamptz;

create index if not exists rooms_is_live_idx
on public.rooms (is_live);

create index if not exists rooms_ended_at_idx
on public.rooms (ended_at);