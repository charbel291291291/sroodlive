create sequence if not exists public.profile_public_user_id_seq;

alter table public.profiles
add column if not exists public_user_id text;

update public.profiles
set public_user_id = 'SR' || lpad(nextval('public.profile_public_user_id_seq')::text, 8, '0')
where public_user_id is null;

alter table public.profiles
alter column public_user_id
set default 'SR' || lpad(nextval('public.profile_public_user_id_seq')::text, 8, '0');

alter table public.profiles
alter column public_user_id set not null;

alter table public.profiles
drop constraint if exists profiles_public_user_id_key;

alter table public.profiles
add constraint profiles_public_user_id_key unique (public_user_id);
