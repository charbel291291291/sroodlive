drop function if exists public.admin_list_reports(integer, text, text);
drop function if exists public.admin_list_reports(text, text, integer);

create or replace function public.admin_list_reports(
  p_limit integer default 100,
  p_status text default null,
  p_target_type text default null
)
returns table (
  id uuid,
  reporter_id uuid,
  reporter_public_user_id text,
  reporter_name text,
  target_type text,
  target_id text,
  reason text,
  details text,
  status text,
  resolved_by uuid,
  resolved_by_name text,
  resolved_at timestamptz,
  resolution_note text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    r.id,
    r.reporter_id,
    null::text as reporter_public_user_id,
    null::text as reporter_name,
    case
      when r.reported_user_id is not null then 'user'
      when r.room_id is not null then 'room'
      else 'other'
    end::text as target_type,
    coalesce(r.reported_user_id::text, r.room_id::text, '')::text as target_id,
    coalesce(r.reason, '')::text as reason,
    null::text as details,
    coalesce(r.status, 'pending')::text as status,
    null::uuid as resolved_by,
    null::text as resolved_by_name,
    null::timestamptz as resolved_at,
    null::text as resolution_note,
    r.created_at
  from public.user_reports r
  where public.is_admin_staff(auth.uid())
    and (p_status is null or r.status = p_status)
    and (
      p_target_type is null
      or (p_target_type = 'user' and r.reported_user_id is not null)
      or (p_target_type = 'room' and r.room_id is not null)
      or (
        p_target_type = 'other'
        and r.reported_user_id is null
        and r.room_id is null
      )
    )
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$$;

grant execute on function public.admin_list_reports(integer, text, text) to authenticated;
