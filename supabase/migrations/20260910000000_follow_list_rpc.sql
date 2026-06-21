-- =============================================================================
-- Follow relationship lists (additive)
--
-- Bug: profile Following/Followers/Friends counts showed values but the opened
-- lists were empty. Two causes:
--   1. The client list query embedded profiles via FK names
--      (profiles!user_follows_follower_id_fkey). Those FKs reference auth.users,
--      NOT public.profiles, so PostgREST could not embed profiles → query failed
--      → empty list. (Counts read user_follows only, so they worked.)
--   2. profiles RLS only allows reading own / room-co-member / DM-participant
--      rows — followed users' profiles were blocked anyway.
--
-- Fix: a SECURITY DEFINER RPC that resolves the relationship and returns ONLY
-- public profile fields. Counts and lists now both derive from user_follows.
-- No profiles RLS is broadened; no private data is exposed. Blocked users
-- (either direction) are excluded. Missing profiles are excluded (inner join).
--
-- Additive, idempotent. No destructive changes.
-- =============================================================================

create or replace function public.get_follow_list(
  p_user_id uuid,
  p_kind    text   -- 'followers' | 'following' | 'friends'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_viewer uuid := auth.uid();
  v_result jsonb;
begin
  if v_viewer is null then raise exception 'not_authenticated'; end if;
  if p_kind not in ('followers', 'following', 'friends') then
    raise exception 'invalid_kind';
  end if;

  with target_ids as (
    -- followers  -> people who follow p_user (follower_id)
    -- following/friends -> people p_user follows (following_id)
    select case when p_kind = 'followers' then uf.follower_id
                else uf.following_id end as uid
    from public.user_follows uf
    where (p_kind = 'followers' and uf.following_id = p_user_id)
       or (p_kind in ('following', 'friends') and uf.follower_id = p_user_id)
  ),
  filtered as (
    select distinct t.uid
    from target_ids t
    where p_kind <> 'friends'
       -- friends: keep only mutual (they follow p_user back)
       or exists (
            select 1 from public.user_follows b
            where b.follower_id = t.uid and b.following_id = p_user_id
          )
  )
  select coalesce(jsonb_agg(row_to_json(x) order by x.display_name), '[]'::jsonb)
  into v_result
  from (
    select
      p.id,
      p.display_name,
      p.avatar_url,
      p.public_user_id,
      p.gender,
      p.vip_level,
      p.vip_expires_at,
      exists (
        select 1 from public.user_follows vf
        where vf.follower_id = v_viewer and vf.following_id = p.id
      ) as viewer_follows
    from filtered f
    join public.profiles p on p.id = f.uid          -- excludes missing profiles
    where p.id <> v_viewer
      and not exists (                              -- exclude blocked (either way)
        select 1 from public.user_blocks ub
        where (ub.blocker_id = v_viewer and ub.blocked_id = p.id)
           or (ub.blocker_id = p.id      and ub.blocked_id = v_viewer)
      )
  ) x;

  return v_result;
end;
$$;

revoke all on function public.get_follow_list(uuid, text) from public;
grant execute on function public.get_follow_list(uuid, text) to authenticated;

-- =============================================================================
-- End of 20260910000000_follow_list_rpc.sql
-- =============================================================================
