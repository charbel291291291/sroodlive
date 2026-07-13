-- =============================================================================
-- Forward-only baseline addition: manually-created leaderboard views.
--
-- Production has 3 views (v_leaderboard_earners / _followed / _gifters) that no
-- migration creates — they were built manually, like the foundational tables.
-- 20260611033503_fix_leaderboard_view_permissions.sql GRANTs on them, so a
-- from-zero reset fails there. Reconstructed verbatim from READ-ONLY production
-- (pg_get_viewdef) and placed just before that grant. Their base tables
-- (profiles, gift_transactions from the foundation baseline; user_follows from
-- an earlier migration) all exist by this point. No production change.
-- =============================================================================

create or replace view public.v_leaderboard_earners as
  select p.id, p.display_name, p.avatar_url,
         coalesce(p.vip_level, 0) as vip_level,
         coalesce(sum(gt.quantity), 0::bigint)::integer as score
  from profiles p
  join gift_transactions gt on gt.receiver_id = p.id
  group by p.id, p.display_name, p.avatar_url, p.vip_level
  order by (coalesce(sum(gt.quantity), 0::bigint)::integer) desc
  limit 50;

create or replace view public.v_leaderboard_gifters as
  select p.id, p.display_name, p.avatar_url,
         coalesce(p.vip_level, 0) as vip_level,
         coalesce(sum(gt.quantity), 0::bigint)::integer as score
  from profiles p
  join gift_transactions gt on gt.sender_id = p.id
  group by p.id, p.display_name, p.avatar_url, p.vip_level
  order by (coalesce(sum(gt.quantity), 0::bigint)::integer) desc
  limit 50;

create or replace view public.v_leaderboard_followed as
  select p.id, p.display_name, p.avatar_url,
         coalesce(p.vip_level, 0) as vip_level,
         count(uf.follower_id)::integer as score
  from profiles p
  join user_follows uf on uf.following_id = p.id
  group by p.id, p.display_name, p.avatar_url, p.vip_level
  order by (count(uf.follower_id)::integer) desc
  limit 50;
