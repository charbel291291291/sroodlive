-- Safe read-only invariants for an applied Phase 3 staging schema.
select operation_id, currency,
  sum(case when entry_side='debit' then amount else 0 end) debits,
  sum(case when entry_side='credit' then amount else 0 end) credits
from agency_finance_v3.agency_ledger_entries
group by operation_id, currency
having sum(case when entry_side='debit' then amount else 0 end)
    <> sum(case when entry_side='credit' then amount else 0 end);

select o.operation_id from agency_finance_v3.agency_financial_operations o
left join agency_finance_v3.agency_ledger_entries e on e.operation_id=o.operation_id
where o.status='completed' group by o.operation_id having count(e.entry_id)=0;

select e.entry_id from agency_finance_v3.agency_ledger_entries e
left join agency_finance_v3.agency_financial_operations o on o.operation_id=e.operation_id
where o.operation_id is null;

select operation_type, idempotency_key, count(*)
from agency_finance_v3.agency_financial_operations
group by operation_type,idempotency_key having count(*) > 1;

select operation_scope,idempotency_key,count(distinct operation_id)
from agency_finance_v3.agency_idempotency_keys
group by operation_scope,idempotency_key having count(distinct operation_id) > 1;

select operation_id from agency_finance_v3.agency_financial_operations
where operation_type='reversal' and reversal_of is null;

select p.oid::regprocedure::text from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='agency_finance_v3' or p.proname in (
  'admin_approve_withdrawal','admin_reject_withdrawal',
  'approve_recharge_transaction','create_recharge_transaction',
  'apply_vip_recharge_exp','preview_withdrawal_split','request_withdrawal'))
and (has_function_privilege('public',p.oid,'execute')
  or has_function_privilege('anon',p.oid,'execute'));
