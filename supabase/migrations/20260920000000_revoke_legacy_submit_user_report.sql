-- Security fix: revoke legacy submit_user_report(text,text,text,text) from authenticated
--
-- This older RPC accepts target_type and target_id as plain text, lacks the
-- cannot_report_self guard, and bypasses evidence capture. The Flutter client
-- already calls submit_user_report_with_evidence exclusively.
-- Revoking the grant prevents direct API calls from inserting structurally
-- different report rows that skip evidence and user-id validation.
--
-- The function is kept in place; the grant is revoked — mirrors the pattern used
-- in 20260916000000_rocket_crash_security_fixes.sql and
-- 20260917000000_revoke_local_crash_cashout.sql.
--
-- Idempotent: REVOKE is safe to run if the grant was already revoked.

revoke execute on function public.submit_user_report(text, text, text, text)
  from authenticated;
