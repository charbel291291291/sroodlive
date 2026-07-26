-- =============================================================================
-- get_follow_list: include selected_avatar_frame_key (additive, CREATE OR REPLACE)
--
-- Frame System V2 migration needs the equipped frame code for each row so the
-- followers/following list can render it through SroodAvatarFrame instead of
-- a plain CircleAvatar. Adding a field to the returned jsonb objects is
-- backwards compatible: existing clients that don't read the new key are
-- unaffected. vip_expires_at was already returned but unused client-side;
-- still included here for effective-VIP computation.
-- =============================================================================

create or replace function public.get_follow_list(
  p_user_id uuid,
  p_kind    text
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
      p.selected_avatar_frame_key,
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
    where not exists (                              -- exclude blocked (either way)
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
-- End of 20261115000000_follow_list_include_frame_key.sql
-- =============================================================================
