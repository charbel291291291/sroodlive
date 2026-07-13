-- =============================================================================
-- MVP Safety Moderation
-- Adds: moderation_events, moderation_user_scores,
--       server-side chat mute enforcement (RLS),
--       log_moderation_event, check_user_active_mute,
--       admin_apply_moderation_action, admin_get_moderation_events RPCs
-- =============================================================================

-- ── 1. moderation_events ─────────────────────────────────────────────────────

create table if not exists public.moderation_events (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users(id) on delete cascade,
  room_id         uuid        references public.rooms(id)        on delete set null,
  source          text        not null check (source in ('chat','report','admin')),
  violation_type  text        not null,
  severity        int         not null check (severity between 1 and 4),
  original_text   text,
  normalized_text text,
  matched_rule    text,
  action_taken    text,
  status          text        not null default 'open'
                              check (status in ('open','reviewed','dismissed')),
  created_at      timestamptz not null default now()
);

create index if not exists idx_moderation_events_user
  on public.moderation_events (user_id, created_at desc);

create index if not exists idx_moderation_events_status
  on public.moderation_events (status, severity desc, created_at desc);

alter table public.moderation_events enable row level security;

-- Only admins can read events (normal users have no direct access)
drop policy if exists "moderation_events_admin_select" on public.moderation_events;
create policy "moderation_events_admin_select"
  on public.moderation_events for select
  to authenticated
  using (public.has_admin_access());

grant select on public.moderation_events to authenticated;

-- ── 2. moderation_user_scores ─────────────────────────────────────────────────

create table if not exists public.moderation_user_scores (
  user_id           uuid        primary key references auth.users(id) on delete cascade,
  score             int         not null default 0,
  last_violation_at timestamptz,
  warning_count     int         not null default 0,
  mute_count        int         not null default 0,
  kick_count        int         not null default 0,
  temp_ban_count    int         not null default 0,
  updated_at        timestamptz not null default now()
);

alter table public.moderation_user_scores enable row level security;

-- Admins only
drop policy if exists "moderation_user_scores_admin_select" on public.moderation_user_scores;
create policy "moderation_user_scores_admin_select"
  on public.moderation_user_scores for select
  to authenticated
  using (public.has_admin_access());

grant select on public.moderation_user_scores to authenticated;

-- ── 3. Enforce chat_mute server-side on room_messages ────────────────────────
--    Replace the permissive insert policy with one that blocks muted users.

drop policy if exists "room_messages_insert_own" on public.room_messages;
create policy "room_messages_insert_own"
  on public.room_messages for insert
  with check (
    auth.uid() = sender_id
    -- Block system-level chat_mute from admin_user_restrictions
    and not exists (
      select 1 from public.admin_user_restrictions
      where user_id    = auth.uid()
        and restriction_type = 'chat_mute'
        and is_active  = true
        and (expires_at is null or expires_at > now())
    )
    -- Block room-level force_muted from room_members
    and not exists (
      select 1 from public.room_members rm
      where rm.user_id = auth.uid()
        and rm.room_id = room_messages.room_id
        and rm.force_muted = true
    )
  );

-- ── 4. log_moderation_event() ────────────────────────────────────────────────

