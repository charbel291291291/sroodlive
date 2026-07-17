-- ============================================================================
-- BACKPACK SYSTEM V2 — canonical catalog, ownership, equipped-slot, audit.
--
-- STRICTLY ADDITIVE. Nothing existing is touched:
--   * legacy public.backpack_items / public.store_items (gamification store),
--     public.frame_catalog / public.user_frames (frames_v2),
--     public.avatar_frames / public.user_avatar_frames (legacy frames),
--     public.badges / public.user_badges, public.vip_levels, and every RPC
--     that reads/writes them keep working unchanged.
--   * These are brand-new tables with names that do not collide with any
--     existing table (the legacy `backpack_items` is an OWNERSHIP table,
--     not a catalog — this migration's catalog is named
--     `backpack_catalog_items` specifically to avoid that collision).
--   * Nothing renders through these tables yet; they are populated by a
--     later migration and consumed by RPCs added in a follow-up migration.
--     No existing screen, flag, or RPC is modified here.
-- Rollback: drop the objects listed at the bottom — no legacy object is
-- touched, so rollback is a pure `drop table`/`drop function` with no
-- data-loss risk to any existing system.
-- ============================================================================

-- ── 1. Catalog ──────────────────────────────────────────────────────────────

create table if not exists public.backpack_catalog_items (
  id uuid primary key default gen_random_uuid(),
  code text unique not null check (code ~ '^[a-z0-9_]+$'),
  name text not null,
  name_ar text,
  name_fr text,
  description text,
  description_ar text,
  description_fr text,
  item_type text not null check (item_type in (
    'avatar_frame', 'profile_frame', 'entry_effect', 'badge', 'name_color',
    'room_background', 'chat_effect', 'mic_effect', 'vehicle'
  )),
  rarity text not null default 'common'
    check (rarity in ('common', 'rare', 'epic', 'legendary', 'mythic')),
  asset_key text,
  preview_asset_key text,
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  is_equippable boolean not null default true,
  is_consumable boolean not null default false,
  is_stackable boolean not null default false,
  default_duration_days int check (default_duration_days is null or default_duration_days > 0),
  vip_level_required int check (vip_level_required is null or vip_level_required between 1 and 9),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists backpack_catalog_items_active_sort_idx
  on public.backpack_catalog_items (is_active, sort_order);
create index if not exists backpack_catalog_items_type_active_idx
  on public.backpack_catalog_items (item_type, is_active);

alter table public.backpack_catalog_items enable row level security;

drop policy if exists "backpack_v2 catalog read active" on public.backpack_catalog_items;
create policy "backpack_v2 catalog read active"
  on public.backpack_catalog_items for select to authenticated
  using (is_active = true or public.has_admin_access());
-- No insert/update/delete policy: catalog writes only via admin RPCs.

create or replace function public.backpack_v2_touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists backpack_catalog_items_touch on public.backpack_catalog_items;
create trigger backpack_catalog_items_touch
  before update on public.backpack_catalog_items
  for each row execute function public.backpack_v2_touch_updated_at();

-- ── 2. Ownership ────────────────────────────────────────────────────────────

create table if not exists public.user_backpack_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.backpack_catalog_items(id),
  quantity int not null default 1 check (quantity > 0),
  source_type text not null check (source_type in (
    'purchase', 'admin_grant', 'event_reward', 'vip_reward', 'legacy_migration'
  )),
  source_reference text,
  acquired_at timestamptz not null default now(),
  expires_at timestamptz,
  is_revoked boolean not null default false,
  revoked_at timestamptz,
  revoked_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((is_revoked = false and revoked_at is null) or (is_revoked = true and revoked_at is not null))
);

-- One ACTIVE ownership row per (user, item); revoked rows stay as history so
-- a re-grant after revoke inserts a fresh row rather than colliding. Repeat
-- grants of an already-active row are handled by the granting RPC (extend
-- expiry for non-stackable items, increment quantity for stackable ones) —
-- never by a second insert, which this index would reject anyway.
create unique index if not exists user_backpack_items_active_unique
  on public.user_backpack_items (user_id, item_id) where is_revoked = false;
create index if not exists user_backpack_items_user_idx
  on public.user_backpack_items (user_id) where is_revoked = false;
