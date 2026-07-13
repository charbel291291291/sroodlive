# Agency, Hostess, and Recharge Legacy Inventory

Generated from the repository on 2026-07-11. This is a source inventory only;
it does not assert that local migrations match the live Supabase database.

## Safety boundary

- No legacy object has been deleted or disabled.
- No financial or historical record has been modified.
- Live row totals are unverified.
- `supabase migration list` was run against the linked project on 2026-07-11.
  The `20261102000000` through `20261106000000` migrations are recorded as
  applied remotely despite their future timestamps. They are deployed history
  and must not be renamed, edited, or removed.
- `20260711021359_harden_admin_audit_and_vip_privacy.sql` is currently local
  only and unrelated to this Agency rebuild.
- Destructive replacement is blocked until live counts, totals, ownership,
  policies, grants, and migration history are verified.

## Active Flutter implementations

### User-facing screens

- `lib/features/profile_hub/screens/my_agency_screen.dart`
- `lib/features/profile_hub/screens/agency_management_screen.dart`
- `lib/features/profile_hub/screens/agency_owner_screen.dart`
- `lib/features/profile_hub/screens/admin_host_agency_review_screen.dart`
- `lib/features/wallet/screens/withdrawal_screen.dart`
- `lib/features/wallet/screens/recharge_help_screen.dart`
- `lib/features/wallet/widgets/recharge_request_sheet.dart`

### Services and models

- `lib/features/profile_hub/services/agency_service.dart`
- `lib/features/profile_hub/models/profile_hub_models.dart`
- `lib/features/admin/services/admin_service.dart`
- `lib/features/admin/models/admin_models.dart`
- `lib/features/wallet/services/wallet_service.dart`
- `lib/features/wallet/models/wallet_transaction.dart`

### Admin surface

- `lib/features/admin/screens/admin_dashboard_screen.dart` contains the current
  Agency, Host/Hostess, recharge, withdrawal, and finance administration UI.
- `lib/features/profile_hub/screens/admin_host_agency_review_screen.dart`
  implements an additional review surface.

### Existing tests

- `test/contracts/agency_hostess_contract_test.dart`
- `test/features/profile_hub/agency_models_test.dart`

## Repository database objects

### Linked database estimates (2026-07-11)

Read-only `pg_stat_user_tables` estimates from the linked project:

| Table | Estimated rows |
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

These are planner statistics, not reconciliation-grade exact counts. Exact
counts and financial sums are still required immediately before migration.

The linked policy catalog currently exposes 16 Agency-related policies. Most
are own-row or active-record reads. Administrative policies use the
`authenticated` database role and must be inspected function-by-function to
prove that their predicates call the authoritative admin-role checks. No
replacement policy may rely on `TO authenticated` alone.

### Tables with overlapping responsibilities

- `agency_applications`
- `agency_members` (defined by more than one migration generation)
- `agency_hosts`
- `approved_hosts`
- `host_availability`
- `host_targets`
- `agency_audit_log`
- `recharge_agencies`
- `recharge_agents`
- `recharge_packages`
- `recharge_requests`
- `recharge_transactions`
- `withdrawal_requests`

These objects can contain historical or financial data and must be preserved
until row-level mapping and reconciliation totals have been produced.

### Agency and Host/Hostess RPCs

- `_activate_approved_host`
- `_agency_audit`
- `_agency_grant_membership`
- `_gen_agency_code`
- `admin_assign_host_to_agency`
- `admin_list_host_agency_applications`
- `admin_remove_host_from_agency`
- `admin_review_agency_application`
- `agency_owner_list_hosts`
- `agency_owner_list_pending_applications`
- `agency_owner_review_application`
- `apply_to_become_host`
- `apply_to_create_agency`
- `apply_to_join_agency`
- `get_my_agency_membership`
- `get_my_host_availability`
- `get_my_host_status`
- `save_my_host_availability`

### Recharge RPCs

- `admin_create_recharge_agency`
- `admin_create_recharge_agent`
- `admin_list_recharge_agencies`
- `admin_list_recharge_agents`
- `admin_list_recharge_requests`
- `admin_set_recharge_agency_active`
- `admin_set_recharge_agent_active`
- `admin_update_recharge_agency`
- `admin_user_recharge_requests`
- `approve_recharge_request`
- `approve_recharge_transaction`
- `create_recharge_transaction`
- `reject_recharge_request`
- `request_recharge`

### Withdrawal RPCs

- `admin_approve_withdrawal`
- `admin_fetch_withdrawal_history`
- `admin_fetch_withdrawal_requests`
- `admin_reject_withdrawal`
- `preview_withdrawal_split`
- `request_withdrawal`

## Migration generations and conflicts

- `20260605062234_step_10_wallet_manual_recharge.sql` introduces recharge
  agencies, agents, requests, and broad client read/create policies.
- `20260606073000_full_social_economy_schema.sql` introduces recharge
  transactions and an early `agency_members` table.
- `20260606090000_profile_hub_ecosystem.sql` introduces agency applications.
- `20260606111500_fix_missing_user_support_feedback_badges_agency_level.sql`
  creates or repairs another agency membership/application contract.
- `20260612090000_economy_rebase_and_withdrawals.sql` introduces withdrawal
  records and financial behavior.
- `20261102000000_agency_hostess_foundation.sql` introduces a later agency-host
  foundation and audit log.
- `20261103000000_agency_phase2_rpcs.sql` adds a second RPC generation.
- `20261104000000_withdrawal_commission_split.sql` changes withdrawal and
  commission behavior.
- `20261105000000_agency_hostess_production_contract.sql` adds a third agency
  application and administration contract.

The November migrations are future-dated but confirmed in remote migration
history. They coexist with the June generation on the linked project. Any
replacement must therefore use forward-only migrations, preserve their history,
and verify live data before disabling either generation.

## Current role vocabulary

Observed concepts include admin, agency owner, host, approved host, agency
member, applicant, recharge agency, recharge agent, and withdrawal reviewer.
The requested manager, recruiter, hostess, agency admin, and finance admin
roles are not yet represented by one authoritative independent assignment
model.

## Current financial flows

- Manual recharge request and approval.
- Recharge transaction creation and approval.
- Recharge agency and agent administration.
- Withdrawal request, previewed split, approval, rejection, and history.
- Host/agency commission split introduced by a later migration generation.

The repository does not yet demonstrate one immutable ledger and one shared
idempotency contract across these flows.

## Required evidence before replacement

1. Export effective live table, function, trigger, policy, and grant catalogs.
   Local and remote migration versions otherwise match for the deployed Agency
   generations.
3. Record row counts for every legacy table.
4. Record recharge, withdrawal, commission, and settlement totals using the
   authoritative numeric columns from the live schema.
5. Map every old role and active membership to the normalized role model.
6. Prove one-active-contract constraints for hostesses.
7. Define archival handling for malformed rows.
8. Apply and test the replacement in a disposable/staging database.
9. Cut over Flutter and Admin callers in the same release.
10. Remove legacy objects only after count and financial-total reconciliation.

## Supabase platform note

Supabase's 2026 Data API change means new public tables may require explicit
Data API grants in addition to RLS. The replacement must use explicit grants,
RLS on every exposed table, restricted function execution, fixed function
search paths, and server-derived authorization.
