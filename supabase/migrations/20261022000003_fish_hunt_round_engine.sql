-- =============================================================================
-- Srood Fish Hunt round engine.
--
-- fish_hunt_foundation.sql created the tables/RPCs but never started a round
-- or spawned any fish, so fish_hunt_get_state always returned an empty board.
-- This adds the auto-advance function (creates a global round if none is
-- active, tops up alive fish, expires stale ones) and schedules it via
-- pg_cron, mirroring the Rocket Crash auto-advance pattern.
-- =============================================================================

create or replace function public.advance_fish_hunt_round()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round_id     uuid;
  v_alive_count  integer;
  v_target_count constant integer := 8;
  v_to_spawn     integer;
  v_fish_type    text;
  v_multiplier   numeric;
  v_hit_prob     numeric;
  v_roll         double precision;
begin
  -- Expire fish whose window has passed.
  update public.fish_hunt_fish
  set status = 'expired'
  where status = 'alive'
    and expires_at <= now();

  -- Ensure a single global active round exists (room_id stays null — Fish
  -- Hunt currently runs one shared board, matching fish_hunt_get_state's
  -- "most recent active round" lookup when p_room_id is null).
  select id
  into v_round_id
  from public.fish_hunt_rounds
  where status = 'active'
    and room_id is null
  order by started_at desc
  limit 1;

  if v_round_id is null then
    insert into public.fish_hunt_rounds (room_id, status)
    values (null, 'active')
    returning id into v_round_id;
  end if;

  select count(*)
  into v_alive_count
  from public.fish_hunt_fish
  where round_id = v_round_id
    and status = 'alive';

  v_to_spawn := greatest(v_target_count - v_alive_count, 0);

  for i in 1..v_to_spawn loop
    v_roll := random();
    if v_roll < 0.55 then
      v_fish_type := 'small';
      v_multiplier := 1.5 + random() * 1.0;   -- 1.5x - 2.5x
      v_hit_prob := 0.55 + random() * 0.15;   -- 55% - 70%
    elsif v_roll < 0.85 then
      v_fish_type := 'medium';
      v_multiplier := 3.0 + random() * 2.0;   -- 3x - 5x
      v_hit_prob := 0.30 + random() * 0.15;   -- 30% - 45%
    else
      v_fish_type := 'large';
      v_multiplier := 6.0 + random() * 6.0;   -- 6x - 12x
      v_hit_prob := 0.10 + random() * 0.10;   -- 10% - 20%
    end if;

    insert into public.fish_hunt_fish (
      round_id, fish_type, reward_multiplier, hit_probability,
      spawned_at, expires_at
    )
    values (
      v_round_id, v_fish_type, v_multiplier, v_hit_prob,
      now(), now() + interval '20 seconds'
    );
  end loop;
end;
$$;

-- Intentionally NOT granted to authenticated — only the cron job runs this.
revoke all on function public.advance_fish_hunt_round()
  from public, anon, authenticated;

-- ── pg_cron auto-advance job ─────────────────────────────────────────────────
-- Mirrors rocket_crash_auto_advance. Installed only if pg_cron is available.

do $$
declare
  v_job_name text := 'fish_hunt_auto_advance';
begin
  if not exists (
    select 1 from pg_catalog.pg_extension where extname = 'pg_cron'
  ) then
    raise notice 'pg_cron not available — Fish Hunt auto-advance will need manual/cron setup';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = v_job_name) then
    perform cron.unschedule(v_job_name);
  end if;

  begin
    -- Finest cadence: every 5 seconds (requires pg_cron >= 1.4)
    perform cron.schedule(
      v_job_name,
      '5 seconds',
      $cron$ select public.advance_fish_hunt_round(); $cron$
    );
    raise notice 'Fish Hunt auto-advance cron job scheduled (every 5 seconds)';
  exception when others then
    perform cron.schedule(
      v_job_name,
      '* * * * *',
      $cron$ select public.advance_fish_hunt_round(); $cron$
    );
    raise notice 'Fish Hunt auto-advance cron job scheduled (every minute — seconds syntax unavailable)';
  end;
end;
$$;
