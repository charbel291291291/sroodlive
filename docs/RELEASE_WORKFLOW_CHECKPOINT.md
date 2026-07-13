# Release Workflow Checkpoint — Schema Baseline Transition Package

**Status: PAUSED (intentionally, by user request) before Phase 5.**
Priority temporarily shifted to a separate Crash Rocket v2 rebuild. This file records
exactly where the release workflow stands so it can be resumed safely and independently.

Checkpoint created: 2026-07-12 (local session).

---

## 1. Current branch
`security/full-production-hardening`

> The release workflow has **not** yet created its dedicated branch
> (`chore/schema-baseline-transition-package`). Nothing has been committed or pushed.

## 2. Git status (working tree — nothing staged, nothing committed)
Tracked modifications (pre-existing, unrelated to the package):
```
 M .gitignore                    <- package-related: added dump + secret ignores (see §Notes)
 M lib/features/games/screens/crash_rocket_screen.dart      (pre-existing, unrelated)
 M lib/features/games/screens/magic_srood_screen.dart       (pre-existing, unrelated)
 M lib/features/profile/profile_screen.dart                 (pre-existing, unrelated)
 M lib/features/rooms/screens/room_details_screen.dart      (pre-existing, unrelated)
 M lib/features/rooms/screens/rooms_screen.dart             (pre-existing, unrelated)
 M lib/features/vip/services/vip_service.dart               (pre-existing, unrelated)
 M lib/features/wallet/widgets/recharge_request_sheet.dart  (pre-existing, unrelated)
 D supabase/migrations/20261022000002_fish_hunt_foundation.sql       (pre-existing)
 D supabase/migrations/20261022000003_fish_hunt_round_engine.sql     (pre-existing)
 D supabase/migrations/20261023000000_srood_roulette_foundation.sql  (pre-existing)
 D supabase/migrations/20261023000001_srood_roulette_round_engine.sql(pre-existing)
 M supabase/migrations/20261030000000_gamification_read_contract.sql (pre-existing)
```
Untracked — **APPROVED package artifacts** (to be staged later, in the release branch only):
```
?? supabase/migrations_legacy_archive/          (216 legacy .sql + MANIFEST.json)
?? supabase/migrations_next/                    (baseline + 2 Agency V3 + docs + CI draft + PR desc)
?? supabase/baseline_candidate/                 (stage ONLY: 00000000000000_schema_baseline_v2.sql,
                                                 080_storage_cron.sql, 090_secdef_hardening.sql, README.md)
?? supabase/verification/                       (agency test SQL harness)
```
Untracked — **NOT part of the release package** (do NOT stage with the package):
```
?? docs/                                        (incl. THIS checkpoint; unrelated)
?? backup_gift_videos_20260703/                 (unrelated)
?? retired_migrations_removed_games/            (unrelated)
?? srood-current.png                            (unrelated)
?? lib/features/profile/widgets/mini_profile_skeleton.dart (unrelated)
?? supabase/security_audit/                     (unrelated to this package's approved scope)
?? supabase/migrations/2026071*_*.sql (9 loose files)  (untracked; already snapshotted in the archive)
?? test/contracts/…, test/features/…            (unrelated)
```
Ignored (never committable — verified via `git check-ignore`):
```
supabase/baseline_candidate/_public_schema_raw.sql       (raw prod dump)
supabase/baseline_candidate/_full_schema_raw.sql         (raw prod dump)
supabase/baseline_candidate/_full_schema_normalized.sql  (normalized dump)
supabase/baseline_validation_project/   supabase/migrations_next_val/   (temp validation workspaces)
android/app/google-services.json   *.keystore  *.jks  android/key.properties  (secrets)
```

### Notes on `.gitignore` (M)
Added during Phase 2 secret-safety hardening (part of the package): now ignores
`_public_schema_raw.sql`, `supabase/baseline_candidate/_*.sql`, the two temp validation
workspaces, and Firebase/Android signing secrets. This is the only tracked change that
belongs to the package.

