alter table public.profiles
add column if not exists date_of_birth date,
add column if not exists bio text;