create index if not exists user_backpack_items_expiry_idx
  on public.user_backpack_items (expires_at) where is_revoked = false and expires_at is not null;

alter table public.user_backpack_items enable row level security;

drop policy if exists "backpack_v2 ownership read own" on public.user_backpack_items;
create policy "backpack_v2 ownership read own"
  on public.user_backpack_items for select to authenticated
  using (user_id = auth.uid() or public.has_admin_access());
-- No insert/update/delete policies: writes go through SECURITY DEFINER RPCs.

drop trigger if exists user_backpack_items_touch on public.user_backpack_items;
create trigger user_backpack_items_touch
  before update on public.user_backpack_items
  for each row execute function public.backpack_v2_touch_updated_at();

-- ── 3. Equipped slots ───────────────────────────────────────────────────────

create table if not exists public.user_equipped_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  slot_type text not null check (slot_type in (
    'avatar_frame', 'profile_frame', 'entry_effect', 'badge', 'name_color',
    'room_background', 'chat_effect', 'mic_effect', 'vehicle'
  )),
  user_backpack_item_id uuid not null references public.user_backpack_items(id) on delete cascade,
  equipped_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, slot_type)
);

create index if not exists user_equipped_items_backpack_item_idx
  on public.user_equipped_items (user_backpack_item_id);

alter table public.user_equipped_items enable row level security;

-- Equipped state is deliberately world-readable to every authenticated user
-- (not owner-only, unlike ownership above): cosmetics exist to be SEEN by
-- other users in rooms/chat/leaderboards, mirroring how
-- profiles.selected_avatar_frame_key is broadly readable today. Ownership
-- details (expiry, source, quantity) stay private in user_backpack_items.
drop policy if exists "backpack_v2 equipped read all" on public.user_equipped_items;
create policy "backpack_v2 equipped read all"
  on public.user_equipped_items for select to authenticated
  using (true);
-- No insert/update/delete policies: writes go through SECURITY DEFINER RPCs.

drop trigger if exists user_equipped_items_touch on public.user_equipped_items;
create trigger user_equipped_items_touch
  before update on public.user_equipped_items
  for each row execute function public.backpack_v2_touch_updated_at();

-- ── 4. Admin audit log ──────────────────────────────────────────────────────

create table if not exists public.backpack_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  target_user_id uuid,
  action text not null check (action in (
    'create_item', 'update_item', 'activate_item', 'deactivate_item',
    'grant', 'grant_temporary', 'extend_expiry', 'revoke', 'restore',
    'equip', 'unequip', 'consume', 'cleanup_expired'
  )),
  item_id uuid,
  ownership_id uuid,
  before_state jsonb,
  after_state jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists backpack_audit_log_target_idx
  on public.backpack_audit_log (target_user_id, created_at desc);
create index if not exists backpack_audit_log_actor_idx
  on public.backpack_audit_log (actor_user_id, created_at desc);
create index if not exists backpack_audit_log_item_idx
  on public.backpack_audit_log (item_id, created_at desc);

alter table public.backpack_audit_log enable row level security;

drop policy if exists "backpack_v2 audit read own or admin" on public.backpack_audit_log;
create policy "backpack_v2 audit read own or admin"
  on public.backpack_audit_log for select to authenticated
  using (actor_user_id = auth.uid() or target_user_id = auth.uid() or public.has_admin_access());
-- No insert/update/delete policies: writes go through SECURITY DEFINER RPCs.

-- ── 5. Grants ────────────────────────────────────────────────────────────────

grant select on public.backpack_catalog_items to authenticated;
grant select on public.user_backpack_items to authenticated;
grant select on public.user_equipped_items to authenticated;
grant select on public.backpack_audit_log to authenticated;

-- ── Rollback inventory (manual, requires explicit approval) ────────────────
-- drop trigger backpack_catalog_items_touch on public.backpack_catalog_items;
-- drop trigger user_backpack_items_touch on public.user_backpack_items;
-- drop trigger user_equipped_items_touch on public.user_equipped_items;
-- drop function public.backpack_v2_touch_updated_at();
-- drop table public.backpack_audit_log, public.user_equipped_items,
--   public.user_backpack_items, public.backpack_catalog_items;
-- No legacy table is modified by this migration, so no legacy rollback is
-- required.
