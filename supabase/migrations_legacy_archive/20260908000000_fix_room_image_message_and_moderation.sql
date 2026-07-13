-- =============================================================================
-- Fix room image messages + add moderation guard (2026-09-08)
--
-- ROOT CAUSE of "VIP can't send images": room_messages has a CHECK constraint
--   room_messages_message_check: CHECK (char_length(message) BETWEEN 1 AND 300)
-- Image messages legitimately carry an empty `message` ('') — the photo lives in
-- image_url. send_room_image_message inserts message='' and the constraint
-- rejected it (sqlstate 23514), so the upload succeeded but the message row was
-- never created and nothing appeared in chat. Proven against production:
-- 12 uploaded objects, 0 image rows.
--
-- Fix 1: relax the constraint so non-text messages (image/system) may have an
--        empty body, while text messages keep the 1..300 rule.
-- Fix 2: add a server-side mute/ban guard to send_room_image_message so muted /
--        room-banned users cannot post images (the text path already checks
--        check_user_active_mute client-side; this enforces it server-side for
--        the SECURITY DEFINER image path, which bypasses RLS).
--
-- The VIP 7 gate is unchanged. Idempotent.
-- =============================================================================

-- ── Fix 1: message length constraint allows empty body for non-text types ─────
alter table public.room_messages
  drop constraint if exists room_messages_message_check;

alter table public.room_messages
  add constraint room_messages_message_check
  check (
    char_length(message) <= 300
    and (message_type <> 'text' or char_length(message) >= 1)
  );

-- ── Fix 2: send_room_image_message — VIP7 (unchanged) + mute/ban guard ────────
create or replace function public.send_room_image_message(
  p_room_id     uuid,
  p_image_url   text,
  p_image_path  text,
  p_sender_role text default 'listener'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_message_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- VIP 7 gate (unchanged).
  if not public.can_user_send_chat_image(v_user_id) then
    raise exception 'image_messages_unlock_at_vip_7';
  end if;

  -- Moderation guard: muted (chat_mute / force_muted) or room-banned users
  -- cannot send images, mirroring the text path's mute enforcement.
  if (public.check_user_active_mute(p_room_id) ->> 'muted')::boolean then
    raise exception 'user_muted';
  end if;

  if p_room_id is null then
    raise exception 'missing_room_id';
  end if;

  if coalesce(trim(p_image_url), '') = '' then
    raise exception 'missing_image_url';
  end if;

  -- path owner check: first segment must be the caller's user_id
  if split_part(coalesce(p_image_path, ''), '/', 1) <> v_user_id::text then
    raise exception 'invalid_image_path_owner';
  end if;

  -- room existence guard
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'room_not_found';
  end if;

  insert into public.room_messages
    (room_id, sender_id, message, message_type, image_url, image_path, metadata)
  values
    (p_room_id, v_user_id, '', 'image', p_image_url, p_image_path,
     jsonb_build_object('role', coalesce(nullif(p_sender_role, ''), 'listener')))
  returning id into v_message_id;

  return jsonb_build_object(
    'id',         v_message_id,
    'room_id',    p_room_id,
    'image_url',  p_image_url,
    'image_path', p_image_path
  );
end;
$$;

grant execute on function public.send_room_image_message(uuid, text, text, text)
  to authenticated;

-- =============================================================================
-- End of 20260908000000_fix_room_image_message_and_moderation.sql
-- =============================================================================