---

## 3. Completed Flutter checks (Phase 4)
| Check | Result |
|---|---|
| `flutter clean` | ✅ done |
| `flutter pub get` | ✅ "Got dependencies!" |
| `dart format --output=none --set-exit-if-changed .` | ⚠️ exit 1 — **129 unrelated pre-existing Dart files** need formatting; **0 files in the package scope** (package is SQL/docs only). Not fixed (would violate "preserve unrelated changes"). **Not a package blocker.** |
| `flutter analyze` | ✅ **No issues found** (exit 0) |
| `flutter test` | ✅ **All 62 tests passed** (exit 0) |

## 4. APK build status (Phase 4)
| Build | Result |
|---|---|
| `flutter build apk --debug` | ✅ **Built** `build/app/outputs/flutter-apk/app-debug.apk` (299,748,907 bytes), Gradle `assembleDebug` 1687.3s. Only obsolete-`source 8` javac warnings. |
| `flutter build apk --release --split-per-abi` | ⏳ **NOT RUN — pending** (deferred). Do NOT start another clean build now (per instruction). Run on resume. |

## 5. Completed Supabase checks
- **In the prior workstream turn** (identical, unchanged `migrations_next` files — checksums
  verified equal), the package passed a full real-stack validation:
  two clean `supabase db reset` from zero (both exit 0), `db lint --local` (22 **inherited
  prod** plpgsql_check errors, documented, unchanged), Agency **28/28 PASS / 0 FAIL**,
  concurrency (one winner, `unbalanced=0`), structural parity exact, 0 duplicate objects.
- **In THIS release-workflow turn (Phase 5 formal re-run):** ⏳ **INCOMPLETE.** The stack
  start / `db reset` were flaky **only** because the concurrent Gradle APK build starved the
  machine and the storage container missed the CLI's health-check window. **No migration
  error occurred** — teardown was a container-health timing issue, not a SQL failure.
  Phase 5 must be **re-run cleanly with no APK build competing**.

## 6. Remaining Phase 5 tasks (to re-run on resume, with nothing else competing for CPU)
1. Recreate isolated workspace `supabase/migrations_next_val/` (gitignored) with
   `config.toml` + a copy of `supabase/migrations_next/*.sql` as the ONLY migrations.
2. `supabase start`, then **two** clean `supabase db reset` (both must exit 0).
3. `supabase db lint --local` → error count must be **≤ 22** (inherited baseline; any NEW
   error is a blocker).
4. Agency suite: `agency_phase5_local_bootstrap.sql` + `agency_phase5_executable_tests.sql`
   → **28 PASS / 0 FAIL**; concurrency (one winner, `unbalanced=0`); rollback; ledger
   zero-net (T12); authorization (T11/FI); RLS isolation; immutability (T10a/b/c).
5. `supabase stop`; remove the temp workspace.

## 7. Pending commit / push / PR tasks (Phases 6–11 — none started)
- **Phase 6:** `git switch -c chore/schema-baseline-transition-package` (from the validated branch).
- **Phase 7:** stage **only** approved files (see §Resume commands); review with
  `git diff --cached --name-only` / `--stat` / `--check`.
- **Phase 8:** final staged validation (`git diff --cached --check`, re-run analyze/test).
- **Phase 9:** one commit — "Prepare validated Supabase schema baseline transition".
- **Phase 10:** `git push -u origin chore/schema-baseline-transition-package` (never main, never force).
- **Phase 11:** `gh pr create --draft --base main …` using `supabase/migrations_next/PR_DESCRIPTION.md`.
  Keep as **draft**.

