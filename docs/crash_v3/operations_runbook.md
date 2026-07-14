# Crash Rocket V3 operations runbook

Crash V3 ships disabled. Do not enable it until migrations are applied, the
engine secrets are configured, the engine is continuously invoked, and its
heartbeat is visible in Owner Game Control.

## Required Edge Function secrets

- `SUPABASE_URL` (provided by Supabase)
- `SUPABASE_SERVICE_ROLE_KEY` (provided by Supabase; never expose to Flutter)
- `CRASH_V3_ENGINE_SECRET` (at least 32 random bytes, supplied to the internal
  invoker in `x-crash-engine-secret`)
- `CRASH_V3_SEED_ENCRYPTION_KEY` (base64 encoding of exactly 32 random bytes)
- `CRASH_V3_ENGINE_INSTANCE_ID` (stable unique deployment identity, 8–128 chars)

The function keeps one request alive for at most 50 seconds and ticks every
200 ms. The infrastructure scheduler must invoke it continuously using a
service-role JWT plus the internal engine header. Overlapping invocations are
safe: PostgreSQL advisory locking and the 15-second renewable lease enforce
ownership. Monitoring must alert when `expires_at` has passed or heartbeat age
exceeds 15 seconds. Keep `game_enabled=false` whenever no healthy invoker is
available.

Seed ciphertext uses AES-256-GCM with a unique 96-bit IV per round. Rotate the
encryption key only when no unresolved round exists; an unresolved ciphertext
must remain decryptable for recovery and reveal.

## Failure actions

1. Use Emergency stop in Owner Game Control.
2. Keep the old encryption key available until every active round settles or
   is cancelled and refunded.
3. Inspect reconciliation before resuming. Never silently adjust a wallet.
4. Use the cancelled-round refund RPC only for a cancelled round. It locks bets
   and refunds only `accepted` rows, so retries are idempotent.
5. Resume only after the engine heartbeat is current. Admins cannot choose or
   override a crash result.

## Local validation

```text
supabase stop --no-backup
supabase start
supabase db reset
supabase db lint --local
Get-Content -Raw supabase/tests/crash_v3_backend_contract.sql |
  docker exec -i supabase_db_srood_live psql -v ON_ERROR_STOP=1 -U postgres -d postgres
flutter pub get
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

The current Windows Docker Desktop environment reports Supabase Storage as
unhealthy even though its process logs show it listening. Crash V3 does not use
Storage. Migration success and Crash V3 SQL tests must still be checked against
the local Postgres container; never substitute a production reset.
