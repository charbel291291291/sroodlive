# Backpack V2 — M3 Legacy Inventory Discovery Report

**Read-only.** No legacy table was written to. No backfill SQL was written. This report
exists so the eventual backfill migration is built from verified schema/identifier facts,
not assumptions.

**Method:** every fact below was captured by running read-only queries
(`information_schema.columns`, `pg_constraint`, `pg_class`, and plain `select`s wrapped in
`begin; set transaction read only; ... rollback;`) against a freshly-reset local Supabase
instance (`npx supabase db reset`, full tracked migration history through
`20261120000002_backpack_v2_hardening.sql`). A clean reset has **no real user/ownership
rows** — only the catalog rows that ship as migration seed data. Row counts below reflect
that; a second discovery pass against the production project (via the Supabase MCP,
read-only) is required before backfilling real ownership data, since production may have
rows a clean reset never creates (e.g. anything written by application code against
`store_items`, which isn't even a trackable table today — see Finding 3).

---

## 1. Headline finding: there is no single identifier format

The task's warning — "do not assume legacy frames, VIP records, badges, and equipped
fields share one identifier format" — is confirmed. Five independent identifier schemes
exist across the systems this migration must reconcile:

| System | Identifier column | Format observed | Owned by |
|---|---|---|---|
| Legacy avatar frames | `avatar_frames.frame_key` | free-form snake_case string, e.g. `custom_srood_live`, `luxury_ruby_royal`, `vip_5` | `avatar_frames` table |
| Frame V2 catalog | `frame_catalog.code` | same snake_case string space as `frame_key` for non-VIP frames, but **not guaranteed identical** — resolved via `frame_legacy_map.legacy_key → code`, which contains aliases with no shared string at all (e.g. `ruby_royal → luxury_ruby_royal`) | `frame_catalog` / `frame_legacy_map` |
| Badges | `badges.badge_key` | separate snake_case space (`agency_host`, `vip_gold`, `level_1`) — **zero overlap** with frame identifiers, no legacy-map table of its own | `badges` table |
| VIP tier — richest facts | `vip_levels.level` | plain integer 1–9, cosmetic asset columns present but **never populated** in seed data (`mic_frame_url`, `profile_frame_url` are all `NULL`) | `vip_levels` |
| VIP tier — purchase SKU | `vip_packages.code` | composite string `vip_{level}_{tier-name}`, e.g. `vip_3_diamond`, `vip_9_celestial` — a *different* string per level than anything in `vip_levels` or `frame_catalog` | `vip_packages` |
| VIP tier — subscription plan | `vip_plans.level` + `vip_plans.frame_key` | integer level (matches `vip_levels.level` in range only, not by FK), plus a **nullable** `frame_key` that points back into the `avatar_frames`/`frame_catalog` string space for only 6 of 9 levels (level 1 has none) | `vip_plans` / `user_vip_subscriptions` |
| Legacy "equipped" ownership | `backpack_items.metadata->>'frame_key'` | the **only** field `equip_backpack_item()` actually reads to resolve a frame — `backpack_items.item_id` (uuid) is present but **unused by that RPC and has no foreign key at all** (see Finding 3) | `backpack_items` |

No natural join exists across these six identifier spaces. Any backfill has to go
**string-by-string** through `frame_legacy_map` (frames), a **new hand-built mapping** for
badges (none exists today), and a **new hand-built mapping** from `vip_levels.level` /
`vip_packages.code` / `vip_plans.level` to whichever Backpack V2 catalog rows represent
VIP-tier cosmetics — because right now those tables store *facts about VIP tiers*, not
*ownable items*, so there is nothing to backfill from for entry effects, mic effects, room
backgrounds, name colors, or vehicles: those categories have zero legacy rows of any kind
(confirmed in the original Phase-1 audit, re-confirmed here — no table in this repo stores
per-user ownership of an entry effect, mic effect, room background, name color, or
vehicle; VIP tier cosmetics are rendered from the hardcoded `VipSpec`/`VipSpecResolver` in
`lib/core/vip/vip_spec.dart`, not from any of these tables).

## 2. Finding: `backpack_items.item_id` is an unenforced, effectively unused column

```
=== FKs on backpack_items ===
 backpack_items_pkey                | PRIMARY KEY (id)
 backpack_items_user_id_fkey        | FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
 backpack_items_user_id_item_id_key | UNIQUE (user_id, item_id)
```

No `FOREIGN KEY` on `item_id` at all — it can point at nothing. Reading
`equip_backpack_item()`'s body (`20261113000000_backpack_items_baseline_and_frame_guard.sql:78-117`)
confirms the RPC never uses `item_id` to look anything up; it reads
`v_item.metadata->>'frame_key'` instead. So for the one legacy ownership table this
migration must read from, **the real identifier lives inside a jsonb metadata blob, not in
a typed column**, and there is no server-side guarantee that blob's `frame_key` resolves to
anything (a malformed or stale `frame_key` there would silently make the item
unequippable, not error). A backfill script reading `backpack_items` must treat
`metadata->>'frame_key'` as an untrusted string and resolve it through the same
`frame_legacy_map`-aware lookup the entitlement RPC uses, skipping (and reporting, not
silently dropping) any row whose key resolves to nothing.

## 3. Finding: `store_items` does not exist in a clean environment

`gamification_store_items` exists and is fully migrated/RLS'd, but plain `store_items` —
the table the Phase-1 audit flagged `backpack_items` as depending on — **is absent
entirely** from a clean `supabase db reset` (`pg_tables`, `pg_class`, and
`information_schema.tables` all return zero rows for it). This reconfirms the earlier
audit finding rather than contradicting it: whatever created `store_items` in production
(if it exists there) was never captured as a tracked migration. Before any backfill can
join against it, its production shape needs to be pulled via `list_tables`/`execute_sql`
against the live project — it cannot be assumed to match anything in this repo's migration
history, and this repo cannot currently reproduce it locally at all.

## 4. Finding: three inconsistent "equipped" representations, one new one

| Table | Equipped representation |
|---|---|
| `user_avatar_frames` | `is_equipped boolean` — one row per owned frame, multiple could theoretically be `true` at once (no partial unique index enforcing "one equipped per user") |
| `user_badges` | `is_equipped boolean` — same shape/gap as above, and (per Finding 5) unrendered anywhere regardless |
| `backpack_items` | `equipped boolean` — different column name, same shape; the *only* one of the three actually enforced to be exclusive, and only per `item_type` (`equip_backpack_item()` does `update backpack_items set equipped=false where user_id=... and item_type=...` before setting the new one) |
| `user_frames` (Frame V2) | **no equipped flag on the ownership row at all** — equipped state lives separately on `profiles.selected_avatar_frame_key`, decoupled from ownership |
| `user_equipped_items` (Backpack V2, this migration) | `PRIMARY KEY (user_id, slot_type)` — a genuinely exclusive one-row-per-slot model, the strongest of the five |

A backfill has to translate three different "what's currently equipped" queries (a
`WHERE is_equipped = true` scan, a `WHERE equipped = true AND item_type = ...` scan, and a
`profiles.selected_avatar_frame_key` string match) into a single upsert into
`user_equipped_items`, and must decide a tie-break rule up front for any user who somehow
has more than one `is_equipped = true` row in a table that doesn't enforce exclusivity
(observed as *possible* by schema, not observed to actually occur — local reset has zero
ownership rows to check against; production must be queried before assuming it doesn't
happen).

## 5. Finding: equipped badges render nowhere, confirmed again at the schema level

`profiles` has no `selected_badge_key`/`equipped_badge_id`/equivalent column
(`information_schema.columns` search for `%badge%` on `profiles` returns only
`badge_count`/`badges_count`, both counters, not selections). This matches the Phase-1
audit's UI finding — there is genuinely no server-side concept of "the user's current
badge" today, on either badge system. Backfilling `user_badges.is_equipped = true` rows
into `user_equipped_items(slot_type = 'badge')` is well-defined data-wise, but there is no
legacy screen this could regress, since nothing reads the legacy equipped-badge state
either.

## 6. Full column inventory (as of this reset)

<details>
<summary>avatar_frames (legacy ownership catalog)</summary>

```
id uuid · frame_key text · name text · category text · vip_level int (nullable)
asset_url text (nullable) · is_active boolean · sort_order int · created_at timestamptz
required_vip_level int (nullable) · is_featured boolean · price_coins bigint · updated_at timestamptz
```
29 seed rows. Sample keys: `custom_admin`, `custom_luxury_diamond`, `custom_srood_live`,
`normal_silver_ring`, `vip_1`..`vip_9` (VIP-tier rows use `frame_key = 'vip_N'` directly).
</details>

<details>
<summary>user_avatar_frames (legacy ownership)</summary>

```
id uuid · user_id uuid → auth.users · frame_id uuid → avatar_frames(id) · frame_key text (denormalized copy)
is_equipped boolean · source text · purchased_at timestamptz · expires_at timestamptz (nullable)
```
0 rows in a clean reset.
</details>

<details>
<summary>frame_catalog (Frame V2 catalog — the most mature system, template for Backpack V2)</summary>

```
id uuid · code text (unique) · name text · localized_names jsonb · category text · vip_level int (nullable)
rarity text · asset_type text · asset_url/thumbnail_url/animation_url text (nullable) · is_animated boolean
is_active boolean · sort_order int · unlock_type text · unlock_value text (nullable)
required_role/required_level/required_vip_level (nullable) · starts_at/expires_at timestamptz (nullable)
legacy_frame_key text (nullable) · created_at/updated_at timestamptz
```
29 seed rows, 1:1 with `avatar_frames` by row count. `legacy_frame_key` is populated for
every non-VIP row and `NULL` for the 9 `vip_N` rows (those rely on `code = frame_key`
being identical by construction, not via the legacy-key column).
</details>

<details>
<summary>frame_legacy_map (alias table — the only cross-identifier map that exists today)</summary>

```
legacy_key text · code text · created_at timestamptz
```
Contains straight passthroughs (`custom_admin → custom_admin`) **and** true aliases
(`ruby_royal → luxury_ruby_royal`, `ruby_royal_dark → luxury_ruby_royal_dark`). Any
backfill resolving a legacy frame key must go through this table, never assume
`frame_key == code`.
</details>

<details>
<summary>user_frames (Frame V2 ownership — no equipped flag, see Finding 4)</summary>

```
id uuid · user_id uuid → auth.users · frame_id uuid → frame_catalog(id) · source text
granted_by uuid (nullable) · granted_at timestamptz · expires_at timestamptz (nullable)
revoked_at/revoked_by/revoke_reason (nullable)
```
0 rows in a clean reset.
</details>

<details>
<summary>badges / user_badges (unrendered system, see Finding 5)</summary>

```
badges: id uuid · badge_key text · name text · description text (nullable) · icon text (nullable)
  category text · rarity text · required_level/required_vip_level int (nullable) · price_coins bigint
  is_active boolean · sort_order int · created_at/updated_at timestamptz
user_badges: id uuid · user_id uuid → auth.users · badge_id uuid → badges(id) · badge_key text (denormalized)
  is_equipped boolean · source text (CHECK: level_reward/vip_reward/agency_reward/event_reward/admin_grant/purchase)
  earned_at timestamptz · expires_at timestamptz (nullable) · created_at timestamptz
```
11 seed badge rows, 0 ownership rows. `source` CHECK values are a useful reference for
mapping to Backpack V2's `source_type` CHECK (`purchase/admin_grant/event_reward/vip_reward/legacy_migration`)
— `level_reward` and `agency_reward` have no direct V2 equivalent yet and would need to
collapse into `event_reward` or a new source_type value during backfill design.
</details>

<details>
<summary>vip_levels / vip_packages / vip_plans / user_vip_subscriptions (three competing VIP tables, see §1)</summary>

```
vip_levels: id uuid · level int · name text · price_coins/price_usd (nullable) · duration_days int
  badge_url/profile_frame_url/mic_frame_url text (nullable, unpopulated) · entrance_effect_key text (nullable)
  chat_bubble_style text (nullable) · room_privileges jsonb · priority_rank int · is_active boolean
  created_at/updated_at · required_recharge_exp/monthly_maintain_exp bigint (nullable)
vip_packages: id uuid · vip_level int · code text · name/arabic_name text · price_coins int · duration_days int
  badge_label text (nullable) · entrance_banner_key text (nullable) · is_active boolean · sort_order int
vip_plans: id uuid · name text · level int · price_coins bigint · duration_days int · badge_style text (nullable)
  frame_key text (nullable) · benefits jsonb · is_active boolean · sort_order int
user_vip_subscriptions: id uuid · user_id uuid → auth.users · vip_plan_id uuid → vip_plans(id) [RESTRICT]
  starts_at/ends_at timestamptz · is_active boolean · vip_level int (nullable, denormalized)
  started_at/expires_at timestamptz (nullable, denormalized) · payment_source text (nullable)
  created_by_admin uuid → auth.users (nullable) · auto_renew boolean
```
9 rows each in `vip_levels`/`vip_packages`/`vip_plans` (one per tier), 0 rows in
`user_vip_subscriptions`. `entrance_effect_key` (`vip_levels`) has real seed values
(`sparkle`, `glow`, `premium`, `luxury`, `royal`, `legendary`) — this is the closest thing
to an ownable "entry effect" catalog that exists today, but it is a **tier attribute**, not
a per-user grant; a level-9 user simply always has `entrance_effect_key = 'legendary'`
while their VIP is active. Backfilling this into Backpack V2's `entry_effect` slot means
synthesizing one grant per active-VIP user pointing at a new catalog row keyed by
tier, re-derived from `profiles.vip_level`/`profiles.vip_expires_at` — not from any
existing ownership table, since none exists for this category.
</details>

<details>
<summary>backpack_items / gamification_store_items / gamification_backpack_items (dead/semi-dead infra)</summary>

```
backpack_items: id uuid · user_id uuid → auth.users · item_id uuid (NO FK — see Finding 2) · item_type text
  equipped boolean · acquired_at timestamptz · metadata jsonb (real identifier lives at metadata->>'frame_key')
gamification_store_items: id uuid · name/name_ar text · description/description_ar text · item_type text
  price_coins/price_diamonds bigint · rarity text · image_url/icon text (nullable) · required_vip_level int
  metadata jsonb · is_active boolean · sort_order int · created_at/updated_at
gamification_backpack_items: id uuid · user_id uuid → auth.users · item_id uuid → gamification_store_items(id)
  equipped boolean · acquired_at timestamptz · expires_at timestamptz (nullable) · metadata jsonb
```
0 rows in every one of these three tables. `gamification_backpack_items` is the only one
of the three with its FK properly enforced — but per the original Phase-1 audit, no
mutating RPC anywhere in the tracked migrations writes to `gamification_store_items` or
`gamification_backpack_items`, so this remains confirmed-dead infrastructure with nothing
to migrate.
</details>

## 7. What this means for the backfill migration (not written yet)

1. **Frames**: source from `user_avatar_frames` (legacy, `is_equipped`) union
   `backpack_items where item_type='avatar_frame'` (reading `metadata->>'frame_key'`, not
   `item_id`) union `user_frames` (already-v2, may not even need backfill — it's the
   target shape's closest ancestor). All three must resolve their key through
   `frame_legacy_map` before matching `frame_catalog.code` / the future
   `backpack_catalog_items.code`.
2. **Badges**: source from `user_badges` only. No legacy-map table exists for badge keys —
   one must be reasoned about (are `badges.badge_key` values already going to be reused
   verbatim as `backpack_catalog_items.code`, or do they need a prefix/rename? This is a
   design decision for the backfill migration, not something discoverable from data).
3. **VIP-tier cosmetics** (entry effects, mic effects, badges-by-tier, profile frames):
   synthesized, not migrated — one catalog row per tier per category, one grant per
   currently-active VIP subscriber, derived from `profiles.vip_level` /
   `profiles.vip_expires_at` (the columns actually read by the app today), cross-checked
   against `vip_levels` for the richest attribute set. `vip_packages` and `vip_plans` are
   evidence of intent (pricing/naming) but not sources of ownership truth.
4. **Room backgrounds, name colors, chat effects, vehicles**: nothing to backfill —
   confirmed (again) zero legacy ownership rows or tables of any kind exist for these
   categories. These start empty in Backpack V2 and get their first catalog rows written
   fresh, not migrated.
5. **Before writing any backfill INSERT**: re-run this same discovery query set against
   the production project (Supabase MCP, `execute_sql`/`list_tables`, still read-only) to
   get real row counts and confirm `store_items`'s actual production shape, since a clean
   local reset cannot surface either.

No backfill SQL has been written. No legacy table was modified. This report is the M3
checkpoint the user asked for before that work begins.
