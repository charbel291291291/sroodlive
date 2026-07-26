-- =============================================================================
-- Additive: expose selected_avatar_frame_key on the leaderboard views so the
-- leaderboard screen can render each user's equipped frame (Frame System v2
-- migration) instead of a plain circle avatar. Appended as the last column so
-- CREATE OR REPLACE VIEW stays valid (Postgres forbids removing/reordering
-- existing view columns, but appending is safe).
-- =============================================================================

create or replace view public.v_leaderboard_earners as
select
  p.id,
  p.display_name,
  p.avatar_url,
  coalesce(p.vip_level, 0) as vip_level,
  coalesce(sum(gt.quantity), 0::bigint)::integer as score,
  p.selected_avatar_frame_key
from public.profiles p
join public.gift_transactions gt on gt.receiver_id = p.id
group by p.id, p.display_name, p.avatar_url, p.vip_level, p.selected_avatar_frame_key
order by coalesce(sum(gt.quantity), 0::bigint)::integer desc
limit 50;

create or replace view public.v_leaderboard_gifters as
select
  p.id,
  p.display_name,
  p.avatar_url,
  coalesce(p.vip_level, 0) as vip_level,
  coalesce(sum(gt.quantity), 0::bigint)::integer as score,
  p.selected_avatar_frame_key
from public.profiles p
join public.gift_transactions gt on gt.sender_id = p.id
group by p.id, p.display_name, p.avatar_url, p.vip_level, p.selected_avatar_frame_key
order by coalesce(sum(gt.quantity), 0::bigint)::integer desc
limit 50;

create or replace view public.v_leaderboard_followed as
select
  p.id,
  p.display_name,
  p.avatar_url,
  coalesce(p.vip_level, 0) as vip_level,
  count(uf.follower_id)::integer as score,
  p.selected_avatar_frame_key
from public.profiles p
join public.user_follows uf on uf.following_id = p.id
group by p.id, p.display_name, p.avatar_url, p.vip_level, p.selected_avatar_frame_key
order by count(uf.follower_id)::integer desc
limit 50;
