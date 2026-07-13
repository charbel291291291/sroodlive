-- Phase 3: narrow the live RPC surface without changing function bodies or
-- current business behavior. Forward-only; no table/data migration.

alter function public.admin_approve_withdrawal(uuid, text)
  set search_path = pg_catalog, public;
alter function public.admin_reject_withdrawal(uuid, text)
  set search_path = pg_catalog, public;
alter function public.approve_recharge_transaction(uuid, text, text)
  set search_path = pg_catalog, public;
alter function public.create_recharge_transaction(uuid, text, text)
  set search_path = pg_catalog, public;
alter function public.apply_vip_recharge_exp(uuid, bigint)
  set search_path = pg_catalog, public;
alter function public.preview_withdrawal_split(integer)
  set search_path = pg_catalog, public;
alter function public.request_withdrawal(integer, text, text, text)
  set search_path = pg_catalog, public;

revoke execute on function public.admin_approve_withdrawal(uuid, text) from public, anon;
revoke execute on function public.admin_reject_withdrawal(uuid, text) from public, anon;
revoke execute on function public.approve_recharge_transaction(uuid, text, text) from public, anon;
revoke execute on function public.create_recharge_transaction(uuid, text, text) from public, anon;
revoke execute on function public.apply_vip_recharge_exp(uuid, bigint) from public, anon, authenticated;
revoke execute on function public.preview_withdrawal_split(integer) from public, anon;
revoke execute on function public.request_withdrawal(integer, text, text, text) from public, anon;

grant execute on function public.admin_approve_withdrawal(uuid, text) to authenticated;
grant execute on function public.admin_reject_withdrawal(uuid, text) to authenticated;
grant execute on function public.approve_recharge_transaction(uuid, text, text) to authenticated;
grant execute on function public.create_recharge_transaction(uuid, text, text) to authenticated;
grant execute on function public.preview_withdrawal_split(integer) to authenticated;
grant execute on function public.request_withdrawal(integer, text, text, text) to authenticated;

-- VIP EXP is an internal side effect of privileged recharge approval only.
grant execute on function public.apply_vip_recharge_exp(uuid, bigint) to service_role;

-- Current live financial tables remain readable under their existing RLS
-- policies, but client-side mutation is RPC-only.
revoke insert, update, delete on table public.recharge_transactions from anon, authenticated;
revoke insert, update, delete on table public.withdrawal_requests from anon, authenticated;
revoke insert, update, delete on table public.user_wallets from anon, authenticated;
revoke insert, update, delete on table public.wallets from anon, authenticated;
revoke insert, update, delete on table public.coin_transactions from anon, authenticated;
revoke insert, update, delete on table public.wallet_transactions from anon, authenticated;
