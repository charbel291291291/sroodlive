-- =============================================================================
-- Additive: expose selected_avatar_frame_key and vip_level on the Srood
-- Blocks weekly leaderboard RPC so its leaderboard tile can render each
-- player's equipped frame (Frame System v2 migration) instead of a plain
-- circle avatar.
--
-- Postgres does not allow CREATE OR REPLACE FUNCTION to change the OUT
-- column list of a RETURNS TABLE function (unlike CREATE OR REPLACE VIEW,
-- which permits appending columns), so the function must be dropped and
-- recreated. This only redefines the function body/signature — no data or
-- tables are touched.
-- =============================================================================

drop function if exists public.get_srood_blocks_weekly_leaderboard(integer);

create function public.get_srood_blocks_weekly_leaderboard(p_limit integer default 50)
returns table (
  rank         bigint,
  user_id      uuid,
  display_name text,
  avatar_url   text,
  best_score   integer,
  total_lines  bigint,
  frame_key    text,
  vip_level    integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_start date := date_trunc('week', current_date)::date;
begin
  return query
  with best as (
    select
      s.user_id,
      max(s.score)          as best_score,
      sum(s.lines_cleared)  as total_lines
    from public.srood_blocks_scores s
    where s.week_start = v_week_start
    group by s.user_id
  )
  select
    row_number() over (order by b.best_score desc, b.total_lines desc) as rank,
    b.user_id,
    coalesce(p.display_name, p.username, 'Player')::text,
    p.avatar_url::text,
    b.best_score::integer,
    b.total_lines,
    p.selected_avatar_frame_key::text,
    coalesce(p.vip_level, 0)::integer
  from best b
  left join public.profiles p on p.id = b.user_id
  order by b.best_score desc, b.total_lines desc
  limit least(p_limit, 100);
end;
$$;

grant execute on function public.get_srood_blocks_weekly_leaderboard(integer) to authenticated;
