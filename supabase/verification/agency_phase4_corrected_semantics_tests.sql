-- Agency Finance V3 — corrected-semantics staging tests (NOT run: no local DB).
-- Run on staging inside a transaction with an impersonated authenticated user
-- (auth.uid() must be non-null; the bare service key will fail 'not_authenticated').
-- Each block states its expected outcome. Wrap everything in BEGIN ... ROLLBACK.
--
-- Prereqs: two authenticated test users
--   :creator_jwt  — ordinary user (request creator)
--   :admin_jwt    — user for whom public.has_finance_access() = true and who
--                   is NOT the creator/agent of the test requests.

begin;

-- T1. create_recharge_request → operation status must be 'pending', and NO
-- ledger entries may exist for it.
--   as :creator_jwt
select agency_finance_v3.create_recharge_request(
  't1-key', jsonb_build_object('coin_amount', 1000, 'exchange_rate', 1));
-- EXPECT: {"status":"pending", ...}
-- EXPECT 0 rows:
--   select * from agency_finance_v3.agency_ledger_entries e
--   join agency_finance_v3.agency_financial_operations o using (operation_id)
--   where o.idempotency_key = 't1-key';

-- T2. Idempotent retry with the SAME key + payload returns the cached result
-- (same operation_id); a DIFFERENT payload under the same key must raise
-- 'idempotency_conflict'.

-- T3. approve_recharge_request (as :admin_jwt) on the T1 request:
--   EXPECT success; source request status -> 'completed';
--   EXPECT 0 ledger entries for the approval (movement happens at posting).
-- Re-approving with a NEW key must raise 'request_not_pending'
-- (duplicate-approval prevention).

-- T4. Self-approval: approving with :creator_jwt (even if finance admin)
-- must raise 'self_approval_forbidden'.

-- T5. post_recharge_transaction (as :admin_jwt) on the approved request:
--   EXPECT success; EXPECT exactly 2 entries: debit V3_CLEARING,
--   credit V3_WALLET(beneficiary), equal amount, currency 'COIN',
--   coin_amount = 1000 on both.
-- Posting again with a NEW key must raise 'request_already_posted'.
-- Posting a request that was never approved must raise 'request_not_approved'.

-- T6. reject_recharge_request on a PENDING request:
--   EXPECT source status -> 'rejected'; EXPECT 0 ledger entries for the
--   rejection. Approving the rejected request must raise 'request_not_pending'.

-- T7. create_withdrawal_request + approve_withdrawal_request:
--   EXPECT withdrawal approval posts debit V3_WALLET / credit V3_CLEARING
--   (money LEAVES the wallet). Self-approval by the creator must raise.

-- T8. reverse_financial_operation on the T5 posting (as :admin_jwt):
--   EXPECT entries with the SOURCE amounts (1000 COIN), direction swapped
--   (debit V3_WALLET, credit V3_CLEARING); source posting status -> 'reversed'
--   with reversed_at set. A second reversal must raise
--   'reversal_source_not_completed'. Reversing a request/approval (non-movement
--   op) must raise 'source_operation_not_reversible'.

-- T9. Currency derivation: create_recharge_request with fiat_amount>0 and no
-- currency must raise 'fiat_currency_required'; coin-only payload records
-- currency 'COIN'; diamond-only records 'DIAMOND'.

-- T10. Immutability: as service_role,
--   update agency_finance_v3.agency_financial_operations
--     set coin_amount = coin_amount + 1 where idempotency_key = 't1-key';
--   EXPECT 'operation_financial_fields_immutable'.
--   update ... set status='pending' where status='completed' ...
--   EXPECT 'invalid_operation_status_transition'.
--   delete from agency_finance_v3.agency_ledger_entries ...
--   EXPECT 'append_only_record'.

-- T11. Isolation: as a plain authenticated user with NO explicit staging grant,
-- calling any agency_finance_v3.* function must fail with permission denied
-- (no authenticated grants exist).

-- T12. Ledger invariant (after T1–T9):
--   select operation_id, currency,
--          sum(case entry_side when 'debit' then amount else -amount end) as net
--   from agency_finance_v3.agency_ledger_entries group by 1,2;
--   EXPECT net = 0 for every row.

rollback;
