-- Rocket Crash realtime fix: set REPLICA IDENTITY FULL on the global rounds table.
--
-- ROOT CAUSE
-- The round lifecycle (betting -> flying -> crashed -> next betting) is driven
-- entirely by UPDATE statements on public.rocket_crash_global_rounds. That table
-- is published to supabase_realtime, but its replica identity was left at the
-- default (primary key only). With default replica identity, Postgres logical
-- replication emits UPDATE events that carry NO column values, so the Flutter
-- client receives realtime payloads with newRecord={} / oldRecord={}
-- (observed as newKeys=[] oldKeys=[]). The client therefore never sees the
-- status/round_number changes and cannot follow phase transitions.
--
-- This mirrors the existing rooms fix in
-- 20260721000000_fix_rooms_realtime.sql which documents the same requirement:
-- "Without REPLICA IDENTITY FULL the UPDATE payload carries no column values."
--
-- FIX
-- REPLICA IDENTITY FULL makes every UPDATE event include all column values in
-- newRecord (and the previous values in oldRecord). Cost is a marginally larger
-- WAL record per UPDATE; the rounds table updates only a few times per ~15s
-- round, so the overhead is negligible. Fully reversible via REPLICA IDENTITY
-- DEFAULT.
--
-- Idempotent: ALTER ... REPLICA IDENTITY FULL is safe to run repeatedly.

ALTER TABLE public.rocket_crash_global_rounds REPLICA IDENTITY FULL;

-- The bets table is fetched via RPC (get_rocket_crash_round_bets), not realtime,
-- but set FULL too so any future realtime subscription on it also carries values.
ALTER TABLE public.rocket_crash_global_bets REPLICA IDENTITY FULL;
