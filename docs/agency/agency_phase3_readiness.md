# Agency Phase 3 Readiness

## Decision: NO-GO

Prepared: seven-RPC inventory; forward-only grant/search-path hardening; private
ledger/idempotency schema; append-only protections; verification suites; staging
and rollback plan.

Not yet resolved: migrations are not locally applied because no local Supabase
database is confirmed; hardening is not deployed; transactional prototypes fail
closed and do not yet post wallets/credits; authorization adapters and concurrency
tests are incomplete; ledger invariants have not run on staging; production
rollback has not been drilled.

## Validation results

- Relevant Flutter tests: 5 passed, 0 failed.
- `flutter analyze`: passed with no issues.
- Live privilege verification: passed and confirmed seven still-exposed RPCs.
- `supabase db lint --linked`: failed on pre-existing public-schema errors,
  including the live VIP helper referencing a missing subscription column.
- Local migration apply, security role fixtures and financial invariants: not run
  because the local Supabase database is not running.
- Staging status: not started.

Functions proposed hardened: all seven. Functions currently still exposed in
production: all seven until the migration is reviewed and deliberately deployed.
No Agency data was migrated and no Flutter read/write path was switched.
