# Migration-History Transition — Dry-Run Plan (DESIGN ONLY, DO NOT EXECUTE)

Every command below is **redacted and unexecuted**. No production command has been
run. This package is working-tree-only and fully reversible.

Project ref (redacted): `<PROD_PROJECT_REF>` · DB password (redacted): `<PROD_DB_PASSWORD>`
Baseline cut version: `20261106000000` (production HEAD at dump time).

## Preconditions (all already satisfied by this package)
- `migrations_next/` validated on a real stack: two clean resets from zero, exact
  structural parity with prod, 0 duplicate objects, 0 SECDEF without search_path,
  Agency 28/28 + concurrency, Flutter analyze/test green.
- `migrations_legacy_archive/` holds a checksummed snapshot of all 216 legacy files.
- Legacy originals in `supabase/migrations/` are untouched.

## Future steps (executed later, only after human sign-off, in a maintenance window)

1. **Back up production** (physical + logical):
   `supabase db dump --linked --password <PROD_DB_PASSWORD> -f prod_full_backup_<UTC>.sql`
   plus confirm an automated daily backup exists in the dashboard.

2. **Verify PITR** is enabled and the recovery window covers the change window
   (dashboard → Database → Backups → Point-in-Time Recovery). Record the earliest
   restore timestamp.

3. **Open a maintenance window**; announce read-mostly / no-schema-change period.

4. **Freeze schema changes**: pause any migration-producing CI/CD; confirm no other
   operator will run `db push` / `migration repair` during the window.

5. **Move current migrations to archive** (working tree; reversible):
   `git mv supabase/migrations/* supabase/migrations_legacy_archive/`
   (the archive already contains identical checksummed copies; this only removes the
   duplicates from the active dir). Reversible with `git mv` back or `git revert`.

6. **Promote migrations_next**:
   `git mv supabase/migrations_next/00000000000000_schema_baseline.sql supabase/migrations/`
   `git mv supabase/migrations_next/20260711175349_agency_financial_foundation_v3.sql supabase/migrations/`
   `git mv supabase/migrations_next/20260711181414_agency_finance_v3_rpc_implementation.sql supabase/migrations/`
   Active `supabase/migrations/` now = baseline + 2 post-cut Agency migrations.

7. **Mark baseline as applied in production (HISTORY-ONLY, no DDL)**:
   `supabase migration repair --status applied 00000000000000 --project-ref <PROD_PROJECT_REF> --password <PROD_DB_PASSWORD>`
   This inserts the baseline version into `supabase_migrations.schema_migrations`
   WITHOUT running its SQL (prod already has the schema). Legacy version rows remain
   recorded as applied; they are not removed. Optionally also mark the 2 Agency
   versions applied ONLY after their real deployment (step 10) — NOT here.

8. **Verify production schema diff** = empty:
   `supabase db diff --linked --password <PROD_DB_PASSWORD> --schema public`
   Expect no differences (baseline == prod). Any diff → STOP and roll back (step below).

9. **Leave the Agency feature flag disabled**: the Agency V3 objects are deployed as
   schema only; the application feature flag stays OFF. No user-facing behavior change.

10. **Separate Agency cutover later**: deploy the 2 Agency migrations to prod as a
    normal `supabase db push` in a subsequent, independently-approved release; then
    enable the feature flag after its own validation. NOT part of this transition.

## Rollback (at any step, before/after history repair)
- **Working tree**: `git revert` the archive-move/promote commits, or `git mv` files
  back from `migrations_legacy_archive/` → `migrations/`. Checksums in
  `MANIFEST.json` verify integrity.
- **History repair reversal**: history-only rows are reversible by re-marking:
  `supabase migration repair --status reverted 00000000000000 --project-ref <PROD_PROJECT_REF> --password <PROD_DB_PASSWORD>`
  (prod DDL was never changed, so nothing to un-apply).
- **Catastrophic**: restore from the step-1 dump or PITR to the pre-window timestamp.
- Production schema is **never mutated** by this transition (baseline is history-only);
  the only prod change is a `schema_migrations` bookkeeping row, itself reversible.

## Non-goals / explicitly NOT done here
- No `supabase db push`, no `migration repair`, no `db diff` against prod executed.
- No deployment, no commit, no push, no Agency cutover, no production data change.
