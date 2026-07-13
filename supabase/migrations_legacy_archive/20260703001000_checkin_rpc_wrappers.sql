-- =============================================================================
-- Gamification check-in RPCs (wrappers over the unified daily reward system).
--
-- get_my_checkin_status  → delegates to get_daily_reward_state and reshapes
--                          output to match the legacy CheckinStatus model.
-- claim_daily_checkin    → thin wrapper around claim_daily_reward.
--
-- Both were previously missing from migrations (schema drift). The Flutter
-- CheckinScreen has been rewritten to call DailyRewardService directly, but
-- these wrappers are kept for DB completeness and any future callers.
-- =============================================================================

create or replace function public.get_my_checkin_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_state    jsonb;
  v_dates    jsonb;
  v_schedule jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  v_state := public.get_daily_reward_state();

  -- Build last_7_dates list from the audit ledger.
  select coalesce(
    jsonb_agg(to_char(claimed_date, 'YYYY-MM-DD') order by claimed_date desc),
    '[]'::jsonb
  )
  into v_dates
  from public.daily_reward_claims
  where user_id = v_uid
    and claimed_date >= (now() at time zone 'utc')::date - 6;

  -- Reshape rules array → CheckinReward format.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'day',           (r->>'day_number')::integer,
        'reward_type',   r->>'reward_type',
        'reward_amount', (r->>'amount')::integer
      ) order by (r->>'day_number')::integer
    ),
    '[]'::jsonb
  )
  into v_schedule
  from jsonb_array_elements(v_state->'rules') as r;

  return jsonb_build_object(
    'today_claimed',  v_state->'claimed_today',
    'streak',         v_state->'streak_count',
    'streak_day',     v_state->'claim_day',
    'last_7_dates',   v_dates,
    'reward_schedule', v_schedule
  );
end;
$$;
grant execute on function public.get_my_checkin_status() to authenticated;


create or replace function public.claim_daily_checkin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  v_result := public.claim_daily_reward();
  -- Remap to the legacy claim-response shape.
  return jsonb_build_object(
    'reward_type',   v_result->'reward_type',
    'reward_amount', v_result->'amount',
    'streak',        v_result->'streak_count'
  );
end;
$$;
grant execute on function public.claim_daily_checkin() to authenticated;