create or replace function public.log_moderation_event(
  p_room_id         uuid    default null,
  p_source          text    default 'chat',
  p_violation_type  text    default 'other',
  p_severity        int     default 1,
  p_original_text   text    default null,
  p_normalized_text text    default null,
  p_matched_rule    text    default null,
  p_action_taken    text    default null
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_user_id  uuid := auth.uid();
  v_event_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  insert into public.moderation_events
    (user_id, room_id, source, violation_type, severity,
     original_text, normalized_text, matched_rule, action_taken)
  values
    (v_user_id, p_room_id, p_source, p_violation_type, p_severity,
     p_original_text, p_normalized_text, p_matched_rule, p_action_taken)
  returning id into v_event_id;

  -- Upsert score
  insert into public.moderation_user_scores
    (user_id, score, last_violation_at,
     warning_count, mute_count, updated_at)
  values
    (v_user_id, p_severity, now(),
     case when p_severity = 1 then 1 else 0 end,
     case when p_severity >= 2 then 1 else 0 end,
     now())
  on conflict (user_id) do update set
    score             = public.moderation_user_scores.score + p_severity,
    last_violation_at = now(),
    warning_count     = public.moderation_user_scores.warning_count
                        + case when p_severity = 1 then 1 else 0 end,
    mute_count        = public.moderation_user_scores.mute_count
                        + case when p_severity >= 2 then 1 else 0 end,
    updated_at        = now();

  return v_event_id;
end;
$$;

grant execute on function public.log_moderation_event(uuid,text,text,int,text,text,text,text)
  to authenticated;

-- ── 5. check_user_active_mute() ───────────────────────────────────────────────
--    Returns JSON with muted=true/false and context. Used for Flutter pre-check.

create or replace function public.check_user_active_mute(
  p_room_id uuid default null
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_expires_at  timestamptz;
  v_reason      text;
  v_force_muted boolean;
begin
  if v_user_id is null then
    return jsonb_build_object('muted', false);
  end if;

  -- Check system-level chat_mute
  select expires_at, reason
  into   v_expires_at, v_reason
  from   public.admin_user_restrictions
  where  user_id         = v_user_id
    and  restriction_type = 'chat_mute'
    and  is_active        = true
    and  (expires_at is null or expires_at > now())
  order by created_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'muted',      true,
      'type',       'chat_mute',
      'expires_at', v_expires_at,
      'reason',     v_reason
    );
  end if;

  -- Check room-level force_muted
  if p_room_id is not null then
    select force_muted
    into   v_force_muted
    from   public.room_members
    where  user_id = v_user_id
      and  room_id = p_room_id;

    if v_force_muted = true then
      return jsonb_build_object(
        'muted',      true,
        'type',       'force_muted',
        'expires_at', null,
        'reason',     'Muted by room owner'
      );
    end if;

    -- Check room ban
    if exists (
      select 1 from public.room_bans
      where user_id = v_user_id
        and room_id = p_room_id
        and (expires_at is null or expires_at > now())
    ) then
      select expires_at, reason
      into   v_expires_at, v_reason
      from   public.room_bans
      where  user_id = v_user_id
        and  room_id = p_room_id
        and  (expires_at is null or expires_at > now())
      order by created_at desc limit 1;

      return jsonb_build_object(
        'muted',      true,
        'type',       'room_ban',
        'expires_at', v_expires_at,
        'reason',     v_reason
      );
    end if;
  end if;

  return jsonb_build_object('muted', false);
end;
$$;

grant execute on function public.check_user_active_mute(uuid)
  to authenticated;

-- ── 6. admin_apply_moderation_action() ───────────────────────────────────────

create or replace function public.admin_apply_moderation_action(
  p_target_user_id uuid,
  p_action_type    text,     -- 'chat_mute' | 'account_ban' | 'gift_block' | 'warning' | 'dismissed'
  p_reason         text,
  p_room_id        uuid      default null,
  p_expires_at     timestamptz default null,
  p_event_id       uuid      default null,
  p_report_id      uuid      default null
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
begin
  if v_admin_id is null then raise exception 'not_authenticated'; end if;
  if not public.has_admin_access() then
    raise exception 'permission_denied: admin access required';
  end if;

  -- Apply restriction (warning and dismissed don't add a row)
  if p_action_type in ('chat_mute', 'account_ban', 'gift_block') then
    -- Deactivate existing active restriction of same type first
    update public.admin_user_restrictions
    set    is_active = false, updated_at = now()
    where  user_id = p_target_user_id
      and  restriction_type = p_action_type
      and  is_active = true;

    insert into public.admin_user_restrictions
      (user_id, restriction_type, is_active, reason, expires_at, created_by)
    values
      (p_target_user_id, p_action_type, true, p_reason, p_expires_at, v_admin_id);
  end if;

  -- Mark moderation event reviewed
  if p_event_id is not null then
    update public.moderation_events
    set status = case when p_action_type = 'dismissed' then 'dismissed' else 'reviewed' end,
        action_taken = p_action_type
    where id = p_event_id;
  end if;

  -- Mark report resolved/rejected
  if p_report_id is not null then
    update public.user_reports
    set status      = case when p_action_type = 'dismissed' then 'rejected' else 'resolved' end,
        resolved_by = v_admin_id,
        resolved_at = now(),
        resolution_note = p_action_type || ': ' || p_reason
    where id = p_report_id;
  end if;

  -- Audit log
  insert into public.admin_audit_logs
    (admin_user_id, target_user_id, action, entity_type, metadata)
  values
    (v_admin_id, p_target_user_id, 'moderation_action', 'moderation', jsonb_build_object(
      'action_type', p_action_type,
      'reason',      p_reason,
      'room_id',     p_room_id,
      'expires_at',  p_expires_at,
      'event_id',    p_event_id,
      'report_id',   p_report_id
    ));
end;
$$;

grant execute on function public.admin_apply_moderation_action(uuid,text,text,uuid,timestamptz,uuid,uuid)
  to authenticated;

-- ── 7. admin_get_moderation_events() ─────────────────────────────────────────

create or replace function public.admin_get_moderation_events(
  p_limit  int  default 100,
  p_status text default null
) returns table (
  id             uuid,
  user_id        uuid,
  user_name      text,
  room_id        uuid,
  source         text,
  violation_type text,
  severity       int,
  original_text  text,
  matched_rule   text,
  action_taken   text,
  status         text,
  created_at     timestamptz
)
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.has_admin_access() then
    raise exception 'permission_denied: admin access required';
  end if;

  return query
  select
    me.id,
    me.user_id,
    coalesce(p.display_name, p.username, 'Unknown'),
    me.room_id,
    me.source,
    me.violation_type,
    me.severity,
    me.original_text,
    me.matched_rule,
    me.action_taken,
    me.status,
    me.created_at
  from   public.moderation_events me
  left   join public.profiles p on p.id = me.user_id
  where  (p_status is null or me.status = p_status)
  order by me.created_at desc
  limit  p_limit;
end;
$$;

grant execute on function public.admin_get_moderation_events(int,text)
  to authenticated;
