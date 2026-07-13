# Agency Migration Safety Plan

## Stage A - Add isolated schema

Create forward-only normalized objects with explicit grants, RLS, constraints,
restricted RPC execution and feature flags. No legacy mutation.

## Stage B - Idempotent backfill

Copy legacy rows with deterministic source keys. Quarantine malformed/conflicting
records. No wallet or settlement recalculation.

## Stage C - Reconcile

Compare exact counts, statuses, financial totals, user/agency links and ledger
effects. Block on any unexplained difference.

## Stage D - Read adapters

Use security-invoker compatibility views or RPC adapters only where required.
Adapters are versioned and have an explicit removal migration.

## Stage E - Switch reads

Release Admin and user reads to the unified source behind server-controlled
feature flags. Monitor authorization and latency.

## Stage F - Switch writes atomically

Deploy one server write path at a time. Never dual-write financial operations
without a proven transactional outbox/idempotency design.

## Stage G - Legacy read-only

Revoke legacy client mutation and retain verified read access. Confirm no active
Flutter, Admin, job, trigger, or RPC caller writes legacy objects.

## Stage H - Monitor

Monitor ledger reconciliation, permission denials, duplicate keys, realtime
reconnects and settlement/recharge/withdrawal error rates.

## Stage I - Archive

Archive legacy objects and documentation after an agreed retention window.

## Stage J - Delete only with explicit approval

Use a separate destructive migration after final exact reconciliation, backup
verification, rollback drill, caller search, and stakeholder approval.

No migration repair, reset, squash, old migration edit, rename, TRUNCATE, or
DROP is permitted in this plan.
