# Phase 4 Authorization Test Results

| Test group | Expected | Actual | Status |
| --- | --- | --- | --- |
| anon/PUBLIC RPC denial | denied | not run locally | Blocked |
| impersonation/cross-Agency | denied | not run | Blocked |
| agent self-approval | denied | static guard present | Not executed |
| host target mutation | denied | not run | Blocked |
| unrelated owner access | denied | not run | Blocked |
| audit forgery/direct writes | denied | grants/triggers prepared | Not executed |
| authenticated VIP helper | denied | revoke prepared | Not executed |

Blocker: Docker/local Supabase unavailable. Existing live read-only evidence still
shows all seven public RPCs exposed because migrations were not deployed.
