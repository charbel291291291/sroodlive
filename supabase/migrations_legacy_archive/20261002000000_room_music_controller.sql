-- Add controller_user_id and auto_replay to room_music_state.
--
-- controller_user_id: the user who started the current track.
--   Set to auth.uid() when a new track begins (different URL from current row).
--   Cleared when music is stopped.
--   Preserved on pause / resume (track unchanged).
--
-- auto_replay: when true the controller's device restarts the same
--   track after it finishes. Only the controller's client triggers
--   the replay push so listeners never cause duplicate restarts.
--
-- Permission rules enforced by the RPCs below:
--   set_room_music_state: any room manager may start a NEW track (becomes
--     controller). Only the controller may pause/resume/change auto_replay
--     on an existing track. A super_admin bypasses the controller check.
--   stop_room_music: only the controller (or a super_admin) may stop music.
--     If no controller is set the stop is a safe no-op.

ALTER TABLE public.room_music_state
  ADD COLUMN IF NOT EXISTS controller_user_id uuid
      REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS auto_replay boolean NOT NULL DEFAULT false;

-- ----------------------------------------------------------------------------
-- RPC: set_room_music_state
-- ----------------------------------------------------------------------------
-- Adds p_auto_replay; enforces controller ownership for pause/resume/replay.
-- Starting a new track (different URL) is allowed for any room manager and
-- transfers controller ownership to the caller.

CREATE OR REPLACE FUNCTION public.set_room_music_state(
  p_room_id          uuid,
  p_track_id         text,
  p_track_title      text,
  p_track_artist     text,
  p_track_url        text,
  p_is_playing       boolean,
  p_position_seconds integer  DEFAULT 0,
  p_auto_replay      boolean  DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid            uuid        := auth.uid();
  v_now            timestamptz := now();
  v_started_at     timestamptz;
  v_paused_at      timestamptz;
  v_controller_id  uuid;
  v_result         json;
  v_current_url    text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  IF NOT public.is_room_manager(p_room_id, v_uid) THEN
    RAISE EXCEPTION 'not_room_manager';
  END IF;

  -- Derive timestamps
  IF p_is_playing THEN
    v_started_at := v_now;
    v_paused_at  := NULL;
  ELSE
    v_started_at := NULL;
    v_paused_at  := v_now;
  END IF;

  -- Decide controller ownership:
  --   New track (URL changed)  -> caller becomes controller regardless of role.
  --   Same track (pause/resume/auto_replay toggle) -> only existing controller
  --     (or a super_admin) may update. Others are rejected.
  SELECT track_url, controller_user_id
    INTO v_current_url, v_controller_id
    FROM public.room_music_state
   WHERE room_id = p_room_id;

  IF v_current_url IS DISTINCT FROM p_track_url THEN
    -- New track: transfer controller to caller.
    v_controller_id := v_uid;
  ELSE
    -- Same track: controller check.
    IF v_controller_id IS NOT NULL
       AND v_controller_id <> v_uid
       AND NOT public.is_super_admin(v_uid) THEN
      RAISE EXCEPTION 'not_music_controller';
    END IF;
    -- v_controller_id stays unchanged (preserve ownership on pause/resume).
  END IF;

  INSERT INTO public.room_music_state (
    room_id, track_id, track_title, track_artist, track_url,
    is_playing, started_at, paused_at, position_seconds,
    controller_user_id, auto_replay,
    updated_by, updated_at
  )
  VALUES (
    p_room_id, p_track_id, p_track_title, p_track_artist, p_track_url,
    p_is_playing, v_started_at, v_paused_at, p_position_seconds,
    v_controller_id, p_auto_replay,
    v_uid, v_now
  )
  ON CONFLICT (room_id) DO UPDATE SET
    track_id           = EXCLUDED.track_id,
    track_title        = EXCLUDED.track_title,
    track_artist       = EXCLUDED.track_artist,
    track_url          = EXCLUDED.track_url,
    is_playing         = EXCLUDED.is_playing,
    started_at         = EXCLUDED.started_at,
    paused_at          = EXCLUDED.paused_at,
    position_seconds   = EXCLUDED.position_seconds,
    controller_user_id = EXCLUDED.controller_user_id,
    auto_replay        = EXCLUDED.auto_replay,
    updated_by         = EXCLUDED.updated_by,
    updated_at         = EXCLUDED.updated_at
  RETURNING to_json(room_music_state.*) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_room_music_state(uuid, text, text, text, text, boolean, integer, boolean)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: stop_room_music
-- ----------------------------------------------------------------------------
-- Only the controller (or a super_admin) may stop music.
-- If no controller is set (music already stopped) the call is a safe no-op.

CREATE OR REPLACE FUNCTION public.stop_room_music(p_room_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid            uuid := auth.uid();
  v_controller_id  uuid;
  v_result         json;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  -- Load current controller.
  SELECT controller_user_id
    INTO v_controller_id
    FROM public.room_music_state
   WHERE room_id = p_room_id;

  -- No active controller means music is already stopped or never started.
  IF v_controller_id IS NULL THEN
    RETURN json_build_object(
      'room_id',    p_room_id,
      'is_playing', false,
      'track_id',   NULL,
      'updated_at', now()
    );
  END IF;

  -- Only the controller or a super_admin may stop music.
  IF v_controller_id <> v_uid AND NOT public.is_super_admin(v_uid) THEN
    RAISE EXCEPTION 'not_music_controller';
  END IF;

  UPDATE public.room_music_state
     SET is_playing         = false,
         started_at         = NULL,
         paused_at          = NULL,
         position_seconds   = 0,
         track_id           = NULL,
         track_title        = NULL,
         track_artist       = NULL,
         track_url          = NULL,
         controller_user_id = NULL,
         auto_replay        = false,
         updated_by         = v_uid,
         updated_at         = now()
   WHERE room_id = p_room_id
  RETURNING to_json(room_music_state.*) INTO v_result;

  IF v_result IS NULL THEN
    v_result := json_build_object(
      'room_id',    p_room_id,
      'is_playing', false,
      'track_id',   NULL,
      'updated_at', now()
    );
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.stop_room_music(uuid) TO authenticated;
