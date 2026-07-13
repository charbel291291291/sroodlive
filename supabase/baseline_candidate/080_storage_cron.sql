-- =============================================================================
-- Baseline 080 — storage buckets, cron jobs, realtime publication.
-- These are CONFIGURATION rows/objects that a schema-only dump does NOT emit
-- (bucket rows, cron.job rows, publication membership). Reconstructed with
-- EXACT read-only production values. No storage.objects rows, no cron run
-- history, no application/user/message/financial data.
-- Idempotent + conflict-safe so it is replay-safe and never broadens exposure.
-- =============================================================================

-- ── 8 storage buckets (exact public/limit/mime config) ───────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('admin-assets','admin-assets',true, null, null),
  ('app_releases','app_releases',true, 600000000, array['application/vnd.android.package-archive','application/octet-stream']),
  ('avatars','avatars',true, 5242880, array['image/jpeg','image/png','image/webp','image/gif']),
  ('room_avatars','room_avatars',true, 2097152, array['image/jpeg','image/png','image/webp']),
  ('room_chat_images','room_chat_images',true, 5242880, array['image/jpeg','image/png','image/webp','image/jpg']),
  ('room_covers','room_covers',true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('room_music','room_music',true, 15728640, array['audio/mpeg','audio/mp3','audio/wav','audio/aac','audio/mp4','audio/m4a','audio/ogg']),
  ('room-backgrounds','room-backgrounds',true, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
-- Storage POLICIES are already reproduced verbatim by the schema dump (DDL);
-- none are added here to avoid duplication.

-- ── 5 cron jobs (exact name / schedule / command; active) ────────────────────
-- cron.schedule(name,...) upserts by name (no duplicates). Registration only —
-- it does NOT invoke the job functions during baseline application. Guarded so
-- it is a no-op when pg_cron is unavailable (e.g. bare validation container).
do $$
begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('cleanup-cron-history','0 3 1 * *',
      $cron$ delete from cron.job_run_details where start_time < now() - interval '90 days'; $cron$);
    perform cron.schedule('fish_hunt_auto_advance','5 seconds', $cron$ select public.advance_fish_hunt_round(); $cron$);
    perform cron.schedule('reset-room-streaks','0 0 * * *', $cron$ select public.update_room_streaks() $cron$);
    perform cron.schedule('reset-room-week-xp','5 0 * * 1', $cron$ select public.reset_room_weekly_xp() $cron$);
    perform cron.schedule('roulette_auto_advance','3 seconds', $cron$ select public.advance_roulette_round(); $cron$);
  else
    raise notice 'cron schema not present; skipping cron registration (validation env)';
  end if;
end $$;

-- ── Realtime publication membership (exact 25 public tables; no broadening) ───
-- The platform owns `supabase_realtime`; ensure it exists locally, then add ONLY
-- the exact production tables, skipping any already a member (no duplicate error).
do $$
declare v_tbl text;
begin
  if not exists (select 1 from pg_publication where pubname='supabase_realtime') then
    create publication supabase_realtime;  -- local validation only; platform provides in prod
  end if;
  foreach v_tbl in array array[
    'rooms','room_members','gift_transactions','wc_matches','wc_predictions','room_messages',
    'room_team_pk_sessions','room_team_pk_members','room_team_pk_support_logs','room_game_rounds',
    'room_game_bets','room_music_state','room_music_tracks','red_envelopes','red_envelope_claims',
    'hungry_cat_global_rounds','rocket_crash_global_rounds','user_wealth','room_reads',
    'magic_srood_global_rounds','fish_hunt_rounds','fish_hunt_fish','crash_rocket_rounds',
    'crash_rocket_round_events','room_youtube_state'
  ] loop
    if to_regclass('public.'||v_tbl) is not null
       and not exists (select 1 from pg_publication_tables
                       where pubname='supabase_realtime' and schemaname='public' and tablename=v_tbl) then
      execute format('alter publication supabase_realtime add table public.%I', v_tbl);
    end if;
  end loop;
end $$;
-- supabase_realtime_messages_publication is platform/realtime-managed
-- (realtime.messages_* partitions); intentionally NOT reproduced here.
