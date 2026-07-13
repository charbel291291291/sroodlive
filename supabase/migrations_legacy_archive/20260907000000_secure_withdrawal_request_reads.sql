-- =============================================================================
-- Secure withdrawal request admin reads (2026-09-07)
--
-- The admin panel previously read withdrawal_requests via a direct client-side
-- `.from('withdrawal_requests').select(...)`, relying solely on RLS. Every other
-- admin operation goes through a SECURITY DEFINER RPC that verifies permission
-- server-side. This migration closes that inconsistency by adding a read RPC.
--
-- Permission: public.has_finance_access()  - the SAME gate already enforced by
--   admin_approve_withdrawal() / admin_reject_withdrawal(). It returns true for
--   finance_admin or super_admin, so anyone who can action a withdrawal can also
--   view the queue. No new/weaker permission is introduced.
--
-- Behaviour matches the admin UI needs:
--   - filter:   status = p_status   (default 'pending')
--   - order:    created_at DESC      \(newest withdrawal requests first\)
--   - limit:    p_limit              (default 50)
--   - columns:  exactly the fields the AdminWithdrawalRequest model reads,
--               with profiles flattened to public_user_id / display_name.
-- No extra columns are exposed.
--
-- Idempotent: CREATE OR REPLACE + guarded GRANT/REVOKE.
-- =============================================================================

create or replace function public.admin_fetch_withdrawal_requests(
  p_status text default 'pending',
  p_limit  integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  -- Server-side authorization - identical gate to the approve/reject RPCs.
  if auth.uid() is null or not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  select coalesce(jsonb_agg(row_to_json(t) order by t.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      w.id,
      w.user_id,
      p.public_user_id,
      p.display_name,
      w.diamonds,
      w.gross_usd,
      w.host_share_usd,
      w.agency_share_usd,
      w.platform_share_usd,
      w.method,
      w.account_details,
      w.notes,
      w.status,
      w.created_at
    from public.withdrawal_requests w
    left join public.profiles p on p.id = w.user_id
    where w.status = p_status
    order by w.created_at desc
    limit greatest(p_limit, 0)
  ) t;

  return v_result;
end;
$$;

-- Follow the existing admin RPC grant pattern: authenticated only, no public.
revoke all on function public.admin_fetch_withdrawal_requests(text, integer) from public;
grant execute on function public.admin_fetch_withdrawal_requests(text, integer) to authenticated;


-- -- Withdrawal history (approved / rejected) ---------------------------------
-- Mirrors admin_service.fetchWithdrawalHistory, which also read the table
-- directly. Same finance gate, same columns, same order (created_at DESC).

create or replace function public.admin_fetch_withdrawal_history(
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.has_finance_access() then
    raise exception 'not_authorized';
  end if;

  select coalesce(jsonb_agg(row_to_json(t) order by t.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      w.id,
      w.user_id,
      p.public_user_id,
      p.display_name,
      w.diamonds,
      w.gross_usd,
      w.host_share_usd,
      w.agency_share_usd,
      w.platform_share_usd,
      w.method,
      w.account_details,
      w.notes,
      w.status,
      w.created_at
    from public.withdrawal_requests w
    left join public.profiles p on p.id = w.user_id
    where w.status in ('approved', 'rejected')
    order by w.created_at desc
    limit greatest(p_limit, 0)
  ) t;

  return v_result;
end;
$$;

revoke all on function public.admin_fetch_withdrawal_history(integer) from public;
grant execute on function public.admin_fetch_withdrawal_history(integer) to authenticated;

-- =============================================================================
-- End of 20260907000000_secure_withdrawal_request_reads.sql
-- =============================================================================


