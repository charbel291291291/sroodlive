-- Rocket Crash security hardening
--
-- PROBLEM (audit S5):
-- settle_rocket_crash_round and start_rocket_crash_flight were granted to ALL
-- authenticated users. Any user could call these RPCs directly (via REST/SDK),
-- forcing early settlement of a live flight and causing other players to lose
-- their bets prematurely.
--
-- FIX:
-- Revoke the grants from authenticated. The backend pg_cron job
-- (advance_rocket_crash_rounds, running every 1 second) is the sole lifecycle
-- driver and does not need client-callable grants. The Flutter client no longer
-- triggers these RPCs; see corresponding Flutter changes in
-- rocket_crash_webview_screen.dart.
--
-- The _trySettleStuckRound client fallback has also been removed from the
-- Flutter client because the 1s cron makes it redundant and it required the
-- now-revoked grant.
--
-- Idempotent: REVOKE is safe to run if the grant was already revoked.

revoke execute on function public.settle_rocket_crash_round(uuid) from authenticated;
revoke execute on function public.start_rocket_crash_flight(uuid) from authenticated;
