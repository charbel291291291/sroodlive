# Phase 3 Staging and Rollback

1. Start the local Supabase stack and apply all migrations from empty history.
2. Run database lint/advisors and both Phase 3 verification suites.
3. Apply to a Supabase branch or isolated staging project, never production first.
4. Verify the authorization matrix for anon, user, cross-Agency owner, agent,
   hostess, Agency admin, finance admin and service role.
5. Run concurrent approval, double-submit, retry, ledger balance, state-transition
   and failure-injection tests.
6. Add server feature flags with legacy as default; no dual financial writes.
7. Monitor authorization denials, duplicate claims, unbalanced operations,
   wallet/ledger reconciliation, latency and retry rates.

Rollback is a new forward-only corrective migration: revoke newly granted RPCs,
disable the feature flag, preserve all V3 evidence, and return callers to the
unchanged legacy path. Never edit/delete an applied migration or remove ledger
history. A production rollback drill and backup verification are mandatory.
