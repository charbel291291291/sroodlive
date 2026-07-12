-- Compatibility layer for old admin RPCs.
-- New role system uses: o_super_admin, p_super_admin, super_admin, admin.
-- Old RPCs still call: has_app_role('super_admin'), has_admin_access(), etc.

create or replace function public.has_app_role(p_role text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
      and au.is_active = true
      and (
        -- Owner roles pass everything.
        au.role = 'o_super_admin'

        -- Platform super admin passes old super_admin checks.
        or (
          au.role = 'p_super_admin'
          and lower(coalesce(p_role, '')) in (
            'super_admin',
            'admin',
            'support_admin',
            'content_admin',
            'finance_admin',
            'bd_admin',
            'room_admin',
            'moderator'
          )
        )

        -- Normal super admin passes old super_admin and lower admin checks.
        or (
          au.role = 'super_admin'
          and lower(coalesce(p_role, '')) in (
            'super_admin',
            'admin',
            'support_admin',
            'content_admin',
            'finance_admin',
            'bd_admin',
            'room_admin',
            'moderator'
          )
        )

        -- Admin passes admin-level operational checks.
        or (
          au.role = 'admin'
          and lower(coalesce(p_role, '')) in (
            'admin',
            'support_admin',
            'content_admin',
            'room_admin',
            'moderator'
          )
        )

        -- Exact match fallback for older custom roles still stored in admin_users.
        or au.role = lower(coalesce(p_role, ''))
      )
  );
$$;

create or replace function public.has_admin_access()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_app_role('admin')
     or public.has_app_role('super_admin');
$$;

create or replace function public.has_content_admin_access()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_app_role('content_admin')
     or public.has_app_role('super_admin');
$$;

create or replace function public.has_finance_access()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_app_role('finance_admin')
     or public.has_app_role('super_admin');
$$;

create or replace function public.has_bd_access()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_app_role('bd_admin')
     or public.has_app_role('super_admin');
$$;

create or replace function public.has_room_admin_access()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_app_role('room_admin')
     or public.has_app_role('moderator')
     or public.has_app_role('super_admin');
$$;

create or replace function public.profile_hub_admin_access()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_admin_access();
$$;

grant execute on function public.has_app_role(text) to authenticated;
grant execute on function public.has_admin_access() to authenticated;
grant execute on function public.has_content_admin_access() to authenticated;
grant execute on function public.has_finance_access() to authenticated;
grant execute on function public.has_bd_access() to authenticated;
grant execute on function public.has_room_admin_access() to authenticated;
grant execute on function public.profile_hub_admin_access() to authenticated;
