# Production hardening inventory

Generated on 2026-07-11 before hardening edits. This inventory describes the
repository state only; live database state has not yet been verified.

## Worktree boundary

- Starting branch: `main`; hardening branch: `security/full-production-hardening`.
- Existing modified Flutter files, deleted future migrations, Hungry Cat assets,
  `retired_migrations_removed_games/`, Firebase config, backup media, and the
  Rocket overflow migration are treated as user-owned changes.
- No existing change may be stashed, discarded, restored, renamed, or folded
  into a security correction without explicit evidence and review.

## High-severity findings

### `admin_audit_logs`

- Created by `20260605111935_step_12_full_admin_panel_roles.sql`.
- Current reconstructed schema is later expanded by
  `20260615230000_admin_role_system_rebuild.sql`.
- That migration creates `admin_audit_logs_insert` for `authenticated` with an
  unconditional `WITH CHECK (true)`.
- Audit rows are also written inside multiple admin `SECURITY DEFINER` RPCs:
  core admin, Hungry Cat admin, Rocket admin, moderation, and phase-two admin
  functions.
- No Flutter direct insert was found in the static scan.
- Required correction: remove all client write policies; revoke table
  `INSERT/UPDATE/DELETE` from `PUBLIC`, `anon`, and `authenticated`; retain
  writes inside already-authorized server functions only.

### `get_user_vip(uuid)`

- Defined as `SECURITY DEFINER` in
  `20260624000000_centralized_vip_system.sql`.
- Granted to both `authenticated` and `anon`.
- Returns user ID, VIP level, VIP start/expiry timestamps, VIP title, activity
  state, golden-ID state, and golden-ID expiry.
- Flutter caller: `lib/features/vip/services/vip_service.dart`.
- Required split: authenticated owner-private `get_my_vip()`, minimal public
  presentation contract, and admin-only contract only if a real caller exists.

## Privileged database surface

- Static migration history contains 513 `SECURITY DEFINER` occurrences and 392
  `GRANT EXECUTE` occurrences.
- One migration containing a definer function has no file-level `search_path`
  declaration: `20261024000000_retire_legacy_crash_direct_rls.sql`.
- This is a historical-source count, not the effective deployed function count;
  later `CREATE OR REPLACE` statements supersede earlier definitions.
- Priority domains: admin, audit, wallets, gifts, recharge/withdrawal, VIP,
  moderation, rooms, games/bets, rewards, agency/host commissions, uploads, and
  profile privacy.

## Logging

- Static scan: 228 `debugPrint` matches, 230 broad `print(` matches, one
  `recordError` match, no direct `developer.log` or `Crashlytics.log` matches.
- Confirmed sensitive candidates include logout user IDs, chat upload paths and
  URLs, room music URLs/local paths, and gift transaction details.
- A centralized redacting logger is not currently present.

## Migration state

- Many migration filenames are dated after 2026-07-11, extending through
  November 2026.
- Four future game migrations are currently deleted in the worktree and a
  `retired_migrations_removed_games/` directory is untracked; deployment intent
  is unknown and must not be inferred.
- Live/local reconciliation is pending `supabase migration list`, `db diff`, and
  `db lint`. No applied migration will be renamed or edited as the primary fix.

## Tests

- Flutter tests currently cover contracts, selected game models/layouts,
  gamification/profile models, room music, room/message models, VIP models, and
  app startup.
- One SQL contract test exists for Magic Srood.
- Dedicated attacker-oriented RLS/RPC suites do not yet exist for audit forgery,
  VIP privacy, direct-table denial, wallet concurrency, or idempotency.

## Oversized Flutter files

- `room_details_screen.dart`: 465,926 bytes.
- `admin_dashboard_screen.dart`: 310,822 bytes.
- `profile_screen.dart`: 133,523 bytes.
- Extraction must begin with stateless/low-risk UI and preserve ownership of
  subscriptions, timers, animation controllers, focus nodes, and observers.

## Build and configuration

- `android/app/google-services.json` is present and untracked.
- `.gitignore` ignores environment secrets but does not intentionally classify
  Firebase Android client configuration.
- `backup_gift_videos_20260703/` is present and untracked; runtime references
  still need verification before relocation.
- `flutter_plugin_android_lifecycle` is overridden to `2.0.21`; the comment says
  this avoids a compile-SDK incompatibility introduced through `file_picker`.
  Removal must be tested rather than assumed.

## Tooling constraints

- `rg` is unavailable in this environment; inventory uses PowerShell recursive
  scans.
- Flutter and Supabase commands may require external cache/network approval.
- Live security claims are prohibited until remote state and SQL behavior are
  verified directly.
