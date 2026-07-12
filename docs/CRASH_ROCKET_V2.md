# Crash Rocket v2

A full rebuild of the Crash Rocket game — native Flutter client, authoritative
server round engine, provably-fair results, atomic wallet/ledger integration,
secure RPCs, an admin module, and automated tests. Ships **behind a disabled,
server-controlled feature flag** (`game_settings.crash_rocket_v2.is_enabled =
false`).

> Coins are **virtual, non-cashable**, for entertainment only, and subject to
> app compliance rules. Nothing in this game is exchangeable for money.

## Why a rebuild
Three overlapping generations had accumulated (`crash_*`, `rocket_crash_*`,
`crash_rocket_*`) with forced-multiplier admin tooling, a room-scoped variant,
and duplicated RPCs. v2 replaces all of them with a single, self-contained
`crash_v2_*` surface and retires the rest (see the retirement migration).

## Round lifecycle
```
waiting → betting_open → betting_locked → flying → crashed → settling → completed → (next) waiting
```
Every transition is **timestamp-driven and idempotent**; a delayed tick
fast-forwards deterministically. Exactly one engine advances a scope at a time
via a per-scope advisory transaction lock (`crash_v2:<room|global>`).

`crash_v2_rounds` stores: `id`, `public_round_number`, `status`,
`betting_open_at`, `betting_close_at`, `started_at`, `crashed_at`,
`completed_at`, `crash_multiplier`, `server_seed_hash`, `server_seed`
(revealed only on completion), `client_seed`, `nonce`, `created_at`.

## Provably fair
1. On round creation the server generates a 32-byte `server_seed`, stores it in
   the **definer-only** `crash_v2_round_secrets`, and publishes
   `server_seed_hash = sha256(server_seed)` on the round before betting opens.
2. The crash target is derived deterministically:
   `H = sha256(server_seed || ':' || client_seed || ':' || nonce)`;
   take the first 52 bits → `u ∈ [0,1)`;
   `target = floor((house_edge_factor / (1 - u)) * 100) / 100`, clamped to
   `[1.00, max_multiplier]` (defaults: edge `0.97`, max `1000`).
3. On completion the server writes `server_seed` onto the round.
   `crash_v2_verify_round(round_number)` returns the seed, the hash check, and a
   recomputed multiplier so anyone can verify the result.

The flight curve is `m(t) = floor(exp(growth_rate · t) · 100) / 100` (growth
`0.09`), matching the retired game's mechanics. **The server clock decides
everything** — a cashout at/after the derived crash instant is refused even if
the status row hasn't advanced yet.

## Tables (all `crash_v2_*`, RLS fail-closed)
| Table | Read access | Notes |
|---|---|---|
| `crash_v2_rounds` | authenticated (public state) | realtime-published, `replica identity full` |
| `crash_v2_round_events` | authenticated (activity feed) | realtime-published |
| `crash_v2_bets` | **own rows only** | no client writes |
| `crash_v2_round_secrets` | **none** (definer-only) | seed + target; never published |
| `crash_v2_config` | **none** (RPC only) | limits, timing, pause, fairness constants |
| `crash_v2_admin_actions` | **none** (RPC only) | append-only audit (trigger-enforced) |

No API role has INSERT/UPDATE/DELETE on any table. All mutation is via
SECURITY DEFINER RPCs with fixed `search_path`, explicit `authenticated`
grants, and `revoke ... from public, anon`.

## RPCs
Player: `crash_v2_get_state`, `crash_v2_place_bet`, `crash_v2_cancel_bet`,
`crash_v2_cash_out`, `crash_v2_set_auto_cashout`, `crash_v2_get_my_round_bets`,
`crash_v2_get_recent_rounds`, `crash_v2_verify_round`.
Admin (super_admin): `crash_v2_admin_get_config`, `crash_v2_admin_update_config`,
`crash_v2_admin_pause_game`, `crash_v2_admin_resume_game`,
`crash_v2_admin_get_overview`, `crash_v2_admin_get_audit_log`.
Engine (service_role/cron only): `crash_v2_tick`, `crash_v2_tick_all`.

