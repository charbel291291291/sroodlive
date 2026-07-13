# Phase 4 VIP RPC Fix

Root cause: `user_vip_subscriptions` was created with canonical `starts_at` and
`ends_at`. The live schema lacks later `started_at`/`expires_at` aliases, while
`apply_vip_recharge_exp` inserts into those missing aliases.

The forward-only correction uses canonical columns, locks and validates the
profile, rejects null/non-positive values, preserves lifetime/monthly EXP and
threshold-crossing renewal behavior, and keeps the helper service-role-only with
`search_path=pg_catalog,public`. It is not deployed. Duplicate extensions remain
guarded by the monthly threshold and the calling approval's pending-state lock.
No safe audit actor/correlation identifier is available in the legacy two-argument
helper; V3 operations provide the auditable path instead of forging an actor.
