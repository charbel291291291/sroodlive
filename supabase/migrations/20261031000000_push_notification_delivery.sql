-- Production push-token hardening.
-- Push delivery is performed only by the send-push-notification Edge Function.

alter table public.user_push_tokens
  add column if not exists device_id text,
  add column if not exists last_seen_at timestamptz not null default now(),
  add column if not exists is_active boolean not null default true,
  add column if not exists invalidated_at timestamptz;

create index if not exists user_push_tokens_user_active_idx
  on public.user_push_tokens (user_id, is_active)
  where is_active;

create index if not exists user_push_tokens_last_seen_idx
  on public.user_push_tokens (last_seen_at desc);

create index if not exists user_push_tokens_device_idx
  on public.user_push_tokens (user_id, device_id)
  where device_id is not null;

-- Preserve the Flutter signature while refreshing delivery-health fields.
create or replace function public.upsert_push_token(
  p_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  p_token := trim(coalesce(p_token, ''));
  if p_token = '' or length(p_token) > 4096 then
    raise exception 'invalid_token';
  end if;

  if p_platform not in ('android', 'ios', 'web') then
    p_platform := 'android';
  end if;

  insert into public.user_push_tokens (
    user_id,
    token,
    platform,
    last_seen_at,
    is_active,
    invalidated_at
  )
  values (
    v_uid,
    p_token,
    p_platform,
    now(),
    true,
    null
  )
  on conflict (token) do update
    set user_id       = excluded.user_id,
        platform      = excluded.platform,
        last_seen_at  = now(),
        updated_at    = now(),
        is_active     = true,
        invalidated_at = null;
end;
$function$;

revoke all on function public.upsert_push_token(text, text)
  from public, anon;
grant execute on function public.upsert_push_token(text, text)
  to authenticated;

-- Called before local logout so a shared device no longer receives pushes for
-- the account that just signed out.
create or replace function public.deactivate_my_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  update public.user_push_tokens
  set is_active = false,
      invalidated_at = now(),
      updated_at = now()
  where user_id = v_uid
    and token = trim(coalesce(p_token, ''));
end;
$function$;

revoke all on function public.deactivate_my_push_token(text)
  from public, anon;
grant execute on function public.deactivate_my_push_token(text)
  to authenticated;

comment on function public.deactivate_my_push_token(text) is
  'Deactivates only the authenticated user''s matching FCM token before logout.';

-- Source-control the shape already consumed by NotificationsScreen. Existing
-- installations keep their rows; missing columns are added compatibly.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null default 'system',
  title text not null default '',
  body text not null default '',
  is_read boolean not null default false,
  read_at timestamptz,
  actor_name text,
  actor_avatar_url text,
  actor_id uuid references auth.users(id) on delete set null,
  target_id text,
  room_id uuid references public.rooms(id) on delete set null,
  sender_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.notifications
  add column if not exists type text not null default 'system',
  add column if not exists title text not null default '',
  add column if not exists body text not null default '',
  add column if not exists is_read boolean not null default false,
  add column if not exists read_at timestamptz,
  add column if not exists actor_name text,
  add column if not exists actor_avatar_url text,
  add column if not exists actor_id uuid,
  add column if not exists target_id text,
  add column if not exists room_id uuid,
  add column if not exists sender_id uuid,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default now();

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id, created_at desc)
  where not is_read;

alter table public.notifications enable row level security;

drop policy if exists "Users read own notifications" on public.notifications;
create policy "Users read own notifications"
  on public.notifications
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users update own notification read state"
  on public.notifications;
create policy "Users update own notification read state"
  on public.notifications
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on table public.notifications from public, anon, authenticated;
grant select on table public.notifications to authenticated;
grant update (is_read, read_at) on table public.notifications to authenticated;

-- The only current user-level producer: room owners notifying a member about
-- moderator assignment/removal. Arbitrary user-to-user notification insertion
-- remains forbidden.
create or replace function public.notify_room_moderator_change(
  p_room_id uuid,
  p_target_user_id uuid,
  p_assigned boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_room_name text;
  v_notification_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_room_id is null or p_target_user_id is null or p_assigned is null then
    raise exception 'invalid_notification_request';
  end if;

  select r.name
  into v_room_name
  from public.rooms r
  where r.id = p_room_id
    and r.owner_id = v_uid;

  if v_room_name is null then
    raise exception 'room_owner_required';
  end if;

  if p_assigned and not exists (
    select 1
    from public.room_moderators rm
    where rm.room_id = p_room_id
      and rm.user_id = p_target_user_id
  ) then
    raise exception 'moderator_assignment_not_found';
  end if;

  if not exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.user_id = p_target_user_id
      and rm.left_at is null
  ) then
    raise exception 'target_not_in_room';
  end if;

  if exists (
    select 1
    from public.notifications n
    where n.user_id = p_target_user_id
      and n.sender_id = v_uid
      and n.room_id = p_room_id
      and n.type = case
        when p_assigned then 'moderator_assigned'
        else 'moderator_removed'
      end
      and n.created_at > now() - interval '1 minute'
  ) then
    raise exception 'notification_rate_limited';
  end if;

  insert into public.notifications (
    user_id,
    type,
    title,
    body,
    is_read,
    actor_id,
    target_id,
    room_id,
    sender_id,
    metadata
  )
  values (
    p_target_user_id,
    case when p_assigned then 'moderator_assigned' else 'moderator_removed' end,
    case
      when p_assigned then 'تمت ترقيتك إلى مشرف'
      else 'تمت إزالتك من المشرفين'
    end,
    case
      when p_assigned then 'أنت الآن مشرف في غرفة ' || v_room_name
      else 'تمت إزالتك من مشرفي غرفة ' || v_room_name
    end,
    false,
    v_uid,
    p_room_id::text,
    p_room_id,
    v_uid,
    jsonb_build_object('assigned', p_assigned)
  )
  returning id into v_notification_id;

  return v_notification_id;
end;
$function$;

revoke all on function public.notify_room_moderator_change(uuid, uuid, boolean)
  from public, anon;
grant execute on function public.notify_room_moderator_change(uuid, uuid, boolean)
  to authenticated;

comment on function public.notify_room_moderator_change(uuid, uuid, boolean) is
  'Owner-authorized moderator notification insert; the push trigger dispatches it asynchronously.';

-- Database webhook equivalent, kept in source control. The trigger is
-- asynchronous and deliberately fail-open: missing Vault configuration or an
-- Edge outage never rolls back the in-app notification.
create extension if not exists pg_net with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.dispatch_notification_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_project_url text;
  v_internal_secret text;
begin
  select decrypted_secret
  into v_project_url
  from vault.decrypted_secrets
  where name = 'push_project_url'
  order by created_at desc
  limit 1;

  select decrypted_secret
  into v_internal_secret
  from vault.decrypted_secrets
  where name = 'push_internal_secret'
  order by created_at desc
  limit 1;

  if nullif(trim(v_project_url), '') is null
     or nullif(v_internal_secret, '') is null then
    raise warning 'Push dispatch skipped: Vault secrets are not configured';
    return new;
  end if;

  perform net.http_post(
    url := rtrim(v_project_url, '/')
      || '/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_internal_secret
    ),
    body := jsonb_build_object('notification_id', new.id),
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    raise warning 'Push dispatch failed for notification %', new.id;
    return new;
end;
$function$;

revoke all on function private.dispatch_notification_push()
  from public, anon, authenticated;

drop trigger if exists notifications_dispatch_push
  on public.notifications;
create trigger notifications_dispatch_push
  after insert on public.notifications
  for each row
  execute function private.dispatch_notification_push();
