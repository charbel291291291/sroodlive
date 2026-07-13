# Phase 3 Idempotency Contract

Scope is the operation type plus a caller-provided opaque key. The server first
inserts `(operation_scope,idempotency_key,actor_user_id,request_hash)` under a
unique constraint in the same transaction. A conflict locks and reads the claim:
same actor and hash returns the stored result; any mismatch fails.

The claim covers recharge submission/decision/posting, wallet credit/debit,
Agency credit adjustment, withdrawals, commission, settlement, reversal and
administrative correction. Financial completion stores the operation/result
before commit. Retrying never repeats wallet mutation, ledger posting, commission
or settlement. Completed keys never expire. Failed/uncommitted claims roll back;
operational cleanup may remove only abandoned pre-effect claims under a separately
approved policy.
