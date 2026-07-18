# M3 Legacy Backfill — Dry-Run Validation Report

**Status:** M3 validation complete. Not yet approved for M4.
**Scope:** `public.backpack_v2_run_m3_backfill()` (migration `20261121000000_backpack_v2_m3_legacy_backfill.sql`), executed against a disposable, real-shaped local dataset. No production or staging system was read from, connected to, or modified at any point in this validation.

---

## 1. Environment

- Database: local Supabase (`supabase_db_srood_live`, Docker), reset with `supabase db reset` against the full tracked migration chain (through `20261121000000_backpack_v2_m3_legacy_backfill.sql`) immediately before each validation pass.
- Dataset: `supabase/tests/fixtures/m3_disposable_dataset.sql` — synthetic, real-shaped, self-contained, wrapped in `begin ... rollback`. Nothing it inserts is ever committed; every run leaves the database exactly as `db reset` left it.
- No sanitized production snapshot was available locally, so the dataset was constructed to match production's known shapes (per the discovery report and mapping manifest) rather than sampled from real data.

## 2. Dataset description (DS01–DS16)

16 scenarios, namespaced `bc050000-...`/`ds_` to avoid collision with other test/fixture files:

| # | Scenario | Exercises |
|---|---|---|
| DS01 | Native Backpack V2 purchase, already equipped | Non-legacy ownership must never be downgraded by a legacy claim |
| DS02 | User with no Backpack V2 records at all | Backfill must not error on a user absent from every V2 table |
| DS03 | VIP-tier cosmetic via seeded `vip_plans` level 2 (`frame_key` populated) | R9 unresolved-mapping logging |
| DS04 | Duplicate historical grant (same frame via two legacy rows) | `duplicate_superseded` logging, only one ownership row survives |
| DS05 | Expired legacy cosmetic | Expired claims never become equipped |
| DS06 | store_items-sourced grant (simulated; table doesn't exist locally) | R13 blocked-source logging |
| DS07 | Missing/invalid legacy foreign key (orphaned `backpack_items.user_id`) | `missing_user_reference` logging, no ownership row created |
| DS08 | Conflicting equipped cosmetics across R2 vs R4 | Tie-break priority (R2 > R4 > R1), loser logged as `equip_conflict_resolved` |
| DS09 | User with multiple legacy source systems (R1 + R2 + R4 simultaneously) | Full 3-way tie-break |
| DS10 | Legacy source added incrementally between run 1 and run 2 | Idempotency under a genuinely new claim, not just a rerun |
| DS11 | Admin-granted item | `source_type` provenance preserved through migration |
| DS12 | Purchased item | Same |
| DS13 | Free/promotional item | Same |
| DS14 | Revoked legacy grant | Revoked rows never become ownership, `revoked_source` logged |
| DS15 | `badges.required_vip_level` default-vs-CHECK conflict | Confirms the pre-existing schema bug (§7) without letting it block the fixture |
| DS16 | `backpack_items` row with `item_type <> 'avatar_frame'` | R5 unresolved-mapping logging (added after the initial 15 categories under-covered R5) |

Legacy source system coverage: `user_avatar_frames` (R1), `user_frames` (R2), `user_badges` (R3), `backpack_items` (R4/R5), `vip_plans`/`user_vip_subscriptions` (R9), `vip_levels` (R6–R8/R10, seeded data, not per-scenario rows), `store_items` (R13, simulated as absent). R11/R12 need no fixture — R11 is confirmed-empty dead infrastructure and R12 has no legacy source table to construct rows from.

## 3. Commands executed

```
supabase db reset
docker exec -i supabase_db_srood_live psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/fixtures/m3_disposable_dataset.sql
docker exec -i supabase_db_srood_live psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/backpack_v2_m3_migration_contract.sql
docker exec -i supabase_db_srood_live psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/backpack_v2_m3_equip_tiebreak_matrix.sql
docker exec -i supabase_db_srood_live psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/backpack_frame_equip_contract.sql
docker exec -i supabase_db_srood_live psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/backpack_v2_contract.sql
docker exec -i supabase_db_srood_live psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/frame_system_v2_contract.sql
```

Every run: exit code 0, zero `^ERROR` lines, ends in `ROLLBACK` (no persisted state).

SQL formatting/lint: no lint tool is configured in this repository (checked for `sqlfluff`, an npm `sql-lint`/`sqlfluff` dependency, and a `.sqlfluff` config — none exist). Reported as **N/A**, not skipped.

## 4. Migration corrections made during validation

Two real defects were found by executing against real-shaped data and fixed directly in `20261121000000_backpack_v2_m3_legacy_backfill.sql` (not worked around in the test):

1. **Existing non-legacy equip state was not protected from being overwritten by a legacy claim.** The original equip-migration CTE chain computed `winners` from legacy claims (R2 > R4 > R1) and inserted them into `user_equipped_items` unconditionally, including for a user who already had a genuine Backpack V2 equip (e.g. a real purchase or admin grant, `source_type <> 'legacy_migration'`) in that slot. Fixed by adding `blocked_by_existing_v2` (detects a pre-existing non-legacy equip in the target slot) and excluding those users from the `equip_ins` insert, with a new `equip_conflict_resolved` log entry (`existing_v2_equip`) recording that the legacy claim was suppressed. Also added `invalid_top_claim`/`log_invalid_top_claim` to log (rather than silently drop) cases where the highest-priority legacy claim resolves to a catalog item that fails validity checks (missing ownership, expired, inactive, not equip-enabled, wrong slot), with no automatic fallback to a lower-priority claim. Verified by DS01 and DS08/DS09 fixture scenarios.
2. **Silent data loss in the R6–R10/R13 category-level issue log.** The four `deferred_synthesis` rows (R6/R7/R8/R10) were originally inserted with `source_row_id = null`, making all four collide on the same dedupe unique index key `(batch, source_table, coalesce(source_row_id,''), coalesce(source_user_id::text,''), issue_type)` inside one multi-row `INSERT ... VALUES ... ON CONFLICT DO NOTHING` statement — Postgres silently drops later rows that collide with an earlier row *in the same statement*, even on first insert. Only R6 was ever surviving; R7/R8/R10 were being dropped every run. Fixed by giving each row a distinct `source_row_id` equal to its manifest-record label (`R6_vip_tier_entry_effect`, etc.). Verified: `issues_by_type_and_table` for `vip_levels/deferred_synthesis` went from count=1 to the correct count=4 after the fix, confirmed via `supabase db reset` + full rerun with zero regressions in the other two pre-existing M3 test files.

No other migration logic was changed. No legacy table was read from more than `SELECT`, and none was written, altered, or dropped by any of this validation work.

## 5. First-run metrics

```json
{"batch": "m3_legacy_backfill_v1", "catalog_upserted": 43, "equipped_slots_set": 5, "issues_logged_total": 13,
 "r2_frame_v2_ownership_inserted": 4, "r4_backpack_items_ownership_inserted": 3, "r1_legacy_avatar_frames_ownership_inserted": 4}
```

Ownership inserted by source: `backpack_items`=3, `user_avatar_frames`=4, `user_frames`=4 (11 total ownership rows from 3 sources).

Equipped slots resolved (6 users land at a stable slot; 5 required a write since DS01 was already equipped via native V2 purchase and needed no update):

| user | slot | code | source |
|---|---|---|---|
| ds_v2_native_01 owner | avatar_frame | ds_v2_native_01 | purchase (pre-existing, untouched) |
| DS08 owner | avatar_frame | ds_conflict_r2_08 | legacy_migration (R2 won over R4) |
| DS09 owner | avatar_frame | ds_multi_r2_09 | legacy_migration (R2 won over R4 and R1) |
| DS11 owner | avatar_frame | ds_admin_11 | legacy_migration |
| DS12 owner | avatar_frame | ds_purchased_12 | legacy_migration |
| DS13 owner | avatar_frame | ds_promo_13 | legacy_migration |

Issues logged by table/type (10 distinct type combinations, 13 rows total):

| source_table | issue_type | count |
|---|---|---|
| backpack_items | equip_conflict_resolved | 1 |
| backpack_items | missing_user_reference | 1 |
| backpack_items | unresolved_mapping | 1 |
| store_items | blocked_source_unavailable | 1 |
| user_avatar_frames | duplicate_superseded | 1 |
| user_avatar_frames | missing_catalog_mapping | 1 |
| user_badges | unresolved_mapping | 1 |
| user_frames | revoked_source | 1 |
| user_vip_subscriptions | unresolved_mapping | 1 |
| vip_levels | deferred_synthesis | 4 |

## 6. Second-run idempotency evidence

DS10 (incremental legacy claim added between runs) was inserted after run 1 and before run 2, specifically to prove idempotency means "no duplicate work," not "no work."

```json
{"batch": "m3_legacy_backfill_v1", "catalog_upserted": 43, "equipped_slots_set": 1, "issues_logged_total": 13,
 "r2_frame_v2_ownership_inserted": 1, "r4_backpack_items_ownership_inserted": 0, "r1_legacy_avatar_frames_ownership_inserted": 0}
```

- `issues_logged_total` unchanged at 13 across both runs — no duplicate log rows for anything already logged in run 1.
- Only DS10's new claim was processed (`r2_frame_v2_ownership_inserted`=1, `equipped_slots_set`=1); all run-1 ownership/equip rows were left untouched (`r1`/`r4` inserted = 0 on run 2).
- DS10's old (run-1) legacy row survived unmodified; its new (pre-run-2) R2 row correctly won the slot per the R2 > R4 > R1 priority.
- DS01, DS08, DS09, DS14 outcomes reverified stable across both runs.
- Duplicate source-reference uniqueness confirmed: no two `user_backpack_items` rows share the same `source_reference` for the same user.
- Orphan-ownership and orphan-equip-state assertions passed: no `user_backpack_items`/`user_equipped_items` row references a nonexistent user or catalog item.
- Legacy-table-immutability re-verified via before/after row-count and content hash comparison on `user_frames`, `user_avatar_frames`, `backpack_items`, `user_vip_subscriptions`, `user_badges` — identical across both runs.
- Privilege checks: `backpack_v2_run_m3_backfill()` raises `insufficient_privilege` under both `role authenticated` and `role anon` — confirmed not callable by any client-facing role.

## 7. Deferred and blocked sources — quantified impact

Per manifest record, answering: what it represents; why not auto-migrated; affected scope; ownership/equip visibility loss at cutover; whether deterministic mapping is possible; whether synthesis is required; whether a follow-up migration is required; recommended action before M5/M6.

### R3 — badges (`user_badges`)
- **Represents:** existing badge ownership rows, one per user per badge.
- **Why deferred:** `target_backpack_catalog_code` naming for badges is an undecided design question (whether `badges.badge_key` is reused verbatim or needs a rename/prefix) — not discoverable from data, per the mapping manifest.
- **Affected scope:** every row in `user_badges` (production count unknown; not observable locally, 0 rows in local reset). One `unresolved_mapping` log row is emitted per source row.
- **Visible ownership lost at cutover:** No — badges render nowhere in the app today (confirmed by the Phase 1 audit: no current UI renders equipped-badge state from either legacy system), so there is no existing visible behavior to preserve or regress.
- **Equipped cosmetic lost at cutover:** No, for the same reason — nothing currently renders an equipped badge.
- **Deterministic mapping possible:** Yes, mechanically (badge_key → catalog code), but the naming decision must be made by a human first; this is a product decision, not a technical blocker.
- **Synthesis required:** No — this is a direct migration once the naming decision is made, not synthesis.
- **Follow-up migration required:** Yes, once catalog-code naming is decided.
- **Recommended action before M5/M6:** Low urgency. Decide the naming convention, then this becomes a straightforward follow-up migration structurally identical to R1. Does not block M4 since nothing currently renders badges.

### R5 — `backpack_items` rows with `item_type <> 'avatar_frame'`
- **Represents:** unknown. `item_type` is an unconstrained `text` column with no CHECK constraint; its real production value set has never been enumerated.
- **Why deferred:** migrating an unknown value set would mean inventing a mapping, explicitly prohibited by the governing rules.
- **Affected scope:** unknown until production is queried (`select distinct item_type from backpack_items`). Locally, 1 synthetic row (DS16, `item_type='name_color'`) exercises the code path; produces exactly one `unresolved_mapping` log row per affected source row, confirmed via DS16.
- **Visible ownership lost at cutover:** Unknown — depends entirely on whether any current UI renders non-avatar_frame `backpack_items` rows. Not established by this validation; must be checked against production before M5/M6 makes any UI decisions here.
- **Equipped cosmetic lost at cutover:** Same caveat — unknown, needs the production `item_type` enumeration first.
- **Deterministic mapping possible:** Cannot be assessed until the value set is known.
- **Synthesis required:** Cannot be assessed.
- **Follow-up migration required:** Yes, contingent on the production enumeration.
- **Recommended action before M5/M6:** **Blocking for any UI/render work touching `backpack_items`.** Run `select distinct item_type, count(*) from backpack_items group by 1` against production (with explicit approval) before M4/M5 designs anything that could hide or misrepresent these items.

### R6 — VIP-tier entry effect (`vip_levels.entrance_effect_key`)
- **Represents:** a real, populated, tier-level attribute — **not empty**. All 9 seeded VIP tiers have a non-null `entrance_effect_key` (`sparkle` ×2, `glow`, `premium`, `luxury` ×2, `royal` ×2, `legendary`), currently rendered unconditionally by the hardcoded `lib/core/vip/vip_spec.dart`, never as a discrete ownable/equippable item.
- **Why deferred:** no existing per-user ownership row exists anywhere for this category — it would need to be **synthesized** (one grant per active VIP subscriber per tier), and both the target catalog-code naming and the equipped-state semantics (does entering VIP auto-equip? can it be un-equipped while VIP is still active?) are undecided product questions.
- **Affected scope:** every currently-active VIP subscriber (count unknown locally — 0 real subscriptions in a clean reset). This is the **highest-stakes deferred category**, because unlike R7/R8/R10 the source data is real and already rendering to users today.
- **Visible ownership lost at cutover:** No visible regression *if the legacy `VipSpecResolver` rendering path is left active* (which M3 does not touch) — but if a future milestone activates Backpack V2 rendering for entry effects without first synthesizing these rows, active VIP users would lose their entrance effect entirely. This is a real cutover risk for a *future* milestone, not M3 itself.
- **Equipped cosmetic lost at cutover:** Same conditional — only a risk once Backpack V2 becomes the rendering source of truth for entry effects, which M3 explicitly does not do.
- **Deterministic mapping possible:** The tier→attribute mapping is deterministic; the catalog-code naming and equip semantics are not yet decided.
- **Synthesis required:** Yes, explicitly — this is synthesis from tier membership, not migration from an ownership row.
- **Follow-up migration required:** Yes, and it should be scheduled **before** any milestone activates Backpack-V2-sourced entry-effect rendering, specifically because real users would otherwise see a regression.
- **Recommended action before M5/M6:** Decide catalog-code naming and equip semantics for entry effects specifically (can be decided independently of R7/R8/R10, which are empty). Do not activate any entry-effect rendering from Backpack V2 until this synthesis migration exists and has been run.

### R7 — VIP-tier mic effect (`vip_levels.mic_frame_url`)
- **Represents:** a schema column with **no populated value in any observed row** (all 9 seed tiers NULL).
- **Why deferred:** no source value exists locally to migrate or synthesize from.
- **Affected scope:** 0 confirmed locally; production must be checked in case the tracked migration seed differs from real production data (flagged explicitly by the mapping manifest — this was not verified against production).
- **Visible ownership/equipped loss at cutover:** None observable — there is nothing currently rendering a mic effect from this column anywhere in the app.
- **Deterministic mapping / synthesis:** N/A while unpopulated.
- **Follow-up migration required:** Only if production confirms real values exist here that the local seed doesn't.
- **Recommended action before M5/M6:** Low urgency. Confirm via production (with explicit approval) whether `mic_frame_url` is genuinely empty everywhere before treating this as a non-issue permanently.

### R8 — VIP-tier profile frame (`vip_levels.profile_frame_url`)
- Identical situation and recommendation to R7 — unpopulated in every observed row, no current renderer, low urgency pending a production confirmation check.

### R9 — VIP plan frame key (`vip_plans.frame_key`)
- **Represents:** a tier-derived avatar-frame entitlement, populated for 6 of 9 `vip_plans` levels (per the discovery report), pointing into the same `avatar_frames`/`frame_catalog` code space as R1/R2/R4 — but as a *tier grant*, not a direct per-user ownership row.
- **Why deferred:** whether this represents ownership genuinely distinct from any frame the same user separately owns via R1/R2/R4 was never addressed by the discovery report's synthesis section — a real gap, not an oversight in this migration.
- **Affected scope:** every active `user_vip_subscriptions` row whose plan has a non-null `frame_key` (confirmed exercised via DS03 against the real seeded level-2 plan; production count unknown).
- **Visible ownership lost at cutover:** No — this attribute is not currently exposed as an ownable item anywhere; nothing renders differently today.
- **Equipped cosmetic lost at cutover:** No, for the same reason.
- **Deterministic mapping possible:** Mechanically yes (same frame_key resolution path as R1/R4), but whether to create a *separate* grant (risking a confusing duplicate-looking entitlement) or treat it as redundant with any existing frame ownership is an open product decision.
- **Synthesis required:** Yes, if this is decided to be a distinct grant.
- **Follow-up migration required:** Yes, once the ownership-distinctness question is answered.
- **Recommended action before M5/M6:** Medium urgency — decide whether VIP-tier frame entitlement is a distinct ownable grant before building any UI that could double-count or conflict with R1/R2/R4 frame ownership for the same user.

### R10 — VIP-tier badge (`vip_levels.badge_url` / `vip_packages.badge_label`)
- **Represents:** no usable identifier at all — `badge_url` is always NULL, `badge_label` is a free-text display string, not a stable key.
- **Why deferred:** mapping a display string as an identity would be inventing a key that doesn't exist in source data.
- **Affected scope:** 0 — structurally empty at the source, same as R7/R8.
- **Visible ownership/equipped loss at cutover:** None — nothing renders a per-tier badge today.
- **Deterministic mapping / synthesis:** Not possible without a product decision to introduce a new stable key first (this is a product/design task, not a data question).
- **Follow-up migration required:** Only after a stable badge-per-tier key is designed from scratch.
- **Recommended action before M5/M6:** Low urgency, same footing as R7/R8.

### R13 — `store_items`
- **Represents:** unknown. The table has no tracked migration and does not exist in a clean local `supabase db reset` — confirmed directly this session via `information_schema.tables`.
- **Why deferred:** cannot design a migration rule for a table whose shape has never been observed; querying production without approval to resolve this would violate "do not invent mappings" / "do not export production data without approval."
- **Affected scope:** unknown. One category-level `blocked_source_unavailable` log row is emitted (not per-row, since the table can't be queried at all).
- **De-risking finding from this validation:** `backpack_items.item_id` — the column that would reference `store_items` — was confirmed this session to have **no foreign key constraint whatsoever** (only `user_id_fkey → auth.users(id)` exists on that table). This means the absence of `store_items` poses **no orphan-FK or referential-integrity risk** at the database level for any existing table. The risk that remains is purely about *ownership semantics* — whether any real `backpack_items` rows were sourced from `store_items` purchases and what that implies for R4/R5 — not about broken references.
- **Visible ownership lost at cutover:** Cannot be assessed without confirming whether `store_items` exists in production at all.
- **Follow-up migration required:** Contingent on a production check (with explicit approval) of whether the table exists there.
- **Recommended action before M5/M6:** Medium urgency, bundled with the R5 production `item_type` enumeration (same underlying uncertainty about what `backpack_items` actually contains in the wild) — but not blocking, since no FK risk exists.

## 8. User-visible cutover risks (summary)

M3 itself activates nothing — `backpack_v2_run_m3_backfill()` is not granted to any client-facing role and is not called by any migration. The risks below apply to **future** milestones that might read from the rows this function creates, not to M3 as validated:

1. **Highest risk — R6 (VIP entry effects):** real, populated, currently-rendering data with no migrated equivalent yet. Activating Backpack-V2-sourced entry-effect rendering before a follow-up synthesis migration exists would visibly regress every active VIP subscriber.
2. **Medium risk — R9 (VIP frame entitlement) and R13/R5 (`store_items`/non-frame `backpack_items`):** unresolved ownership-semantics questions that could cause double-counted or missing entitlements if a future milestone builds UI on top of R2/R4 ownership without first resolving these.
3. **Low risk — R3 (badges), R7/R8/R10 (empty VIP-tier columns):** no current rendering exists for any of these, so no user-visible regression is possible until a future milestone actively builds new UI for them — at which point the same "is source data structurally empty" facts established here still apply.
4. **No risk identified from R11/R12** — confirmed dead/nonexistent respectively.

## 9. Security and data-integrity findings

- `backpack_v2_run_m3_backfill()` is `SECURITY DEFINER`, `SET search_path = ''`, fully-qualified references throughout, and has **no grant to `authenticated` or `anon`** — confirmed by direct privilege-denial testing under both roles (raises `insufficient_privilege`).
- No legacy table is read from more than `SELECT`, and none is written, altered, or dropped — confirmed via before/after row-count + content-hash comparison across both backfill runs.
- Every ownership and equip insert is idempotent — confirmed via two full runs plus a third incremental scenario (DS10) added between runs.
- **Pre-existing, unrelated schema bug found incidentally:** `badges.required_vip_level` has `DEFAULT 0`, but its own CHECK constraint (`badges_required_vip_level_check`) only permits `NULL OR (required_vip_level BETWEEN 1 AND 9)` — the column's own default violates its own constraint. This is not a Backpack V2 defect and is not touched by this migration; noted here for visibility since it was surfaced while building the DS15 fixture (which works around it by explicitly setting `required_vip_level = null`). Recommend a separate, unrelated ticket to fix the default.
- Two real defects were found in the M3 migration itself (§4) purely by executing it against realistic data, not by static review — validating the governing instruction's premise that a passing test alone does not establish correctness.

## 10. Required migration changes

Both fixes in §4 have already been applied to `20261121000000_backpack_v2_m3_legacy_backfill.sql` and reverified with a full `supabase db reset` + all six test/fixture files (zero regressions). No further migration changes are required for M3 to be internally correct and idempotent.

## 11. Verdict

**APPROVE M3 WITH A DOCUMENTED FOLLOW-UP MILESTONE.**

The migration and backfill function are correct, idempotent, properly privileged, and provably non-destructive to every legacy table, verified against a 16-scenario real-shaped disposable dataset across two runs plus all pre-existing Backpack V2/Frame V2 regression tests. Two real defects were found and fixed during this validation. M3 does not activate anything for real users and introduces no new risk on its own.

However, R6 (VIP entry effects) represents real, currently-visible production data with no migrated path yet, and R5/R9/R13 carry open ownership-semantics questions that must be resolved — via a production data check (with explicit approval) for R5/R13, and a product decision for R6/R9 — **before** any milestone (M4 onward) builds rendering or UI on top of Backpack V2 ownership data. This report recommends that follow-up work be scoped as an explicit M3.1/M4-prerequisite step rather than silently folded into M4, given R6's real-user-regression risk if skipped.

---

## Deliverables summary

1. **Final verdict:** APPROVE M3 WITH A DOCUMENTED FOLLOW-UP MILESTONE (§11).
2. **Files changed:**
   - `supabase/migrations/20261121000000_backpack_v2_m3_legacy_backfill.sql` (corrected — two real defects fixed, §4)
   - `supabase/tests/fixtures/m3_disposable_dataset.sql` (new — 16-scenario disposable dataset + assertions)
   - `docs/backpack_v2/M3_LEGACY_BACKFILL_DRY_RUN_REPORT.md` (this file, new)
3. **Commands run:** listed in §3.
4. **Test results:** `backpack_v2_m3_migration_contract.sql`, `backpack_v2_m3_equip_tiebreak_matrix.sql`, `backpack_frame_equip_contract.sql`, `backpack_v2_contract.sql`, `frame_system_v2_contract.sql`, and the new `m3_disposable_dataset.sql` — all pass cleanly (exit 0, zero `ERROR` lines, end in `ROLLBACK`) against the corrected migration after a clean `supabase db reset`. SQL lint: N/A (no tool configured in this repo).
5. **Migration corrections made:** two, detailed in §4 (existing-V2-equip protection + invalid-top-claim logging; R6–R10 dedupe-collision fix).
6. **First-run metrics:** §5.
7. **Second-run idempotency metrics:** §6.
8. **Deferred and blocked source counts:** §7 (R3, R5, R6–R10, R13 each individually quantified).
9. **User-visible cutover risks:** §8.
10. **Commit hash:** recorded at commit time (see repository history — this report is committed alongside the migration fix and the new fixture in grouped M3-validation commits).
