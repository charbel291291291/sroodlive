-- =============================================================================
-- Moderation Evidence Snapshot
-- Adds: moderation_report_evidence table,
--       submit_user_report_with_evidence RPC,
--       admin_get_report_evidence RPC
-- Privacy: evidence rows are NOT readable by normal users.
-- =============================================================================

-- ── 1. moderation_report_evidence ────────────────────────────────────────────

create table if not exists public.moderation_report_evidence (
  id                  uuid        primary key default gen_random_uuid(),
  report_id           uuid        not null references public.user_reports(id) on delete cascade,
  room_id             uuid        references public.rooms(id) on delete set null,
  reporter_id         uuid        not null references auth.users(id) on delete cascade,
  reported_user_id    uuid        not null references auth.users(id) on delete cascade,
  evidence_type       text        not null default 'chat_snapshot',
  message_id          uuid,
  sender_id           uuid        references auth.users(id) on delete set null,
  sender_display_name text,
  message_text        text,
  message_created_at  timestamptz,
  is_reported_user    boolean     not null default false,
  metadata            jsonb       not null default '{}'::jsonb,
  created_at          timestamptz not null default now()
);

create index if not exists idx_mod_evidence_report
  on public.moderation_report_evidence (report_id, message_created_at asc);

alter table public.moderation_report_evidence enable row level security;

-- Normal users cannot read evidence
drop policy if exists "evidence_admin_select" on public.moderation_report_evidence;
create policy "evidence_admin_select"
  on public.moderation_report_evidence for select
  to authenticated
  using (public.has_admin_access());

-- No insert/update/delete policies for normal users — RPC uses security definer
grant select on public.moderation_report_evidence to authenticated;

-- ── 2. submit_user_report_with_evidence() ────────────────────────────────────
--    Replaces client-side `submit_user_report` for room reports.
--    Evidence is captured server-side from room_messages — never from Flutter.

create or replace function public.submit_user_report_with_evidence(
  p_reported_user_id  uuid,
  p_room_id           uuid    default null,
  p_reason            text    default 'other',
  p_description       text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter_id   uuid := auth.uid();
  v_report_id     uuid;
  v_msg           record;
  v_sender_name   text;
begin
  if v_reporter_id is null then
    raise exception 'auth_required';
  end if;

  if v_reporter_id = p_reported_user_id then
    raise exception 'cannot_report_self';
  end if;

  -- Inherit rate-limit from existing submit_user_report: max 5 per hour
  if (
    select count(*) from public.user_reports
    where  reporter_id = v_reporter_id
      and  created_at >= now() - interval '1 hour'
  ) >= 5 then
    raise exception 'rate_limited: max 5 reports per hour';
  end if;

  -- Insert the report
  insert into public.user_reports
    (reporter_id, target_type, target_id, reason, details)
  values
    (v_reporter_id,
     'user',
     p_reported_user_id::text,
     p_reason,
     p_description)
  returning id into v_report_id;

  -- Capture last 10 room messages as evidence (server-side only)
  if p_room_id is not null then
    for v_msg in (
      select
        rm.id,
        rm.sender_id,
        rm.message,
        rm.created_at
      from   public.room_messages rm
      where  rm.room_id = p_room_id
        and  rm.created_at <= now()
      order  by rm.created_at desc
      limit  10
    ) loop
      -- Resolve display name inside the loop (avoids N+1 with index lookup)
      select coalesce(p.display_name, p.username, null)
      into   v_sender_name
      from   public.profiles p
      where  p.id = v_msg.sender_id;

      insert into public.moderation_report_evidence
        (report_id, room_id, reporter_id, reported_user_id,
         evidence_type, message_id, sender_id, sender_display_name,
         message_text, message_created_at, is_reported_user,
         metadata)
      values
        (v_report_id, p_room_id, v_reporter_id, p_reported_user_id,
         'chat_snapshot', v_msg.id, v_msg.sender_id, v_sender_name,
         v_msg.message, v_msg.created_at,
         (v_msg.sender_id = p_reported_user_id),
         jsonb_build_object(
           'report_reason',      p_reason,
           'report_description', p_description
         ));
    end loop;
  end if;

  return v_report_id;
end;
$$;

grant execute on function public.submit_user_report_with_evidence(uuid, uuid, text, text)
  to authenticated;

-- ── 3. admin_get_report_evidence() ───────────────────────────────────────────

create or replace function public.admin_get_report_evidence(
  p_report_id uuid
)
returns table (
  id                  uuid,
  message_id          uuid,
  sender_id           uuid,
  sender_display_name text,
  message_text        text,
  message_created_at  timestamptz,
  is_reported_user    boolean,
  room_id             uuid
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_admin_access() then
    raise exception 'permission_denied: admin access required';
  end if;

  return query
  select
    e.id,
    e.message_id,
    e.sender_id,
    e.sender_display_name,
    e.message_text,
    e.message_created_at,
    e.is_reported_user,
    e.room_id
  from   public.moderation_report_evidence e
  where  e.report_id = p_report_id
    and  e.evidence_type = 'chat_snapshot'
  order  by e.message_created_at asc;
end;
$$;

grant execute on function public.admin_get_report_evidence(uuid)
  to authenticated;
