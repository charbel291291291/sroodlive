# Agency Security Audit

Read-only catalog audit of the linked project on 2026-07-11.

## Table exposure

- All 13 inventoried tables have RLS enabled.
- `anon` has no effective SELECT/INSERT/UPDATE privilege on these tables.
- `authenticated` has SELECT on all 13 tables.
- `authenticated` has INSERT on `recharge_requests` and UPDATE on
  `agency_applications`; policies must enforce ownership and admin roles.
- No effective authenticated DELETE grant was observed.

## Critical function findings

The following financial `SECURITY DEFINER` functions are executable by
`PUBLIC`, `anon`, and `authenticated`:

- `admin_approve_withdrawal`
- `admin_reject_withdrawal`
- `approve_recharge_transaction`
- `create_recharge_transaction`
- `apply_vip_recharge_exp`
- `preview_withdrawal_split`
- `request_withdrawal`

They use `search_path=public`, rather than an empty fixed search path with every
relation schema-qualified. This is a critical privilege and search-path risk.
The `admin_*` withdrawal functions being anon-executable is especially severe,
even if their bodies perform an internal role check.

Other Agency RPCs correctly revoke anon/PUBLIC execution but still use
`search_path=public`; their bodies require a separate authorization review.

## Policy findings

Sixteen related policies exist. The principal risks requiring body inspection:

- `Admins can update agency applications` targets `authenticated`; its predicate
  must call the authoritative admin-role system and must have both USING and
  WITH CHECK.
- Active recharge agency/agent/package reads intentionally expose catalog data
  only to authenticated users.
- Own-record reads exist for applications, requests, transactions, withdrawals,
  availability, membership, and host state.
- Audit writes are not directly granted to authenticated users.

## Required remediation design (not deployed)

1. Revoke EXECUTE from PUBLIC and anon for every financial definer RPC.
2. Put internal privileged writers in a non-exposed schema.
3. Derive actor identity only from `auth.uid()`.
4. Use `SET search_path = ''` and schema-qualified objects.
5. Verify independent agency-admin and finance-admin assignments server-side.
6. Add immutable idempotency keys and row locking to recharge, withdrawal,
   settlement, and commission operations.
7. Write an immutable financial ledger and Agency audit event in the same
   transaction.
8. Add attacker-oriented RPC and RLS tests before deployment.

## Classification

- RLS enabled: Pass
- Anon direct table writes: Pass
- Least-privilege function execution: **Critical fail**
- Fixed safe definer search paths: **High fail**
- Unified idempotency: **High gap**
- Unified immutable ledger: **High gap**
- Cross-agency authorization proof: **Not yet proven**