Guarantees per RPC: `auth.uid()` validation, row locking (`for update`,
consistent round→bet lock order), atomic balance updates, immutable
`wallet_transactions` ledger rows, idempotency keys (bet + cashout), duplicate
cashout protection, insufficient-balance rollback, bet-window enforcement,
multiplier/amount/slot validation, and audit logging for admin actions.

**Admins cannot set or preview the crash multiplier.** No forced-multiplier
capability exists anywhere in v2 (the old `owner_set_rocket_crash_forced_multiplier`
and `game_settings.forced_crash_multiplier` path are retired and unused).

## Server engine
`crash_v2_tick(room)` advances one scope; `crash_v2_tick_all()` (cron every 3s,
`service_role` only) ticks global + active rooms. The engine also runs
defensively inside `crash_v2_get_state` / `crash_v2_place_bet`, so gameplay stays
correct even if cron lags. Recovery: a single tick fast-forwards a stale round
through all due transitions (restart, delayed cron, partial settlement); the
advisory lock prevents double execution; residual settlement is idempotent.

## Wallet & ledger flow
- Bet: debit `amount` (`crash_rocket_bet`), row-locked wallet, insufficient →
  full rollback.
- Cancel (betting only): refund `amount` (`crash_rocket_refund`).
- Cashout / auto-cashout: credit `floor(amount × multiplier)` capped at
  `max_payout` (`crash_rocket_cashout`). Auto-cashout is settled server-side at
  the exact threshold crossing time.
- Every movement writes an immutable `wallet_transactions` row tagged
  `metadata.v = 2` with `round_id` + `bet_id`.

## Realtime
Client subscribes to `crash_v2_rounds` (round row) and `crash_v2_round_events`
(activity) for its scope. Payloads are **hints**: on any signal (and on
reconnect / app resume) the client calls `crash_v2_get_state`, which returns
`server_now` for clock-drift correction and rebuilds the exact state. Private
bets, wallet, seeds-before-completion, and config are never broadcast.

## Flutter
`lib/features/games/crash_v2/`: `crash_v2_models.dart`, `crash_v2_service.dart`
(RPC + realtime), `crash_v2_sound_service.dart`, `crash_v2_widgets.dart`
(original procedural rocket/starfield painters — no copied assets),
`crash_v2_screen.dart` (two bet panels, live multiplier, history bar, activity
list, countdown, sound/history/help controls). Handles states: loading,
reconnecting, betting open/locked, flying, crashed, cashout success,
insufficient balance, bet rejected, paused, maintenance/disabled, network loss.
Purple / electric-blue / cyan-glow Srood Live styling; responsive from 320px.

The client never advances rounds and never writes game/wallet tables; the
in-flight multiplier is a cosmetic projection of the server curve using the
server-clock offset.

## Feature flag & cutover
Ships disabled. Enable via `crash_v2_admin_update_config({"is_enabled": true})`
(super_admin) after production validation. The retirement migration
(`20261107000000`) revokes all legacy crash RPCs, refunds open legacy bets, and
marks legacy tables deprecated (kept for history; dropped later, separately).

## Migrations (forward-only)
- `20261107000000_retire_legacy_crash_games.sql`
- `20261107000001_crash_v2_foundation.sql`
- `20261107000002_crash_v2_engine_and_rpcs.sql`

## Tests
- `supabase/verification/crash_v2_executable_tests.sql` (+ bootstrap): balance,
  idempotency, slot lock, betting-after-lock, double cashout, cashout-after-crash,
  auto-cashout, settlement retry, restart recovery, cancel/refund, pause, admin
  gating + audit, RLS isolation, PUBLIC/anon denial, legacy-RPC retirement,
  wallet zero-net, ledger consistency, provably-fair verification.
- `test/features/games/crash_v2_test.dart`: models (all states, feed merge,
  seed reveal), widgets (history chip, stepper, rocket scene, no-overflow at
  320px).
