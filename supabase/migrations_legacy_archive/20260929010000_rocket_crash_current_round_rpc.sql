-- Read-only RPC: get current active rocket crash round without taking advisory lock.
-- Used by the 8-second reconciliation poll in Flutter as a lightweight alternative
-- to get_or_create_rocket_crash_round (which takes pg_advisory_xact_lock and can
-- contend with the pg_cron advance function under load).
--
-- Returns JSON with the current betting or flying round, or null if none active.
-- Never inserts, never takes a lock.

create or replace function public.get_rocket_crash_current_round()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_round  public.rocket_crash_global_rounds;
  v_now    timestamptz := now();
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  -- Active betting window
  select * into v_round
  from public.rocket_crash_global_rounds
  where status = 'betting' and betting_ends_at > v_now
  order by created_at desc
  limit 1;

  -- Fallback: flying round that started within the last 120 seconds
  if v_round.id is null then
    select * into v_round
    from public.rocket_crash_global_rounds
    where status = 'flying'
      and flight_starts_at > v_now - interval '120 seconds'
    order by created_at desc
    limit 1;
  end if;

  if v_round.id is null then
    return null;
  end if;

  return json_build_object(
    'round_id',         v_round.id,
    'round_number',     v_round.round_number,
    'status',           v_round.status,
    'betting_ends_at',  extract(epoch from v_round.betting_ends_at) * 1000,
    'flight_starts_at', case when v_round.flight_starts_at is not null
                            then extract(epoch from v_round.flight_starts_at) * 1000
                            else null end,
    'crash_multiplier', case when v_round.status = 'crashed'
                            then v_round.crash_multiplier
                            else null end,
    'server_now',       extract(epoch from v_now) * 1000
  );
end;
$$;

grant execute on function public.get_rocket_crash_current_round() to authenticated;
