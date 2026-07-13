# Legacy-to-Unified Mapping

| Legacy source | Target | Transformation and conflict rule |
| --- | --- | --- |
| `agency_applications` | `agency_applications` | Preserve UUID/user/message/status/review timestamps; normalize application type to requested role/action; archive unknown types/statuses without coercion. |
| `agency_members` | `agency_members` + `agency_role_assignments` | Preserve membership UUID where possible; split role into independent assignment; reject no row silently. |
| `agency_hosts` | `hostess_contracts` | Active row becomes contract candidate; preserve joined/left/application references; conflict with another active contract is quarantined. |
| `approved_hosts` | role/contract evidence archive | Approval is evidence, not a second authority; link to resulting contract or archive unmatched approval. |
| `host_availability` | `hostess_daily_activity`/availability adapter | Preserve schedule JSON as legacy payload until a validated normalized schedule mapping exists. |
| `host_targets` | monthly targets/performance | Copy target/actual/reward values and month; snapshot the legacy policy identifier; never recalculate. |
| `agency_audit_log` | `agency_audit_logs` | Preserve UUID, actor, event, entity links, detail, timestamp; mark source version. |
| `recharge_agencies` | unified `recharge_agencies` | Preserve UUID/code/owner/contact/status/rate; owner becomes independent role assignment. |
| `recharge_agents` | `recharge_agency_members` | Preserve UUID/user/code/agency/status/rate; null user rows are archived until resolved. |
| `recharge_packages` | recharge product catalog | Preserve IDs/prices/coin values/status/order; package catalog remains distinct from credit accounts. |
| `recharge_requests` | unified requests | Preserve all IDs, values, references, proof and decisions; generate deterministic migration idempotency key from source table+UUID. |
| `recharge_transactions` | unified transactions + ledger | Preserve authoritative values/status/reference; pending rows do not produce completed ledger credit. |
| `withdrawal_requests` | unified withdrawals + ledger references | Preserve split snapshot, diamonds, USD values, agency links and status; zero rows currently. |

## Null/default rules

- Never invent a user, agency, financial value, reviewer, or approval timestamp.
- Nullable legacy links remain null with migration diagnostics.
- Unknown statuses/types are archived and reported, not mapped to approved.
- Deterministic source identifiers make backfill rerunnable and idempotent.

## Verification and rollback

For every table: source/target exact count, per-status count, financial sums and
hash/sample verification. Rollback references source table and source UUID; no
legacy object is removed during backfill or read cutover.
