-- Prevent stale flying rounds from overflowing numeric(12,2). Rocket targets
-- are authoritatively capped at 1000x, so the live display curve never needs
-- to grow beyond that same bound.
create or replace function public._crash_rocket_multiplier_at(
  p_fly_started_at timestamptz,
  p_at timestamptz
)
returns numeric
language sql immutable
set search_path = ''
as $$
  select least(
    1000.00,
    greatest(
      1.00,
      floor(
        exp(
          least(
            ln(1000.00),
            0.09 * greatest(
              0,
              extract(epoch from p_at - p_fly_started_at)
            )
          )
        ) * 100
      ) / 100
    )
  )::numeric(12,2);
$$;

revoke all on function public._crash_rocket_multiplier_at(
  timestamptz,
  timestamptz
) from public, anon, authenticated;

-- Recover any rounds that became stuck before the guarded calculation existed.
do $$
declare
  v_room_id uuid;
begin
  perform public.advance_crash_rocket_round(null);

  for v_room_id in
    select distinct room_id
    from public.crash_rocket_rounds
    where room_id is not null
      and status in ('waiting', 'betting_open', 'flying', 'crashed')
  loop
    perform public.advance_crash_rocket_round(v_room_id);
  end loop;
end;
$$;
