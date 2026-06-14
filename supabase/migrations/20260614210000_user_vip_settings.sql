create table if not exists public.user_vip_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  not_being_followed boolean not null default false,
  anti_entering_room boolean not null default false,
  private_browsing boolean not null default false,
  do_not_disturb boolean not null default false,
  invisibility boolean not null default false,
  anti_kick boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id)
);

create index if not exists idx_user_vip_settings_user_id
  on public.user_vip_settings(user_id);

alter table public.user_vip_settings enable row level security;

drop policy if exists "user_vip_settings_select_own" on public.user_vip_settings;
create policy "user_vip_settings_select_own"
  on public.user_vip_settings for select
  using (auth.uid() = user_id);

drop policy if exists "user_vip_settings_insert_own" on public.user_vip_settings;
create policy "user_vip_settings_insert_own"
  on public.user_vip_settings for insert
  with check (auth.uid() = user_id);

drop policy if exists "user_vip_settings_update_own" on public.user_vip_settings;
create policy "user_vip_settings_update_own"
  on public.user_vip_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.touch_user_vip_settings_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_touch_user_vip_settings_updated_at on public.user_vip_settings;
create trigger trg_touch_user_vip_settings_updated_at
before update on public.user_vip_settings
for each row
execute function public.touch_user_vip_settings_updated_at();

grant select, insert, update on public.user_vip_settings to authenticated;
