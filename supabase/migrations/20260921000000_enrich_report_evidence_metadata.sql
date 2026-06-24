-- Enrich moderation report evidence with trusted room/seat/role context
--
-- submit_user_report_with_evidence previously stored only report_reason and
-- report_description in each evidence row's metadata. This update adds a
-- server-side context snapshot read from:
--   room_members   → reported user's role, seat_number, is_muted, force_muted
--   room_members   → reporter's role
--   room_moderators→ whether reported user is a room moderator
--   rooms          → whether reported user is the room owner
--
-- No client-supplied data is used for this context — all values are read from
-- trusted database state inside the SECURITY DEFINER function.
--
-- Existing behavior preserved:
--   - rate limit (5/hour)
--   - cannot_report_self guard
--   - last-10-messages chat snapshot
--   - admin-only evidence RLS
--
-- Idempotent: CREATE OR REPLACE.

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
  v_reporter_id           uuid    := auth.uid();
  v_report_id             uuid;
  v_msg                   record;
  v_sender_name           text;

  -- Trusted room context — read from DB, never from client
  v_reported_role         text;
  v_reported_seat         integer;
  v_reported_is_muted     boolean;
  v_reported_force_muted  boolean;
  v_reported_is_mod       boolean := false;
  v_reported_is_owner     boolean := false;
  v_reporter_role         text;
begin
  if v_reporter_id is null then
    raise exception 'auth_required';
  end if;

  if v_reporter_id = p_reported_user_id then
    raise exception 'cannot_report_self';
  end if;

  -- Rate-limit: max 5 reports per user per hour
  if (
    select count(*) from public.user_reports
    where  reporter_id = v_reporter_id
      and  created_at >= now() - interval '1 hour'
  ) >= 5 then
    raise exception 'rate_limited: max 5 reports per hour';
  end if;

  -- ── Trusted room context snapshot ───────────────────────────────────────────
  if p_room_id is not null then
    -- Reported user's active room_members row
    select role, seat_number, is_muted, force_muted
    into   v_reported_role, v_reported_seat, v_reported_is_muted, v_reported_force_muted
    from   public.room_members
    where  room_id = p_room_id
      and  user_id = p_reported_user_id
      and  left_at is null;

    -- Reporter's active role
    select role
    into   v_reporter_role
    from   public.room_members
    where  room_id = p_room_id
      and  user_id = v_reporter_id
      and  left_at is null;

    -- Whether reported user is a room moderator
    select exists(
      select 1 from public.room_moderators
      where  room_id = p_room_id
        and  user_id = p_reported_user_id
    ) into v_reported_is_mod;

    -- Whether reported user is the room owner
    select (owner_id = p_reported_user_id)
    into   v_reported_is_owner
    from   public.rooms
    where  id = p_room_id;
  end if;

  -- Insert the report
  insert into public.user_reports
    (reporter_id, target_type, target_id, reason, details)
  values
    (v_reporter_id, 'user', p_reported_user_id::text, p_reason, p_description)
  returning id into v_report_id;

  -- Capture last 10 room messages as evidence (server-side only)
  if p_room_id is not null then
    for v_msg in (
      select rm.id, rm.sender_id, rm.message, rm.created_at
      from   public.room_messages rm
      where  rm.room_id = p_room_id
        and  rm.created_at <= now()
      order  by rm.created_at desc
      limit  10
    ) loop
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
           -- Report content
           'report_reason',           p_reason,
           'report_description',      p_description,
           -- Reported user context (trusted server-side)
           'reported_role',           v_reported_role,
           'reported_seat_number',    v_reported_seat,
           'reported_is_muted',       v_reported_is_muted,
           'reported_force_muted',    v_reported_force_muted,
           'reported_is_moderator',   v_reported_is_mod,
           'reported_is_owner',       v_reported_is_owner,
           -- Reporter context
           'reporter_role',           v_reporter_role
         ));
    end loop;
  end if;

  return v_report_id;
end;
$$;

-- Grant unchanged — authenticated users may still call this function.
grant execute on function public.submit_user_report_with_evidence(uuid, uuid, text, text)
  to authenticated;
