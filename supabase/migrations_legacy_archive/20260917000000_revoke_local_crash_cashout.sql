-- Security fix: revoke cashout_crash_bet_local from authenticated users
--
-- cashout_crash_bet_local trusts the client-supplied p_multiplier with no
-- server-side cap. The Flutter UI never calls this function (the WebView screen
-- uses refundBet / markBetLost only), making it a dead client path — but the
-- GRANT still allows any authenticated user to call it directly via the REST/SDK
-- API with an arbitrary multiplier (e.g. 1,000,000) and drain coins.
--
-- Fix: revoke the grant, mirroring the pattern used in
-- 20260916000000_rocket_crash_security_fixes.sql for settle_rocket_crash_round.
-- The function is kept in place for potential future use but cannot be called
-- by clients until the grant is explicitly re-added.
--
-- Idempotent: REVOKE is safe to run if the grant was already revoked.

revoke execute on function public.cashout_crash_bet_local(uuid, numeric) from authenticated;
