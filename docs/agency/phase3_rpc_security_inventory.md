# Phase 3 RPC Security Inventory

Read-only live catalog evidence collected 2026-07-11. All seven functions are
owned by `postgres`, are `SECURITY DEFINER`, use `search_path=public`, and are
executable by `PUBLIC`, `anon`, and `authenticated` before the proposed migration.

| Function | Source | Callers | Writes / impact | Authorization and risk | Remediation |
| --- | --- | --- | --- | --- | --- |
| `admin_approve_withdrawal(uuid,text)` | `20261106000000_agency_system_canonical_contract.sql` | finance admin UI | withdrawal status, agency wallet, wallet transaction, audit | `auth.uid()` + `has_finance_access()`; replay protected only by pending state | revoke PUBLIC/anon; authenticated only; fixed path |
| `admin_reject_withdrawal(uuid,text)` | same | finance admin UI | withdrawal status, wallet refund, transaction, audit | same; state lock prevents repeat refund | same |
| `approve_recharge_transaction(uuid,text,text)` | `20260606073000_full_social_economy_schema.sql`, later VIP migration | finance admin UI | user wallets, legacy wallets, recharge status, coin transaction, VIP | `auth.uid()` + finance check; pending lock prevents repeat credit | same; internalize VIP helper |
| `create_recharge_transaction(uuid,text,text)` | `20260606073000_full_social_economy_schema.sql` | authenticated customer | recharge transaction | actor is `auth.uid()`; payment reference has replay/duplicate risk | authenticated only; future idempotency |
| `apply_vip_recharge_exp(uuid,bigint)` | VIP recharge migration | internal recharge approval | profiles and VIP subscriptions | trusts supplied user ID and amount; critical if directly callable | revoke authenticated; service/internal only |
| `preview_withdrawal_split(integer)` | canonical Agency migration | authenticated customer | read-only financial preview | actor is `auth.uid()`; validates membership server-side; non-positive preview allowed | authenticated only; fixed path; validate positive in V3 |
| `request_withdrawal(integer,text,text,text)` | canonical Agency migration | authenticated customer | wallet debit, transaction, withdrawal request | actor and Agency derived server-side; wallet locked; one-pending guard but no idempotency result | authenticated only; fixed path; V3 idempotency |

## Cross-cutting findings

- No function accepts a client-supplied actor ID.
- `apply_vip_recharge_exp` accepts a spoofable beneficiary and value and therefore
  must never be a client endpoint.
- Admin authorization is server-side, but exposure to anon/PUBLIC is needless.
- State checks reduce replay effects for approvals; request creation lacks a
  durable idempotency contract.
- Proposed hardening does not rewrite function bodies and preserves legitimate
  authenticated callers.
