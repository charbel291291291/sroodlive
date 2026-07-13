-- =============================================================================
-- Charm Level System (additive)
--
-- Mirror of the Wealth Level System, but driven by gifts RECEIVED:
--   "When you receive 10 gold coins of gifts, you gain 1 charm XP."
--   charm_xp += floor(gift total_cost_coins / 10)  for the RECEIVER.
--
-- Tiers / colours / thresholds are copied from wealth_level_rules so the 10
-- visual tiers match (Bronze..Legend). Charm is fully separate from VIP, Wealth,
-- and the activity user_levels system.
--
-- Safety: additive only. No destructive changes. Charm XP is credited by an
-- AFTER INSERT trigger on gift_transactions (the money RPC is NOT modified), and
-- the trigger swallows errors so it can never break gifting. No wallet / VIP /
-- recharge / moderation logic is touched.
-- =============================================================================

-- ── 1. Tables ─────────────────────────────────────────────────────────────────
create table if not exists public.charm_level_rules (
  level        integer primary key check (level between 1 and 100),
  tier_number  integer not null check (tier_number between 1 and 10),
  tier_name    text    not null,
  required_xp  bigint  not null default 0,
  badge_key    text    not null,
  color_hex    text    not null,
  is_active    boolean not null default true
);

create table if not exists public.user_charm (
  user_id      uuid        primary key references auth.users(id) on delete cascade,
  charm_xp     bigint      not null default 0,
  charm_level  integer     not null default 1,
  tier_number  integer     not null default 1,
  last_xp_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.charm_level_rules enable row level security;
alter table public.user_charm        enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='charm_level_rules' and policyname='charm_rules_public_read') then
    create policy charm_rules_public_read on public.charm_level_rules for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='user_charm' and policyname='user_charm_own_read') then
    create policy user_charm_own_read on public.user_charm for select using (auth.uid() = user_id);
  end if;
end $$;

-- ── 2. Seed charm_level_rules from the existing wealth tiers ──────────────────
-- Reuses the approved 10-tier colour/threshold scheme so charm and wealth share
-- the same premium tier look (Bronze..Legend).
insert into public.charm_level_rules (level, tier_number, tier_name, required_xp, badge_key, color_hex, is_active)
select level, tier_number, tier_name, required_xp,
       replace(badge_key, 'wealth_', 'charm_'), color_hex, is_active
from public.wealth_level_rules
on conflict (level) do update set
  tier_number = excluded.tier_number,
  tier_name   = excluded.tier_name,
  required_xp = excluded.required_xp,
  badge_key   = excluded.badge_key,
  color_hex   = excluded.color_hex,
  is_active   = excluded.is_active;

-- ── 3. add_charm_xp(uuid, bigint) ────────────────────────────────────────────
-- Atomic XP add + level recompute. Never raises (callers swallow anyway).
create or replace function public.add_charm_xp(p_user_id uuid, p_xp bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_xp    bigint;
  v_new_level integer;
  v_new_tier  integer;
begin
  if p_user_id is null or coalesce(p_xp, 0) <= 0 then return; end if;

  insert into public.user_charm (user_id) values (p_user_id)
  on conflict (user_id) do nothing;

  update public.user_charm
  set charm_xp   = charm_xp + p_xp,
      last_xp_at = now(),
      updated_at = now()
  where user_id = p_user_id
  returning charm_xp into v_new_xp;

  select level, tier_number
  into   v_new_level, v_new_tier
  from   public.charm_level_rules
  where  required_xp <= v_new_xp and is_active = true
  order  by required_xp desc
  limit  1;

  update public.user_charm
  set charm_level = coalesce(v_new_level, 1),
      tier_number = coalesce(v_new_tier, 1),
      updated_at  = now()
  where user_id = p_user_id;
end;
$$;

-- ── 4. get_my_charm_level() ──────────────────────────────────────────────────
create or replace function public.get_my_charm_level()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_row        public.user_charm;
  v_curr_rule  public.charm_level_rules;
  v_next_rule  public.charm_level_rules;
  v_band_start bigint;
  v_band_size  bigint;
  v_progress   numeric;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  insert into public.user_charm (user_id) values (v_user_id)
  on conflict (user_id) do nothing;

  select * into v_row from public.user_charm where user_id = v_user_id;
  select * into v_curr_rule from public.charm_level_rules where level = v_row.charm_level;
  select * into v_next_rule from public.charm_level_rules where level = v_row.charm_level + 1;

  if v_next_rule.level is not null then
    v_band_start := v_curr_rule.required_xp;
    v_band_size  := v_next_rule.required_xp - v_band_start;
    v_progress   := case when v_band_size > 0
                         then greatest(0.0, least(1.0, (v_row.charm_xp - v_band_start)::numeric / v_band_size))
                         else 1.0 end;
  else
    v_progress := 1.0;
  end if;

  return json_build_object(
    'charm_level',            v_row.charm_level,
    'charm_xp',               v_row.charm_xp,
    'tier_number',            v_row.tier_number,
    'tier_name',              v_curr_rule.tier_name,
    'color_hex',              v_curr_rule.color_hex,
    'badge_key',              v_curr_rule.badge_key,
    'next_level',             v_next_rule.level,
    'next_level_required_xp', v_next_rule.required_xp,
    'xp_to_next_level',       case when v_next_rule.level is not null
                                   then greatest(0, v_next_rule.required_xp - v_row.charm_xp)
                                   else null end,
    'level_progress',         v_progress,
    'last_xp_at',             to_char(v_row.last_xp_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
end;
$$;

grant execute on function public.get_my_charm_level() to authenticated;

-- ── 5. get_user_charm_level(uuid) — display for any user ─────────────────────
create or replace function public.get_user_charm_level(p_user_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row  public.user_charm;
  v_rule public.charm_level_rules;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  select * into v_row from public.user_charm where user_id = p_user_id;
  if not found then
    return json_build_object('charm_level',1,'tier_number',1,'tier_name','Bronze',
                             'color_hex','#8B5E3C','badge_key','charm_bronze');
  end if;

  select * into v_rule from public.charm_level_rules where level = v_row.charm_level;
  return json_build_object(
    'charm_level', v_row.charm_level,
    'tier_number', v_row.tier_number,
    'tier_name',   v_rule.tier_name,
    'color_hex',   v_rule.color_hex,
    'badge_key',   v_rule.badge_key
  );
end;
$$;

grant execute on function public.get_user_charm_level(uuid) to authenticated;

-- ── 6. Trigger: credit charm XP to the gift RECEIVER ─────────────────────────
-- Decoupled from send_gift_with_wallet (money RPC untouched). 10 coins = 1 XP.
create or replace function public.tg_charm_xp_on_gift()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.receiver_id is not null and coalesce(new.total_cost_coins, 0) >= 10 then
    begin
      perform public.add_charm_xp(new.receiver_id, (new.total_cost_coins / 10)::bigint);
    exception when others then
      null; -- never break gifting
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_charm_xp_on_gift on public.gift_transactions;
create trigger trg_charm_xp_on_gift
  after insert on public.gift_transactions
  for each row execute function public.tg_charm_xp_on_gift();

-- =============================================================================
-- End of 20260909000000_charm_level_system.sql
-- =============================================================================
