# Baseline Cut Manifest — `migrations_next`

Working-tree-only transition package. **No production writes, no history change, nothing committed.**

## Cut definition
| Field | Value |
|---|---|
| Production schema dump source | `supabase/baseline_candidate/_public_schema_raw.sql` (READ-ONLY `--schema public`) |
| Dump generated (local file mtime) | 2026-07-12 (operator-run, read-only) |
| Latest production migration applied (dump marker) | `20261106000000` |
| **Baseline cut version** | **`20261106000000`** (production HEAD at dump time) |
| Production migrations applied (history rows) | 208 |
| Local migration files snapshotted to archive | 216 |
| Agency V3 present in production migration history | **No** (`agency_finance_v3` schema absent; versions `20260711175349` / `20260711181414` not in `schema_migrations`) |

The baseline (`00000000000000_schema_baseline.sql`, sha256 `f17eb100…d590da3`) is the validated
public-only baseline v2 (structural parity with production confirmed on a real
`supabase db reset`).

## `migrations_next/` contents (the future active set)
| Order | File | sha256 (short) | Role |
|---|---|---|---|
| 1 | `00000000000000_schema_baseline.sql` | `f17eb100…d590da3` | Squashed baseline == exact production public schema + private fn + storage policies + config + SECDEF hardening |
| 2 | `20260711175349_agency_financial_foundation_v3.sql` | `fd0fbdb7…5fd8951e` | Post-cut: Agency V3 ledger foundation |
| 3 | `20260711181414_agency_finance_v3_rpc_implementation.sql` | `c7a65ede…88037a58` | Post-cut: Agency V3 RPC surface |

## Included in baseline (NOT re-applied post-cut) — 214 files
- **208** `legacy_prod_applied` — recorded in production `schema_migrations`; their end-state is captured verbatim by the dump.
- **3** `reconstructed_baseline_helper` — `20260602000000` (manual foundation tables), `20260606100000` (badges check drift reconcile), `20260611033000` (leaderboard views). Not in prod history, but the objects **exist in production**, so their effect is already in the baseline.
- **3** `hardening_already_in_prod` — `20260711021359` (admin_audit RLS + `admin_record_audit`), `20260711175345` (RPC search_path/grant hardening), `20260711181410` (`apply_vip_recharge_exp` v3). Read-only introspection confirmed **production already has each effect** (RLS enabled, fixed search_path on all 7 RPCs, v3 body present), so they are already in the baseline and would be redundant re-applications.

## Excluded as post-cut (promoted into `migrations_next`) — 2 files
| Version | File | Proof it is post-cut |
|---|---|---|
| `20260711175349` | agency_financial_foundation_v3 | `agency_finance_v3` schema count = 0 in production; version not in `schema_migrations` |
| `20260711181414` | agency_finance_v3_rpc_implementation | same — RPC surface depends on the absent schema |

**Inclusion rule honored:** a post-cut migration is promoted only when its effect is
absent from the baseline. Every hardening/reconstruction migration was verified
**present** in production and therefore excluded; only the genuinely-absent Agency V3
pair is promoted.

## Reversibility
- Legacy originals remain in `supabase/migrations/` (untouched).
- Full classified snapshot + checksums in `supabase/migrations_legacy_archive/MANIFEST.json`.
- The transition (archive move + promote) is a directory rename, reversible by
  `git revert` / restoring from the archive. Production is never modified by this package.
