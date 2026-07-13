# Phase 2 Exact Production Reconciliation

Evidence collected read-only from the linked Supabase project on 2026-07-11.
No production row was modified.

## Exact counts

| Table | Exact rows |
| --- | ---: |
| agency_applications | 2 |
| agency_audit_log | 2 |
| agency_hosts | 0 |
| agency_members | 0 |
| approved_hosts | 0 |
| host_availability | 0 |
| host_targets | 0 |
| recharge_agencies | 1 |
| recharge_agents | 1 |
| recharge_packages | 7 |
| recharge_requests | 2 |
| recharge_transactions | 1 |
| withdrawal_requests | 0 |

## Exact financial totals

| Source/status | Rows | Coins | USD | Diamonds |
| --- | ---: | ---: | ---: | ---: |
| recharge_requests / approved | 2 | 51,000 | 6.00 | 0 |
| recharge_transactions / pending | 1 | 2,500,000 | 5.00 | 0 |
| withdrawal_requests / all | 0 | 0 | 0.00 | 0 |

Recharge package catalog totals: 7 packages, 3,760,000 base coins,
0 bonus coins, 3,760,000 total coins, USD 188.00 list-price sum.

Host target totals are all zero because `host_targets` contains no rows.

## Status evidence

- `agency_applications`: approved = 2
- `recharge_requests`: approved = 2
- `recharge_transactions`: pending = 1
- No other status-bearing Agency table currently contains rows.

## Data quality evidence

All checks returned zero:

- duplicate recharge request reference codes
- duplicate transaction payment references
- missing auth users for requests, transactions, withdrawals, members, hosts,
  and recharge agents
- orphan recharge agent agency links
- orphan recharge request agency or agent links
- negative recharge, transaction, or withdrawal financial values
- null required recharge, transaction, or withdrawal financial values

## Reconciliation gap and risk

The two approved recharge requests total 51,000 coins/USD 6.00, while the one
pending recharge transaction totals 2,500,000 coins/USD 5.00. These are
different workflows and are not linked by a shared immutable identifier.
They must not be netted or assumed equivalent. There is no unified financial
ledger or idempotency key spanning them.

Risk: **High** until request-to-transaction lineage and wallet ledger effects
are reconciled from the exact RPC bodies and wallet transaction records.

## SQL evidence

The reproducible read-only statements are maintained in
`supabase/verification/agency_phase2_verification.sql`.
