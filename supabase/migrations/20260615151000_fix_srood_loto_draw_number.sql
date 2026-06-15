-- Fix missing draw_number on deployed Srood Loto loto_draws table

create sequence if not exists public.loto_draw_number_seq start 1 increment 1;

alter table if exists public.loto_draws
add column if not exists draw_number bigint;

update public.loto_draws
set draw_number = nextval('public.loto_draw_number_seq')
where draw_number is null;

alter table if exists public.loto_draws
alter column draw_number set default nextval('public.loto_draw_number_seq');

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'loto_draws'
  )
  and not exists (
    select 1
    from pg_constraint
    where conname = 'loto_draws_draw_number_key'
  ) then
    alter table public.loto_draws
    add constraint loto_draws_draw_number_key unique (draw_number);
  end if;
end $$;