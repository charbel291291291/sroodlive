-- Security fix: replace direct payout_requests INSERT with server-validated RPC
--
-- PROBLEM: income_service.dart did a raw INSERT into payout_requests with a
-- client-supplied amount_usd. The only RLS check was user_id = auth.uid(),
-- meaning any authenticated user could request an arbitrary payout amount via
-- a direct API call, bypassing the UI's client-side amount <= availableBalance
-- guard.
--
-- FIX:
--   1. Create request_payout() RPC (SECURITY DEFINER) that re-reads
--      income_accounts.available_balance_usd server-side and rejects the
--      request if amount > available balance or below the $1 minimum.
--   2. Revoke direct INSERT on payout_requests from authenticated so the table
--      can only be written through this RPC.
--
-- The Flutter client is updated separately to call rpc('request_payout').

-- ── 1. Create the safe RPC ─────────────────────────────────────────────────

create or replace function public.request_payout(
  p_amount_usd      numeric,
  p_method          text,
  p_account_details text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid    := auth.uid();
  v_available  numeric;
  v_request_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if p_amount_usd is null or p_amount_usd < 1.0 then
    raise exception 'amount_below_minimum';
  end if;

  if coalesce(trim(p_method), '') = '' then
    raise exception 'missing_method';
  end if;

  -- Re-read server-side balance with a row lock to prevent race conditions.
  select available_balance_usd
  into   v_available
  from   public.income_accounts
  where  user_id = v_uid
  for update;

  if not found then
    raise exception 'no_income_account';
  end if;

  if p_amount_usd > v_available then
    raise exception 'amount_exceeds_available_balance';
  end if;

  insert into public.payout_requests
    (user_id, amount_usd, method, account_details, status)
  values
    (v_uid, p_amount_usd, p_method, p_account_details, 'pending')
  returning id into v_request_id;

  return v_request_id;
end;
$$;

grant execute on function public.request_payout(numeric, text, text) to authenticated;

-- ── 2. Remove direct INSERT access ────────────────────────────────────────
-- All inserts must now go through the RPC above.

revoke insert on public.payout_requests from authenticated;
