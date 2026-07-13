-- ============================================================
-- Local-dev bootstrap for a view created directly in prod
-- outside of migration history (schema drift). Definition
-- pulled from prod via pg_get_viewdef.
-- ============================================================

create or replace view public.v_leaderboard_earners as
select
  p.id,
  p.display_name,
  p.avatar_url,
  coalesce(p.vip_level, 0) as vip_level,
  coalesce(sum(gt.quantity), 0::bigint)::integer as score
from public.profiles p
join public.gift_transactions gt on gt.receiver_id = p.id
group by p.id, p.display_name, p.avatar_url, p.vip_level
order by coalesce(sum(gt.quantity), 0::bigint)::integer desc
limit 50;

create or replace view public.v_leaderboard_gifters as
select
  p.id,
  p.display_name,
  p.avatar_url,
  coalesce(p.vip_level, 0) as vip_level,
  coalesce(sum(gt.quantity), 0::bigint)::integer as score
from public.profiles p
join public.gift_transactions gt on gt.sender_id = p.id
group by p.id, p.display_name, p.avatar_url, p.vip_level
order by coalesce(sum(gt.quantity), 0::bigint)::integer desc
limit 50;

create or replace view public.v_leaderboard_followed as
select
  p.id,
  p.display_name,
  p.avatar_url,
  coalesce(p.vip_level, 0) as vip_level,
  count(uf.follower_id)::integer as score
from public.profiles p
join public.user_follows uf on uf.following_id = p.id
group by p.id, p.display_name, p.avatar_url, p.vip_level
order by count(uf.follower_id)::integer desc
limit 50;
