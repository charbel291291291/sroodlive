-- ============================================================
-- Replace SR-prefixed public_user_id with random 6-digit IDs
-- ============================================================
-- Existing users keep their SR IDs untouched.
-- New users get a random 6-digit numeric ID from 100000 to 999999.
-- The column already has a UNIQUE constraint.
-- ============================================================

-- 1. Drop the old sequence-based column default
alter table public.profiles
  alter column public_user_id drop default;

-- 2. Generator function. Picks a random 6-digit number and retries on collision.
create or replace function public.generate_6digit_public_user_id()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_candidate text;
  v_attempts  int := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    if v_attempts > 50 then
      raise exception 'generate_6digit_public_user_id: could not find unique ID after 50 attempts';
    end if;

    -- 100000 to 999999, no leading zero
    v_candidate := (floor(random() * 900000) + 100000)::bigint::text;

    exit when not exists (
      select 1 from public.profiles where public_user_id = v_candidate
    );
  end loop;

  return v_candidate;
end;
$$;

grant execute on function public.generate_6digit_public_user_id() to authenticated, service_role;

-- 3. New column default uses the generator function
alter table public.profiles
  alter column public_user_id
  set default public.generate_6digit_public_user_id();

-- 4. Check constraint allows legacy SR IDs and new 6-digit IDs
alter table public.profiles
  drop constraint if exists profiles_public_user_id_format;

alter table public.profiles
  add constraint profiles_public_user_id_format
  check (
    public_user_id ~ '^SR[0-9]+$'
    or public_user_id ~ '^[1-9][0-9]{5}$'
  );
