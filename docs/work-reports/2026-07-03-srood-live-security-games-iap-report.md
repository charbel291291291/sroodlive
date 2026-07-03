# Srood Live — Security, Games, IAP Work Report

**Date:** 2026-07-03
**Project:** Srood Live (Flutter/Dart app), `C:\Users\user\Documents\Dev\srood_live`
**Backend:** Supabase project `srood-live` (ref `xwcldazsjauaeywklukb`)
**Primary working branch:** `feature/crash-rocket-result-timing`

This note is a factual snapshot of work done over the preceding ~24 hours. It
records exact branches, commit hashes, PR numbers, migration numbers, and
production status, grouped by deployment/commit state.

---

## 1. Applied to production

Migrations applied to the `srood-live` production database and recorded in the
migration ledger (`supabase_migrations.schema_migrations`):

| Migration | Name | Purpose |
|---|---|---|
| `20261024000000` | `retire_legacy_crash_direct_rls` | Legacy `crash_rounds`/`crash_bets`: FOR ALL policies → SELECT-only; direct writes revoked |
| `20261025000000` | `rocket_crash_realtime_secrecy` | Drop `rocket_crash_global_bets` from realtime; own-row SELECT; private `rocket_crash_round_secrets` so `crash_multiplier` is NULL until crash; redefined `advance_rocket_crash_rounds()` |
| `20261026000000` | `game_backend_secret_and_write_hardening` | Treasure prize-layout, Fish Hunt `hit_probability`/`server_seed`, Hungry Cat/Loto write-path hardening |
| `20261027000000` | `account_deletion_and_push_tokens` | `account_deletion_requests`, `user_push_tokens`, `request_account_deletion()`, `upsert_push_token()` |
| `20261029000000` | `spin_wheel_rpc` | Server-authoritative Spin Wheel: `spin_wheel_prizes`, `spin_wheel_spins`, `spin_wheel()` RPC |

Post-apply verification (read-only) confirmed:
- Realtime publication exposes only `rocket_crash_global_rounds` among the game
  tables; `rocket_crash_global_bets`, `fish_hunt_fish`, `fish_hunt_rounds`
  removed.
- Zero client (anon/authenticated) read/write grants on secret tables.
- Own-row-only bet SELECT policies.
- Spin Wheel: RPC is SECURITY DEFINER, execute granted only to `authenticated`,
  `spin_wheel_prizes` has no client grants, `spin_wheel_spins` is own-row SELECT
  only, and `wallet_transactions_type_check` includes `spin_wheel_bet` /
  `spin_wheel_reward`.
- Spin Wheel live idempotency test run on a real account **inside a rolled-back
  transaction**: two calls with the same `client_spin_id` → one charge, one
  payout, one ledger row, zero permanent change.

---

## 2. Committed and pushed

On `origin/main` (via merged PR #2 — `security/game-backend-hardening` → `main`):

- `55e1e8f` — Backend game security hardening (migrations `20261024`–`20261026`)
- `6c21d1c` — Account deletion (migration `20261027`) + `DeleteAccountScreen`
- `797e5f5` — Firebase foundation (Crashlytics/Analytics/FCM)
- `a2de188` — Game UI/UX/performance fixes
- `7977f2f` — Merge commit for PR #2

Pushed feature branches (not merged):
- `origin/feature/iap-foundation-ci` — IAP foundation + CI workflow
- `origin/feature/crash-rocket-result-timing` — through commit `826d4d7`
  (`4248484` Crash Rocket fix + `826d4d7` Spin Wheel RPC are pushed)

---

## 3. Local only, not pushed

On `feature/crash-rocket-result-timing`, three commits ahead of
`origin/feature/crash-rocket-result-timing`:

| Commit | Message |
|---|---|
| `9eb1993` | Unify game coin UI components |
| `84e4b66` | Extract shared game sound service |
| `fe2eaf9` | Add dedicated game sound effects (4 Dart files + 11 `.mp3` assets) |

These are complete and gate-green but **not pushed** (holding per instruction).

---

## 4. Open PRs

| PR | Head → Base | State | Notes |
|---|---|---|---|
| PR #1 | `feature/iap-foundation-ci` → `main` | Open, not merged | IAP foundation + CI; IAP migration NOT applied |
| PR #2 | `security/game-backend-hardening` → `main` | Merged | 16 commits; brought hardening + account deletion + Firebase + UI fixes into `main` |
| PR #3 | `feature/crash-rocket-result-timing` → `main` | Open, not merged | Crash Rocket result timing + Leave Game (commit `4248484`) |

---

## 5. Not applied to production

- `20261028000000` `iap_foundation` — committed on `feature/iap-foundation-ci`,
  **not applied to prod**. Deliberately deferred until real Google Play / Apple
  server-side purchase verification exists (the Edge Function is a stub).
- Any migrations authored by parallel work and currently untracked in the tree
  (e.g. `20261030…`, `20261031…`, `20261101…`) — not authored or applied here.

---

## 6. Remaining risks

- **IAP is not production-ready:** the verification Edge Function is a stub; no
  real store verification. Coins must never be credited until it is implemented.
- **Store-policy decision pending:** off-store coin purchases + gambling-style
  games remain a Google Play / Apple compliance risk (see the IAP audit and its
  three options — Play/Apple-compliant, APK/PWA manual, hybrid).
- **Schema drift precedent:** `spin_wheel` had no migration until now; other
  client-referenced RPCs should be spot-checked against version control.
- **Divergent working tree:** many unrelated files are modified/untracked in the
  tree (auth, calls, host, live, rooms, wallet screens; new migrations; new test
  dirs). These are outside the scope of the local commits above and untouched.
- **Manual QA outstanding:** the local UI/sound commits and PR #3 have passed
  analyze/test/apk build but have not had on-device Android QA.

---

## 7. Next recommended actions

1. Push the three local commits (`9eb1993`, `84e4b66`, `fe2eaf9`) once approved.
2. Decide the store/payments direction (drives whether IAP or APK/PWA is primary).
3. Implement real Google/Apple verification before applying the IAP migration.
4. On-device Android QA for Crash Rocket (PR #3) and the coin-UI/sound work.
5. Audit other client-called RPCs for schema drift like `spin_wheel`.
6. Extend server-side fraud controls around wallet mutations (rate limits,
   multi-account/wash detection) given the manual-money economy.

---

## Immediate next steps (checklist)

- [ ] Push local commits `9eb1993`, `84e4b66`, `fe2eaf9` when approved.
- [ ] Keep `android/app/google-services.json` untracked until decided.
- [ ] Do not apply the IAP migration until real Google/Apple verification exists.
- [ ] Manual QA Crash Rocket PR #3 on Android before merge.
- [ ] Manual QA coin UI and sounds on Android before merge.
- [ ] Keep Codex-owned `test/*` changes untouched.
