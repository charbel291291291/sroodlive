# Phase 4 Staging Deployment Plan

Order: full existing history, `20260711175345` RPC hardening,
`20260711175349` private foundation, `20260711181410` VIP correction, then
`20260711181414` V3 implementation. Expected objects are the private ledger,
idempotency/audit tables and isolated RPCs; expected live changes are only the
seven grant/search-path changes and corrected VIP helper.

Use an isolated Supabase staging project with its own secrets and synthetic users.
Load fixtures only after setting `app.agency_phase4_fixtures=enabled`. Run security
inventory, role matrix, idempotency, concurrency, failure injection and financial
invariants in that order, followed by wallet/Agency smoke tests and monitoring for
denials, conflicts and unbalanced operations.

Rollback is forward-only: revoke V3 execution, disable any staging feature flag,
restore the prior legitimate RPC grant set, preserve ledger evidence and deploy a
corrective function version. Never repair history or delete posted records.
