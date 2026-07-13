-- user_preferences table (was missing from migrations)
create table if not exists public.user_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  notif_sound boolean not null default true,
  notif_vibrate boolean not null default true,
  allow_messages boolean not null default true,
  allow_calls boolean not null default true,
  auto_play boolean not null default true,
  data_warning boolean not null default true,
  message_from text not null default 'everyone' check (message_from in ('everyone', 'followers', 'nobody')),
  call_from text not null default 'everyone' check (call_from in ('everyone', 'followers', 'nobody')),
  font_size text not null default 'medium' check (font_size in ('small', 'medium', 'large')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_preferences enable row level security;

drop policy if exists "Users can read own preferences" on public.user_preferences;
create policy "Users can read own preferences"
  on public.user_preferences for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users can upsert own preferences" on public.user_preferences;
create policy "Users can upsert own preferences"
  on public.user_preferences for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users can update own preferences" on public.user_preferences;
create policy "Users can update own preferences"
  on public.user_preferences for update to authenticated
  using (user_id = auth.uid());

grant select, insert, update on public.user_preferences to authenticated;

-- auto-update updated_at on user_preferences
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_preferences_updated_at on public.user_preferences;
create trigger trg_user_preferences_updated_at
  before update on public.user_preferences
  for each row execute function public.set_updated_at();

-- auto-update updated_at on user_settings (was previously client-set)
drop trigger if exists trg_user_settings_updated_at on public.user_settings;
create trigger trg_user_settings_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();
