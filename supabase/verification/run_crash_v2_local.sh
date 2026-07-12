#!/usr/bin/env bash
# Crash Rocket v2 — full local DB validation from zero (bare supabase/postgres
# container as the superuser test harness). Run once Docker is healthy:
#   bash supabase/verification/run_crash_v2_local.sh
#
# Applies: baseline v2 + agency migrations + the three crash v2 migrations,
# then the bootstrap + the 24-check executable suite, then a concurrency race.
# Exits non-zero on any FAIL. Does not touch production.
set -uo pipefail
cd "$(dirname "$0")/../.."

IMG=public.ecr.aws/supabase/postgres:17.6.1.127
C=crashv2run
PSQL=(docker exec -i "$C" psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1)

echo "== (re)creating container =="
docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --name "$C" -e POSTGRES_PASSWORD=postgres "$IMG" >/dev/null
until docker exec "$C" pg_isready -U supabase_admin >/dev/null 2>&1; do sleep 2; done
for _ in $(seq 1 40); do
  ok=$(docker exec "$C" psql -U supabase_admin -d postgres -tA \
        -c "select count(*) from pg_tables where schemaname='storage' and tablename='buckets'" 2>/dev/null)
  [ "$ok" = "1" ] && break; sleep 2
done
echo "== storage shim (bare container lacks storage-api; matches its DDL) =="
# The bare supabase/postgres image creates the `storage` schema but NOT
# storage.buckets/objects (those come from the storage-api service). The
# baseline's config section writes bucket rows, so provide the two tables the
# storage-api would create. Test-harness only — identical to the image
# pre-creating auth.users.
docker exec -i "$C" psql -U supabase_admin -d postgres -q -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
create schema if not exists storage;
create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz default now()
);
create or replace function storage.foldername(name text) returns text[]
  language sql immutable as $fn$ select string_to_array(name, '/') $fn$;
alter table storage.objects enable row level security;
SQL

echo "== applying migrations =="
apply() { echo "  -> $1"; docker exec -i "$C" psql -U supabase_admin -d postgres -q -v ON_ERROR_STOP=1 < "$1" \
            > /tmp/crashv2_apply.log 2>&1 || { echo "APPLY FAILED: $1"; tail -20 /tmp/crashv2_apply.log; exit 1; }; }
apply supabase/migrations_next/00000000000000_schema_baseline.sql
apply supabase/migrations/20260711175349_agency_financial_foundation_v3.sql
apply supabase/migrations/20260711181414_agency_finance_v3_rpc_implementation.sql
apply supabase/migrations/20261107000000_retire_legacy_crash_games.sql
apply supabase/migrations/20261107000001_crash_v2_foundation.sql
apply supabase/migrations/20261107000002_crash_v2_engine_and_rpcs.sql

echo "== bootstrap + suite =="
docker exec -i "$C" psql -U supabase_admin -d postgres -q < supabase/verification/crash_v2_local_bootstrap.sql >/dev/null
OUT=$(docker exec -i "$C" psql -U supabase_admin -d postgres 2>&1 < supabase/verification/crash_v2_executable_tests.sql)
echo "$OUT" | grep -E 'T[0-9]+|PASS|FAIL' | sed 's/^psql:.*NOTICE:  //;s/^NOTICE:  //'

echo "== concurrency: parallel double-cashout must yield one winner =="
docker exec -i "$C" psql -U supabase_admin -d postgres -q >/dev/null <<'SQL'
truncate public.crash_v2_bets, public.crash_v2_round_events,
         public.crash_v2_round_secrets, public.crash_v2_rounds cascade;
update public.wallets set coins_balance=1000000 where user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
select public.crash_v2_tick(null);
update public.crash_v2_rounds set betting_open_at=now()-interval '1 second' where status='waiting';
select public.crash_v2_tick(null);
-- pin a high crash target so the derived crash instant is far in the future
update public.crash_v2_round_secrets set target_multiplier=100.00
 where round_id=(select id from public.crash_v2_rounds order by public_round_number desc limit 1);
select public.crash_v2_place_bet(null,1,1000,null,'race-000000001');
-- close betting: push BOTH timestamps back so close > open (table CHECK holds)
update public.crash_v2_rounds
 set betting_open_at=now()-interval '30 seconds', betting_close_at=now()-interval '3 seconds'
 where status='betting_open';
select public.crash_v2_tick(null);   -- -> flying
update public.crash_v2_rounds set started_at=now()-interval '3 seconds' where status='flying';
SQL
BID=$(docker exec -i "$C" psql -U supabase_admin -d postgres -tA -c "select id from public.crash_v2_bets limit 1")
( docker exec -i "$C" psql -U supabase_admin -d postgres -tA -c \
    "select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false); select (public.crash_v2_cash_out('$BID','raceA-00000001')->>'idempotent');" 2>&1 &
  docker exec -i "$C" psql -U supabase_admin -d postgres -tA -c \
    "select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false); select (public.crash_v2_cash_out('$BID','raceB-00000001')->>'idempotent');" 2>&1 &
  wait )
FINAL=$(docker exec -i "$C" psql -U supabase_admin -d postgres -tA -c \
  "select 'cashed='||count(*) filter (where status='cashed_out')||' payouts='||coalesce(sum(payout),0)||' events='||(select count(*) from public.crash_v2_round_events where event_type='bet_cashed_out') from public.crash_v2_bets")
echo "CONCURRENCY: $FINAL  (want exactly one cashout, one payout, one event)"

FAILS=$(echo "$OUT" | grep -c 'FAIL')
echo "== FAIL count: $FAILS =="
docker rm -f "$C" >/dev/null 2>&1 || true
[ "$FAILS" = "0" ] || exit 1
