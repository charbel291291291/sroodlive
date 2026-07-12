# Schema-Squash Baseline — Candidate & Transition Plan

Preparation/validation only. **No production writes, no data, no history change.**

## Why a squash (root cause)
The migration history has no baseline; it is a partial ALTER-log over a
manually-built prod schema. Objects are altered before they are created
(`20260611100952` alters `room_schedules`; `20260611130000` creates it), and the
prod apply-order ≠ filename order — so the chain **cannot** be replayed from zero,
and no forward-only edit can fix a failure *inside* an earlier applied migration.
The only clean path is a squash: one exact baseline == current prod schema.

## Production schema inventory (read-only)
| Object | Count | | Object | Count |
|---|---|---|---|---|
| schemas (app) | 6 | | functions (public) | **385** |
| extensions | 7 | | └ SECURITY DEFINER | **372** |
| enum types | 2 | | └ SECDEF w/o fixed search_path | **2** ⚠ |
| tables | 159 | | triggers | 11 |
| columns | 1,758 | | RLS policies | 259 |
| views | 3 | | RLS-enabled tables | 159 |
| foreign keys | 231 | | indexes | 403 |
| storage buckets | 8 | | storage policies | 27 |
| cron jobs | 5 | | publications | 2 |

Extensions: pg_cron, pg_net, pg_stat_statements, pgcrypto, plpgsql, supabase_vault, uuid-ossp.
Enums: `admin_permission`, `admin_task_status`. Cron: cleanup-cron-history,
fish_hunt_auto_advance, reset-room-streaks, reset-room-week-xp, roulette_auto_advance.

## Phase B — how to GENERATE the exact baseline (owner runs; read-only)
Hand-assembling 385 functions / 259 policies / 231 FKs / 403 indexes is unsafe
("do not guess"). Use the canonical exact tool. The prod DB password is required
and is **not** available to the read-only MCP used in this session — the DB owner
runs ONE read-only command:

```bash
# READ-ONLY schema dump (no data, no roles/ownership noise)
supabase db dump --db-url "$PROD_READONLY_URL" --schema public,storage \
  -f supabase/baseline_candidate/_full_schema.sql
#   OR: pg_dump --schema-only --no-owner --no-privileges=false \
#       --schema=public --schema=storage "$PROD_READONLY_URL" > _full_schema.sql
```
Then split `_full_schema.sql` into the ordered files already scaffolded here
(`010`…`080`) by object kind. `000_extensions_and_types.sql` is already exact and
complete (extensions + both enums). `040_views.sql` content is already validated
in `supabase/migrations/20260611033000_baseline_manual_leaderboard_views.sql`.

**Security hardening applied during split (documented deviations, no behaviour loss):**
- Pin `SET search_path = pg_catalog, public` on the **2** SECURITY DEFINER
  functions currently missing it (prod hardening — not a functional change).
- Keep every existing `REVOKE … FROM PUBLIC` / grant verbatim; do not broaden.

## Phase C — validate the candidate on a FRESH isolated DB
```bash
docker run -d --name basetest -e POSTGRES_PASSWORD=postgres \
  public.ecr.aws/supabase/postgres:17.6.1.127
# apply candidate in order
for f in 000 010 020 030 040 050 060 070 080; do
  docker exec -i basetest psql -U postgres -v ON_ERROR_STOP=1 \
    < supabase/baseline_candidate/${f}_*.sql || { echo "FAIL $f"; break; }
done
```
Assertions (must all pass): 159 tables, 3 views, 385 functions, 231 FKs resolve,
403 indexes, 11 triggers, 259 policies, RLS enabled on 159 tables, 0 SECURITY
DEFINER fn without fixed search_path, no duplicate objects. Then run a structured
schema diff **candidate vs prod (read-only)**:
```sql
-- object-count + name diff per catalog (tables, functions w/ signatures,
-- policies, indexes, constraints). Allowed diffs: none expected; any diff is
-- documented or the run is NO-GO.
```

## Phase D — post-baseline migrations
After the baseline validates, apply ONLY post-cut migrations, which are the
corrected Agency V3 set (already validated 28/28 in Phase 5) on top of the
baseline, plus any future work. **Do not replay the legacy chain.** Re-run the
Agency Phase 5 executable suite + concurrency + rollback + ledger-invariant +
authorization tests, then `flutter analyze` / `flutter test` / `git diff --check`.

## Phase E — migration-history transition plan (design only; DO NOT EXECUTE)
- **Baseline cut date:** the current prod HEAD. Recommended tag
  `baseline/2026-XX-XX` at the latest legacy migration already applied in prod
  (the day the dump is taken). All 213 legacy files are ≤ cut date.
- **Directory move (later, on approval):** legacy `supabase/migrations/*` →
  `supabase/migrations_legacy_archive/` (read-only, kept for provenance);
  `supabase/baseline_candidate/*` → new `supabase/migrations/0000000000000_baseline_*`
  (single squashed baseline, timestamp = cut date, sorts first).
- **Mark prod as already-baselined (no re-apply):** on prod, insert the baseline
  version into `supabase_migrations.schema_migrations` via
  `supabase migration repair --status applied <baseline_version>` — a HISTORY-ONLY
  operation, no DDL, run only after sign-off. Legacy versions remain recorded as
  applied; the archive keeps them.
- **Staging / new envs:** start from the single baseline → clean from-zero reset,
  then post-cut migrations only.
- **Rollback:** if the baseline is wrong, `git revert` the directory move; prod is
  untouched (history-only repair is reversible by re-marking versions).
- **Disaster recovery:** baseline == exact prod schema, so a fresh DB + baseline +
  a data restore from PITR/backup reproduces prod. Keep the archive + dump.
- **Git branch strategy:** do the squash on `chore/schema-baseline`; PR with the
  candidate + validation report; protected `main` merge after CI green.
- **CI migration test:** on every PR, `supabase db reset` on a clean container
  (baseline + post-cut migrations) must pass; fail the build on any error.
- **Deployment approval gates:** (1) candidate validated on fresh DB, (2) schema
  diff vs prod = empty/explained, (3) Agency + Flutter green, (4) 2-person review,
  (5) history-repair on prod executed in a maintenance window with a backup taken.

## Files created by this phase (no history modified, nothing committed)
- `supabase/baseline_candidate/000_extensions_and_types.sql` (exact, complete)
- `supabase/baseline_candidate/010…080_*.sql` (ordered scaffold; filled by the dump)
- `supabase/baseline_candidate/README.md` (this file)
Existing migrations are **unchanged**; unrelated working-tree changes preserved.
