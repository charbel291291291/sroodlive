# Agency Dependency Map

## Flutter dependencies

| Path | Object/feature | Behavior | Impact | Replacement destination |
| --- | --- | --- | --- | --- |
| `lib/features/profile_hub/services/agency_service.dart` | Agency RPC set | Reads membership/status; submits/reviews applications and availability | High security | unified Agency repository using new read/mutation RPCs |
| `lib/features/profile_hub/models/profile_hub_models.dart` | `AgencyApplication`, `AgencyMembership` | Client parsing | Medium migration | versioned unified DTOs |
| `lib/features/profile_hub/screens/my_agency_screen.dart` | `get_my_agency_membership`, host/apply flows | User navigation and mutations | High | role-aware Agency hub |
| `lib/features/profile_hub/screens/agency_owner_screen.dart` | owner host/application RPCs | Agency owner operations | High | owner dashboard |
| `lib/features/profile_hub/screens/agency_management_screen.dart` | legacy management tables | Direct/legacy management surface | Critical | remove after unified admin/owner cutover |
| `lib/features/profile_hub/screens/admin_host_agency_review_screen.dart` | admin review RPCs | Admin application review | High | unified Admin Agency module |
| `lib/features/admin/screens/admin_dashboard_screen.dart` | recharge, withdrawal, Agency modules | Administrative reads and approvals | Critical financial | unified permission-scoped Admin Agency section |
| `lib/features/admin/services/admin_service.dart` | admin Agency/recharge/withdrawal RPCs | Privileged mutation | Critical financial | finance/agency admin repositories |
| `lib/features/wallet/widgets/recharge_request_sheet.dart` | `request_recharge` | Creates recharge request | Critical financial | unified recharge request RPC |
| `lib/features/wallet/screens/withdrawal_screen.dart` | withdrawal RPCs | Preview and request withdrawal | Critical financial | unified withdrawal RPC |
| `lib/features/profile/profile_screen.dart` | Agency navigation entry | Opens secured Agency screen | Medium | unified role router |

## Database dependencies

| Object | Reads/writes | Financial/security impact | Proposed destination |
| --- | --- | --- | --- |
| `agency_applications` | user submit, owner/admin review | role assignment | unified `agency_applications` |
| `agency_members` | membership read | cross-tenant access | unified `agency_members` plus role assignments |
| `agency_hosts`, `approved_hosts` | host approval/membership | duplicate authority | unified host contract/membership state |
| `host_availability`, `host_targets` | own schedule; admin targets | earnings inputs | host daily activity and monthly targets |
| `agency_audit_log` | privileged append, scoped read | audit integrity | immutable `agency_audit_logs` |
| `recharge_agencies`, `recharge_agents` | admin management/catalog read | financial authority | unified recharge agencies/members |
| `recharge_requests`, `recharge_transactions` | user/admin mutation | wallet/coins | unified request + immutable transaction/ledger |
| `withdrawal_requests` | user request/admin approval | USD/diamonds | unified withdrawal + financial ledger |

## Realtime, routes, and jobs

- No dedicated Agency provider/controller was found; screens call services and
  RPCs directly.
- Admin changes are refreshed by screen queries; a single authoritative Agency
  realtime coordinator does not exist.
- Profile and Settings route to multiple Agency screens.
- No Agency-specific Edge Function or scheduled job was found in the repository
  search. Database triggers/functions remain the effective server workflow.

## Migration risk

Highest-risk cutovers are recharge approval, withdrawal approval, host/Agency
membership authority, and Admin dashboard visibility. Reads and writes must not
be split across legacy and unified sources during a release.
