# Agency Migration Readiness

## Decision: NO-GO

The project is not ready for schema creation or cutover.

## Verified evidence

- Exact counts and current financial totals are documented.
- No current duplicate references, orphan links, missing users, negative values,
  or null required financial values were found.
- All inventoried tables have RLS enabled; anon has no direct table access.
- Local and remote migration history confirms both June and November Agency
  generations are deployed history.

## Critical blockers

1. Financial/admin `SECURITY DEFINER` RPCs are executable by PUBLIC and anon.
2. Definer functions use `search_path=public`, not an empty fixed path.
3. Recharge requests and transactions are separate, unreconciled authorities.
4. No unified idempotency key or immutable financial ledger is proven.
5. Independent owner/manager/recruiter/hostess/recharge/admin role assignments
   do not exist in one authoritative model.
6. Cross-agency authorization and admin predicates require function-body tests.
7. A complete wallet-ledger effect reconciliation has not yet been produced.
8. Unified schema migrations, backfill, rollback drill, and staging validation
   do not yet exist.

## Required changes before conditional go

- Harden legacy financial RPC execution immediately in a separate corrective
  migration after caller analysis and attacker tests.
- Define and test unified schema/RLS/RPC contracts.
- Backfill in staging and reconcile exact totals.
- Build permission-scoped Admin and user modules.
- Prove realtime ownership and reconnection behavior.
- Switch reads/writes behind controlled feature flags.

## Rollback approach

Legacy remains intact and writable until each unified write cutover is proven.
Rollback disables the new feature flag and routes callers to the unchanged
legacy source. Financial operations require idempotency keys shared across retry
and rollback boundaries.
