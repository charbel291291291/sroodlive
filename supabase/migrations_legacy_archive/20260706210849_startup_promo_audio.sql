-- Startup promo optional audio support.
-- Keeps existing image-only promos working while allowing a bundled asset
-- reference (asset:assets/sounds/startup_promo_intro.m4a) or remote audio URL.

alter table public.startup_promos
  add column if not exists audio_url text;

comment on column public.startup_promos.audio_url is
  'Optional startup promo audio source. Supports remote URLs or app asset references prefixed with asset:.';

drop function if exists public.get_active_startup_promo();
create or replace function public.get_active_startup_promo()
returns table (
  id               uuid,
  title            text,
  image_url        text,
  audio_url        text,
  duration_seconds int,
  frequency        text,
  priority         int,
  updated_at       timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    id,
    title,
    image_url,
    audio_url,
    duration_seconds,
    frequency,
    priority,
    updated_at
  from public.startup_promos
  where
    is_active = true
    and (starts_at is null or starts_at <= now())
    and (ends_at   is null or ends_at   >  now())
    and image_url is not null
    and image_url <> ''
  order by priority desc, created_at desc
  limit 1;
$$;

revoke all on function public.get_active_startup_promo() from public;
grant execute on function public.get_active_startup_promo() to authenticated;
