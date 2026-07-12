alter table public.rooms
add column if not exists member_count integer not null default 0;

alter table public.rooms
add column if not exists max_members integer;

alter table public.rooms
add column if not exists category text;

alter table public.rooms
add column if not exists tags text[] not null default '{}';

create index if not exists rooms_member_count_idx
on public.rooms (member_count);

create index if not exists rooms_category_idx
on public.rooms (category);