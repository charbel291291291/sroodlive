create extension if not exists pg_cron;

-- Crash V3 engine cron invoker.
--
-- The crash-v3-engine Edge Function only ticks the round state machine
-- while it is actively running (it self-terminates after ~50s per
-- invocation and must be re-invoked continuously). This job re-invokes it
-- on a schedule via pg_net, mirroring the existing fish_hunt_auto_advance /
-- roulette_auto_advance pattern in this project.
--
-- The shared x-crash-engine-secret header value is pulled from
-- vault.decrypted_secrets at invocation time (name: crash_v3_engine_secret)
-- rather than embedded literally, so this tracked migration file never
-- contains the raw secret. The same value must be set as the
-- CRASH_V3_ENGINE_SECRET Edge Function secret for requests to authenticate.
--
-- Invocations are scheduled every 40s with a 55s request timeout: each
-- invocation runs for up to 50s internally, so consecutive invocations
-- overlap briefly, keeping the engine's 15s lease continuously renewed
-- even if one invocation errors out early. Overlapping invocations are
-- safe by design (advisory lock + lease keyed on a single primary row).

select cron.unschedule(jobid)
from cron.job
where jobname = 'crash_v3_engine_invoke';

do $$
begin
  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'crash_v3_engine_url'
      and nullif(decrypted_secret, '') is not null
  ) then
    raise exception 'missing vault secret: crash_v3_engine_url';
  end if;
  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'crash_v3_publishable_key'
      and nullif(decrypted_secret, '') is not null
  ) then
    raise exception 'missing vault secret: crash_v3_publishable_key';
  end if;
  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'crash_v3_engine_secret'
      and nullif(decrypted_secret, '') is not null
  ) then
    raise exception 'missing vault secret: crash_v3_engine_secret';
  end if;
end
$$;

select cron.schedule(
  'crash_v3_engine_invoke',
  '40 seconds',
  $$
  select net.http_post(
    url := (
      select decrypted_secret
      from vault.decrypted_secrets
      where name = 'crash_v3_engine_url'
    ),
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'crash_v3_publishable_key'
      ),
      'apikey', (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'crash_v3_publishable_key'
      ),
      'x-crash-engine-secret', (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'crash_v3_engine_secret'
      )
    ),
    timeout_milliseconds := 55000
  );
  $$
);
