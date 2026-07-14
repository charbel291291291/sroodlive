# Crash Rocket V3 Implementation Plan

## Audited contracts

- Gameplay wallet authority: `public.wallets.coins_balance` (`integer`) with
  immutable evidence in `public.wallet_transactions`.
- Wallet mutation pattern: row lock/conditional update, business row mutation,
  and wallet transaction insert inside one PostgreSQL RPC transaction.
- Owner authorization: existing `public.owner_control_users` and
  `public.is_owner_control_user()`; no parallel roles.
- Client architecture: direct feature services over `SupabaseService`, local
  stateful controllers/widgets, Supabase Realtime, and `just_audio`.
- Retired Crash Rocket: migration `20261110000000_remove_crash_rocket_backend.sql`
  removed every prior generation. V3 uses only `crash_v3_*` names and never reads
  the immutable legacy archive.

## Product decisions

- Two independent bet slots per user and round.
- `public.wallets` is canonical; V3 never mutates `public.user_wallets`.
- Every debit/credit/refund writes exactly one `wallet_transactions` row with a
  V3 type and deterministic idempotency metadata.
- The game starts disabled. It remains disabled when no healthy engine lease
  exists.
- Admins can change future settings and stop/refund safely, but cannot choose a
  seed, crash multiplier, winner, or unrevealed result.
- The engine uses a server-only secret/encryption key and service role. Flutter
  receives only the commitment before settlement and the revealed seed after it.

## Delivery sequence

1. Replay the current migration history locally and classify baseline failures.
2. Add isolated schema, constraints, indexes, RLS, grants, fairness helpers,
   wallet-safe player RPCs, engine RPCs, history/state RPCs, and owner RPCs.
3. Add a service-role Edge Function engine using a database advisory lock and
   renewable lease; recover or refund abandoned rounds idempotently.
4. Add the Flutter V3 module: models, service, clock, realtime, audio, controller,
   painter/rocket UI, dual bet panels, history/fairness/rules sheets, reconnect.
5. Add game-center and existing owner-control integration.
6. Add SQL contract/invariant/concurrency/recovery/fairness tests and Flutter
   parsing/controller/layout tests.
7. Run local reset, lint, SQL verification, format, analyze, tests, and debug APK.
8. Stage exact files and create logical commits only after their validation passes.

## Security boundaries

- No direct client writes to rounds, bets, settings, events, leases, limits,
  reconciliation, or audit tables.
- `SECURITY DEFINER` only for narrow RPCs, fixed `search_path`, explicit grants,
  caller from `auth.uid()`, row/advisory locks, input/state/ownership validation.
- Realtime is delivery only; reconnect always calls `crash_v3_get_state()`.
- No production Supabase command, push, migration repair, old migration edit, or
  restored retired artifact.
