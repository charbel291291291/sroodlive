alter table public.room_members
add column if not exists seat_number integer;

alter table public.room_members
drop constraint if exists room_members_seat_number_valid;

alter table public.room_members
add constraint room_members_seat_number_valid
check (seat_number is null or seat_number between 1 and 100);