## 8. Exact commands to RESUME safely (run later, after Crash Rocket is done & merged separately)
```bash
cd /c/Users/user/Documents/Dev/srood_live
git switch security/full-production-hardening        # ensure back on the validated base branch

# --- Phase 5 (clean, no APK build running) ---
mkdir -p supabase/migrations_next_val/supabase/migrations
cat > supabase/migrations_next_val/supabase/config.toml <<'TOML'
project_id = "srood_next_val"
[db]
port = 55531
major_version = 17
[api]
port = 55532
[studio]
enabled = false
TOML
cp -p supabase/migrations_next/*.sql supabase/migrations_next_val/supabase/migrations/
cd supabase/migrations_next_val
supabase start && supabase db reset && supabase db reset && supabase db lint --local
db=$(docker ps --format '{{.Names}}' | grep supabase_db_srood_next_val)
docker exec -i "$db" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < ../verification/agency_phase5_local_bootstrap.sql
docker exec -i "$db" psql -U postgres -d postgres < ../verification/agency_phase5_executable_tests.sql   # expect 28 PASS / 0 FAIL
supabase stop
cd ../.. && rm -rf supabase/migrations_next_val

# --- Phase 4 remaining APK (warm build, do NOT flutter clean first) ---
flutter build apk --release --split-per-abi        # do NOT sign with production credentials

# --- Phase 6: dedicated branch ---
git switch -c chore/schema-baseline-transition-package

# --- Phase 7: stage ONLY approved files ---
git add .gitignore
git add supabase/migrations_legacy_archive
git add supabase/migrations_next
git add supabase/baseline_candidate/00000000000000_schema_baseline_v2.sql
git add supabase/baseline_candidate/080_storage_cron.sql
git add supabase/baseline_candidate/090_secdef_hardening.sql
git add supabase/baseline_candidate/README.md
git add supabase/verification
# Verify NOTHING else is staged (esp. no dumps, no lib/*, no google-services.json):
git diff --cached --name-only
git diff --cached --check

# --- Phase 8/9: validate + commit ---
flutter analyze && flutter test
git commit -m "Prepare validated Supabase schema baseline transition"

# --- Phase 10/11: push new branch + draft PR ---
git push -u origin chore/schema-baseline-transition-package
gh pr create --draft --base main --head chore/schema-baseline-transition-package \
  --title "Prepare validated Supabase schema baseline transition" \
  --body-file supabase/migrations_next/PR_DESCRIPTION.md
```

### Hard guardrails when resuming (unchanged)
- Never `git add .` — stage the explicit approved paths only.
- Never stage: `_*.sql` dumps, `android/app/google-services.json`, keystores, `lib/*`
  unrelated changes, `docs/`, `backup_gift_videos_*`, `retired_migrations_removed_games/`,
  the 9 loose untracked `supabase/migrations/2026071*.sql` files, `supabase/security_audit/`,
  or any temp `*_val` workspace.
- Never push to `main`; never force-push. PR stays **draft**.
- Do NOT run `supabase db push` or `supabase migration repair`. Agency feature flag stays OFF.

## 9. Package integrity snapshot (must match on resume)
- `supabase/migrations_legacy_archive/` = **216** `.sql` + `MANIFEST.json` (0 unclassified;
  214 in-baseline / 2 post-cut). Checksums matched originals (0 mismatch).
- `supabase/migrations_next/` = `00000000000000_schema_baseline.sql`,
  `20260711175349_agency_financial_foundation_v3.sql`,
  `20260711181414_agency_finance_v3_rpc_implementation.sql`,
  `BASELINE_MANIFEST.md`, `TRANSITION_DRYRUN_PLAN.md`, `PR_DESCRIPTION.md`,
  `ci_migration_validation.draft.yml`.
- Baseline sha256 `f17eb100…d590da3`; foundation `fd0fbdb7…5fd8951e`; rpc `c7a65ede…88037a58`.

---

## Production safety confirmation
- **No production writes.**
- **No production data changes.**
- **No production migrations.**
- **No migration repair.**
- **No deployment.**
- **No commit. No push. No branch created yet.**
- **No Agency cutover.** (Agency V3 remains schema-only, feature flag OFF.)
- Only read-only production introspection was used (migration history + object existence).
