-- Admin payout-request review RPCs
--
-- payout_requests are host-income withdrawal requests submitted via the
-- request_payout() RPC (migration 20260918000000_request_payout_rpc.sql).
-- This migration adds three admin RPCs for reviewing them:
--
--   admin_list_payout_requests  — paginated list with user display info
--   admin_approve_payout_request — approve + deduct available_balance_usd
--   admin_reject_payout_request  — reject without touching balance
--
-- All three require has_finance_access(). All mutating RPCs lock rows
-- FOR UPDATE to prevent concurrent double-processing.
--
-- RLS addition: admins can SELECT payout_requests via has_finance_access().
-- The authenticated INSERT grant was already revoked by migration 20260918.

-- ── RLS: admin read access ──────────────────────────────────────────────────

drop policy if exists "Admins can view all payout requests" on public.payout_requests;
create policy "Admins can view all payout requests"
  on public.payout_requests for select to authenticated
  using (user_id = auth.uid() or public.has_finance_access());

-- ── admin_list_payout_requests ──────────────────────────────────────────────

drop function if exists public.admin_list_payout_requests(text, integer);

create or replace function public.admin_list_payout_requests(
  p_status text    default 'pending',
  p_limit  integer default 50
)
returns table (
  id              uuid,
  user_id         uuid,
  public_user_id  text,
  display_name    text,
  amount_usd      numeric,
  method          text,
  account_details text,
  status          text,
  admin_note      text,
  requested_at    timestamptz,
  reviewed_at     timestamptz,
  reviewed_by     uuid
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_finance_access() then
    raise exception 'finance_access_required';
  end if;

  return query
    select
      pr.id,
      pr.user_id,
      p.public_user_id,
      coalesce(p.display_name, p.username) as display_name,
      pr.amount_usd,
      pr.method,
      pr.account_details,
      pr.status,
      pr.admin_note,
      pr.requested_at,
      pr.reviewed_at,
      pr.reviewed_by
    from   public.payout_requests pr
    left join public.profiles p on p.id = pr.user_id
    where  (p_status is null or pr.status = p_status)
    order  by pr.requested_at desc
    limit  p_limit;
end;
$$;

revoke all on function public.admin_list_payout_requests(text, integer) from public;
grant execute on function public.admin_list_payout_requests(text, integer) to authenticated;

-- ── admin_approve_payout_request ────────────────────────────────────────────

create or replace function public.admin_approve_payout_request(
  p_request_id uuid,
  p_note       text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id  uuid := auth.uid();
  v_request   record;
  v_balance   numeric(12,2);
begin
  if v_admin_id is null or not public.has_finance_access() then
    raise exception 'finance_access_required';
  end if;

  -- Lock the payout request row to prevent concurrent processing.
  select id, user_id, amount_usd, status
  into   v_request
  from   public.payout_requests
  where  id = p_request_id
  for update;

  if not found then
    raise exception 'payout_request_not_found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'payout_request_not_pending: current status is %', v_request.status;
  end if;

  -- Lock income_accounts and re-check balance server-side.
  select available_balance_usd
  into   v_balance
  from   public.income_accounts
  where  user_id = v_request.user_id
  for update;

  if not found then
    raise exception 'income_account_not_found';
  end if;

  if v_request.amount_usd > v_balance then
    raise exception 'insufficient_balance: requested % but available %',
      v_request.amount_usd, v_balance;
  end if;

  -- Deduct the approved amount from available balance.
  update public.income_accounts
  set    available_balance_usd = available_balance_usd - v_request.amount_usd,
         updated_at             = now()
  where  user_id = v_request.user_id;

  -- Mark payout request approved.
  update public.payout_requests
  set    status      = 'approved',
         admin_note  = coalesce(p_note, admin_note),
         reviewed_at = now(),
         reviewed_by = v_admin_id
  where  id = p_request_id;
end;
$$;

revoke all on function public.admin_approve_payout_request(uuid, text) from public;
grant execute on function public.admin_approve_payout_request(uuid, text) to authenticated;

-- ── admin_reject_payout_request ─────────────────────────────────────────────

create or replace function public.admin_reject_payout_request(
  p_request_id uuid,
  p_reason     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_request  record;
begin
  if v_admin_id is null or not public.has_finance_access() then
    raise exception 'finance_access_required';
  end if;

  select id, status
  into   v_request
  from   public.payout_requests
  where  id = p_request_id
  for update;

  if not found then
    raise exception 'payout_request_not_found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'payout_request_not_pending: current status is %', v_request.status;
  end if;

  update public.payout_requests
  set    status      = 'rejected',
         admin_note  = coalesce(p_reason, admin_note),
         reviewed_at = now(),
         reviewed_by = v_admin_id
  where  id = p_request_id;
end;
$$;

revoke all on function public.admin_reject_payout_request(uuid, text) from public;
grant execute on function public.admin_reject_payout_request(uuid, text) to authenticated;
