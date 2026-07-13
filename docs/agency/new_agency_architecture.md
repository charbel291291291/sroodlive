# Unified Agency Architecture Proposal

Documentation only; no table has been created.

## Principles

- One independent role assignment model; users may hold multiple roles.
- UUID keys, server timestamps, actor from `auth.uid()`, soft deletion for
  business entities, immutable financial and audit records.
- Versioned policies with effective date ranges; historical calculations retain
  their original policy version.
- Explicit Data API grants plus RLS; no implicit access.
- Financial mutation through transactional, idempotent server RPCs only.

## Core tables

### `agencies`

Agency identity and lifecycle. UUID PK; unique code; owner is represented by a
role assignment, not a trusted client field. Status enum draft/active/suspended/
closed; timestamps and soft-delete marker. Index status/code.

### `agency_members`

Membership identity: agency FK, user FK, status, joined/left timestamps. Unique
active membership per agency/user. RLS scoped through verified membership.

### `agency_role_assignments`

Independent roles owner/manager/recruiter/hostess with valid-from/to, assigned
by, revoked-by, permissions version. Partial unique constraints for active role.

### `agency_applications`

Applicant, requested role/action, target agency, status, review reason and
reviewer. Unique active application per user/type/agency.

### `hostess_contracts`

Hostess, agency, status, effective dates, immutable policy-version references.
Partial unique index ensures one active hostess contract globally.

### `hostess_target_policies` and `hostess_monthly_targets`

Versioned approved policy plus per-contract monthly snapshot. Financial targets
are immutable after period close.

### `hostess_daily_activity` and `hostess_monthly_performance`

Server-recorded activity and derived monthly snapshot. Unique contract/date and
contract/month keys. Hostess reads own rows; operators cannot edit finalized data.

### `agency_commission_policies` and `agency_settlements`

Versioned commission rules and immutable settlement snapshots. Approval is a
finance-admin RPC transition, not a client update.

### `recharge_agencies` and `recharge_agency_members`

Recharge business identity and independent owner/agent roles. Never inferred
from hostess Agency roles.

### `recharge_credit_accounts` and `recharge_limits`

Locked credit balance/version and versioned daily/monthly agent limits. Credit
changes only through ledger-backed RPCs.

### `recharge_requests` and `recharge_transactions`

Customer intent and immutable completed/reversed operation. Both carry unique
idempotency keys and request linkage. Transactions never become editable history.

### `withdrawal_requests`

Requester, source account, requested value, locked policy snapshot, workflow
status/reason. Approval and rejection are finance-admin RPCs.

### `financial_ledger`

Append-only double-entry-style events: account, currency, signed amount,
operation type/id, idempotency key, actor and server timestamp. Unique operation
and idempotency constraints; no client INSERT/UPDATE/DELETE.

### `agency_audit_logs`

Append-only action metadata with server actor/timestamp. Restricted internal
writer; scoped admin read only.

## RLS matrix

- Hostess: own contract/targets/activity/performance/settlements.
- Owner/manager: rows for verified assigned agency, with distinct mutation scope.
- Recruiter: applications/invitations only; no financial columns.
- Recharge owner: own recharge business, credit, agents, operations.
- Recharge agent: own permitted operations and limits; no approval or limit edit.
- Agency admin: Agency lifecycle/contracts/policies through verified RPCs.
- Finance admin: credit, settlement, withdrawal, fraud transitions through RPCs.
- Anon: no access.

## Required indexes and constraints

Every FK indexed; unique codes; partial unique active contracts/assignments;
non-negative limit and amount checks; valid effective date ranges; immutable
finalized rows; unique idempotency and external transaction references.
