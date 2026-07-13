# Prepare validated Supabase schema baseline transition

> **Draft.** Working-tree-only migration-history transition package. **No production
> changes of any kind.** Do not merge without the human-gated cutover checklist below.

## Purpose
Replace the un-replayable historical migration chain with a single, production-derived,
**public-only** squashed baseline plus the post-cut Agency Finance V3 migrations — packaged
reversibly, with the legacy chain archived (not deleted) for provenance.

## Root cause of the broken legacy migration chain
The history has **no baseline**; it is a partial ALTER-log over a manually-built prod schema:
- Foundational tables/views (`profiles`, `rooms`, `room_members`, leaderboard views) were
  created **manually**, never by a migration — so a from-zero replay fails at the first
  migration that references them (`20260602122424` → `public.room_members`).
- Objects are **altered before they are created** (e.g. `room_schedules` altered by
  `20260611100952`, created later), and prod apply-order ≠ filename order.
No forward-only edit can fix a failure *inside* an already-applied migration. The only clean
path is a squash: one exact baseline == current production schema.

## Validated public-only baseline
`migrations_next/00000000000000_schema_baseline.sql` — assembled from a **read-only
`--schema public`** production dump. Contains no platform schema DDL, no platform ownership,
no production data, no secrets. Applies cleanly under a real `supabase db reset` (as the
`postgres` migration role). Structural parity with production is exact:

| tables | functions | SECDEF | views | policies | RLS tables | FKs | indexes | enums | storage buckets | storage policies | realtime tables |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 159 | 385 | 372 | 3 | 259 | 159 | 231 | 403 | 2 | 8 | 27 | 25 |

SECURITY DEFINER hardening: **all** SECDEF functions have a fixed `search_path`
(`secdef_no_sp = 0`) after pinning the 2 prod functions that lacked it.

## `migrations_next` contents
1. `00000000000000_schema_baseline.sql` — the squashed baseline.
2. `20260711175349_agency_financial_foundation_v3.sql` — post-cut Agency V3 ledger.
3. `20260711181414_agency_finance_v3_rpc_implementation.sql` — post-cut Agency V3 RPCs.

Plus docs: `BASELINE_MANIFEST.md`, `TRANSITION_DRYRUN_PLAN.md`, `PR_DESCRIPTION.md`,
`ci_migration_validation.draft.yml`.

## Legacy archive + checksum manifest
`migrations_legacy_archive/` holds a **checksummed snapshot of all 216 legacy migrations**
(originals left in place, nothing deleted). `MANIFEST.json` classifies every file
(sha256, size, `included_in_baseline`, reason): 208 `legacy_prod_applied`, 3
`reconstructed_baseline_helper`, 3 `hardening_already_in_prod`, 2 `post_cut_agency_v3`;
**0 unclassified**. Baseline cut = production HEAD `20261106000000`.

Only migrations whose effect is **absent** from the baseline are promoted post-cut — verified
via read-only introspection that the 3 hardening and 3 reconstruction migrations already have
their effects in production, so only the genuinely-absent Agency V3 pair is promoted.

## Validation results
- **Two clean `supabase db reset` from zero: both exit 0** (baseline + 2 Agency migrations).
- **Agency Finance V3: 28/28 PASS, 0 FAIL** — idempotency, rollback, ledger zero-net,
  reversal, self-approval, withdrawal direction, immutability, authorization/RLS isolation.
- **Concurrency:** parallel double-post → exactly one winner, `unbalanced = 0`.
- **No duplicate** function signatures / policies / indexes / buckets / realtime memberships.
- **Flutter analyze: no issues. Flutter test: 62/62 pass.**

## Inherited lint debt (not a regression)
`supabase db lint --local` reports 22 error-level `plpgsql_check` findings that are **verified
pre-existing in production** and reproduced verbatim by the baseline (columns genuinely absent
in prod such as `user_vip_subscriptions.started_at`; `admin_record_audit` 2-overload
ambiguity; `digest`/`gen_random_bytes` resolved via the `extensions` schema — a linter
search_path artifact). The CI draft gates on *new* errors beyond this inherited baseline.

## Explicit safety statements
- **No production migration repair was executed.**
- **No Agency cutover occurred** — Agency V3 ships as schema only; feature flag stays disabled.
- **The production transition remains separately gated** (see `TRANSITION_DRYRUN_PLAN.md`):
  backup → PITR verify → maintenance window → archive move → promote → history-only
  `migration repair` → schema-diff verify. None executed here.

## Rollback plan
Working tree is reversible by `git revert` / restoring from `migrations_legacy_archive/`
(checksums in `MANIFEST.json`). The future history-repair step is itself reversible
(`migration repair --status reverted`), and prod DDL is never mutated — only a
`schema_migrations` bookkeeping row would change. Catastrophic fallback: PITR / backup restore.

## Reviewer checklist
- [ ] Baseline is public-only (no `storage`/`auth`/`graphql_public` schema DDL, no platform ownership).
- [ ] No raw/normalized dump, secret, key, or connection string committed.
- [ ] `migrations_legacy_archive/` = 216 files, checksums match, nothing deleted.
- [ ] `migrations_next/` = baseline + 2 Agency migrations + docs only; no duplicate versions.
- [ ] Two clean resets pass locally; Agency 28/28; Flutter analyze + 62 tests pass.
- [ ] Inherited lint set unchanged (no new errors).
- [ ] Cutover checklist understood; **do not** run `migration repair` / `db push` on merge.
- [ ] PR kept as **draft** until cutover is scheduled and approved.
