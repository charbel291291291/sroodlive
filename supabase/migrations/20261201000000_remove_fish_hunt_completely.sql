BEGIN;

DO $$
DECLARE
  r RECORD;
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    FOR r IN
      SELECT jobid
      FROM cron.job
      WHERE COALESCE(jobname, '') ILIKE '%fish_hunt%'
         OR COALESCE(command, '') ILIKE '%fish_hunt%'
    LOOP
      IF to_regclass('cron.job_run_details') IS NOT NULL THEN
        DELETE FROM cron.job_run_details
        WHERE jobid = r.jobid;
      END IF;

      PERFORM cron.unschedule(r.jobid);
    END LOOP;
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'fish_hunt_fish'
  ) THEN
    ALTER PUBLICATION supabase_realtime
    DROP TABLE public.fish_hunt_fish;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'fish_hunt_rounds'
  ) THEN
    ALTER PUBLICATION supabase_realtime
    DROP TABLE public.fish_hunt_rounds;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'fish_hunt_shots'
  ) THEN
    ALTER PUBLICATION supabase_realtime
    DROP TABLE public.fish_hunt_shots;
  END IF;
END
$$;

DROP FUNCTION IF EXISTS public.advance_fish_hunt_round() CASCADE;
DROP FUNCTION IF EXISTS public.fish_hunt_get_state(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.fish_hunt_get_leaderboard(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.fish_hunt_place_shot(
  uuid,
  uuid,
  bigint,
  text
) CASCADE;

DROP TABLE IF EXISTS public.fish_hunt_shots CASCADE;
DROP TABLE IF EXISTS public.fish_hunt_fish CASCADE;
DROP TABLE IF EXISTS public.fish_hunt_rounds CASCADE;

COMMIT;
