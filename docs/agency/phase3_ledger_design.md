# Phase 3 Append-only Ledger Design

The isolated `agency_finance_v3` schema defines:

- `agency_financial_operations`: one lifecycle and correlation record.
- `agency_ledger_accounts`: Agency, agent, host, wallet, platform, commission,
  settlement and clearing accounts by currency.
- `agency_ledger_entries`: immutable debit/credit postings linked to operation,
  request and transaction.
- `agency_idempotency_keys`: atomic request claim and stored result.
- `agency_audit_events`: immutable server audit events.

Each operation must balance debit and credit by currency. Coin, diamond, credit,
commission and fiat dimensions remain explicit. Unique operation/account/side
and operation-scope/idempotency constraints prevent duplicate posting. UPDATE
and DELETE of ledger/audit rows are denied by grants and triggers. Reversals use
new compensating operations. The schema is private and grants no access to
PUBLIC, anon, or authenticated.
