-- ============================================================
-- Room XP & Level Progression System
-- ============================================================
-- Adds exponential XP growth across 50 levels with:
--   • Gifts (primary source, uncapped)
--   • Active listeners (capped per day to prevent idle abuse)
--   • Hosting time (tiny baseline reward)
--   • PK battle bonuses
--   • Daily streak multiplier
-- ============================================================

-- ── 1. Columns on rooms ──────────────────────────────────────────────────────

alter table public.rooms
  add column if not exists room_xp            bigint          not null default 0,
  add column if not exists xp_today_gift      int             not null default 0,
  add column if not exists xp_today_passive   int             not null default 0,
  add column if not exists xp_week            bigint          not null default 0,
  add column if not exists daily_streak       smallint        not null default 0,
  add column if not exists streak_multiplier  numeric(4,2)    not null default 1.00,
  add column if not exists last_active_date   date,
  add column if not exists last_xp_at         timestamptz;

-- Update room_level cap to 50 now that we have a real system
alter table public.rooms
  drop constraint if exists rooms_room_level_check;
alter table public.rooms
  add constraint rooms_room_level_check check (room_level >= 1 and room_level <= 50);

-- ── 2. Level threshold table (50 levels) ─────────────────────────────────────

create table if not exists public.room_level_thresholds (
  level        smallint primary key check (level >= 1 and level <= 50),
  xp_required  bigint   not null,
  tier_name    text     not null,
  unlock_name  text     not null
);

-- Truncate so re-running is idempotent
truncate public.room_level_thresholds;

insert into public.room_level_thresholds (level, xp_required, tier_name, unlock_name) values
  -- ── Starter (1–5) ──────────────────────────────────────────────────────────
  (1,           0,          'Starter',    'Violet Glass Mic Pods'),
  (2,        2000,          'Starter',    'Stronger Mic Glow'),
  (3,        6000,          'Starter',    'Silver Glass Border'),
  (4,       15000,          'Starter',    'Animated Seat Border Pulse'),
  (5,       35000,          'Starter',    'Blue Prestige Seat Style'),
  -- ── Rising (6–10) ─────────────────────────────────────────────────────────
  (6,       75000,          'Rising',     'Blue Aura Room Glow'),
  (7,      140000,          'Rising',     'Gold Accent Ring'),
  (8,      240000,          'Rising',     'Purple Crown Room'),
  (9,      380000,          'Rising',     'Advanced PK Mode Access'),
  (10,     600000,          'Rising',     'Gold Room Frame'),
  -- ── Prestige (11–15) ──────────────────────────────────────────────────────
  (11,     800000,          'Prestige',   'Premium Entrance Effect'),
  (12,    1065000,          'Prestige',   'Enhanced Room Badge Glow'),
  (13,    1415000,          'Prestige',   'Extended Welcome Message'),
  (14,    1880000,          'Prestige',   'Ruby Seat Theme'),
  (15,    2500000,          'Prestige',   'Premium Room Background'),
  -- ── Elite (16–20) ─────────────────────────────────────────────────────────
  (16,    3155000,          'Elite',      'Animated Room Intro'),
  (17,    3980000,          'Elite',      'Dual-Color Seat Ring'),
  (18,    5020000,          'Elite',      'Enhanced Gift Effects'),
  (19,    6335000,          'Elite',      'Elite Room Banner'),
  (20,    8000000,          'Elite',      'Royal Mic Seats'),
  -- ── Grand (21–25) ─────────────────────────────────────────────────────────
  (21,    9610000,          'Grand',      'Extended Host Controls'),
  (22,   11540000,          'Grand',      'Custom Intro Music Slot'),
  (23,   13860000,          'Grand',      'Premium Seat Numbering'),
  (24,   16640000,          'Grand',      'Diamond Border Effects'),
  (25,   20000000,          'Grand',      'Room Entrance Animation'),
  -- ── Royal (26–30) ─────────────────────────────────────────────────────────
  (26,   23520000,          'Royal',      'Priority Room Discovery'),
  (27,   27660000,          'Royal',      'Custom Room Badge Shape'),
  (28,   32530000,          'Royal',      'Exclusive Gift Reactions'),
  (29,   38260000,          'Royal',      'Extended PK Battle Time'),
  (30,   45000000,          'Royal',      'Crown Room Badge'),
  -- ── Legend (31–35) ────────────────────────────────────────────────────────
  (31,   51700000,          'Legend',     'Elite Tier Priority Listing'),
  (32,   59400000,          'Legend',     'Sapphire Seat Theme'),
  (33,   68250000,          'Legend',     'Custom Announcement Style'),
  (34,   78420000,          'Legend',     'Golden Room Aura'),
  (35,   90000000,          'Legend',     'Diamond Seat Glow'),
  -- ── Mythic (36–40) ────────────────────────────────────────────────────────
  (36,  102240000,          'Mythic',     'Enhanced Leaderboard Rank'),
  (37,  116140000,          'Mythic',     'Cosmic Seat Pulse'),
  (38,  131935000,          'Mythic',     'Private Room Analytics'),
  (39,  149878000,          'Mythic',     'Platinum Room Frame'),
  (40,  170000000,          'Mythic',     'Palace Room Theme'),
  -- ── Immortal (41–45) ──────────────────────────────────────────────────────
  (41,  190400000,          'Immortal',   'Mythic Room Entrance'),
  (42,  213248000,          'Immortal',   'Galaxy Seat Effects'),
  (43,  238838000,          'Immortal',   'Rainbow Gift Reactions'),
  (44,  267499000,          'Immortal',   'Legendary Room Banner'),
  (45,  300000000,          'Immortal',   'Elite Ranking Priority'),
  -- ── Legend Throne (46–50) ─────────────────────────────────────────────────
  (46,  332100000,          'Throne',     'Eternal Aura'),
  (47,  367734000,          'Throne',     'Shadow Throne Effects'),
  (48,  407082000,          'Throne',     'Eclipse Seat Theme'),
  (49,  450638000,          'Throne',     'Immortal Room Badge'),
  (50,  500000000,          'Throne',     'Legend Throne Room Theme');

-- RLS: anyone authenticated can read thresholds
alter table public.room_level_thresholds enable row level security;
create policy "read_room_level_thresholds"
  on public.room_level_thresholds for select
  to authenticated using (true);

-- ── 3. grant_room_xp RPC ─────────────────────────────────────────────────────
-- Called from server-side triggers/edge functions and admin panel.
-- Sources: 'gift' | 'active' | 'hosting' | 'pk' | 'event'
-- Only 'gift' source is uncapped. All others share a 50,000 XP/day passive cap.

create or replace function public.grant_room_xp(
  p_room_id  uuid,
  p_xp       bigint,
  p_source   text default 'gift'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room          record;
  v_actual_xp     bigint := p_xp;
  v_passive_cap   bigint := 50000;
  v_new_xp        bigint;
  v_new_level     smallint;
  v_leveled_up    boolean := false;
begin
  select room_xp, room_level, xp_today_gift, xp_today_passive,
         xp_week, daily_streak, streak_multiplier, last_active_date
  into v_room
  from public.rooms
  where id = p_room_id
  for update;

  if not found then
    return jsonb_build_object('error', 'room_not_found');
  end if;

  -- Enforce passive daily cap (non-gift sources)
  if p_source <> 'gift' then
    if v_room.xp_today_passive >= v_passive_cap then
      return jsonb_build_object('capped', true, 'room_xp', v_room.room_xp, 'room_level', v_room.room_level);
    end if;
    v_actual_xp := least(p_xp, v_passive_cap - v_room.xp_today_passive);
  end if;

  -- Apply streak multiplier (only to non-gift to prevent abuse inflation)
  if p_source <> 'gift' then
    v_actual_xp := ceil(v_actual_xp::numeric * v_room.streak_multiplier);
  end if;

  v_new_xp := v_room.room_xp + v_actual_xp;

  -- Compute new level from thresholds
  select coalesce(max(level), 1) into v_new_level
  from public.room_level_thresholds
  where xp_required <= v_new_xp;

  v_leveled_up := v_new_level > v_room.room_level;

  update public.rooms set
    room_xp          = v_new_xp,
    room_level       = v_new_level,
    xp_today_gift    = case when p_source = 'gift'  then xp_today_gift  + v_actual_xp else xp_today_gift  end,
    xp_today_passive = case when p_source <> 'gift' then xp_today_passive + v_actual_xp else xp_today_passive end,
    xp_week          = xp_week + v_actual_xp,
    last_xp_at       = now(),
    last_active_date = current_date
  where id = p_room_id;

  return jsonb_build_object(
    'room_xp',    v_new_xp,
    'room_level', v_new_level,
    'leveled_up', v_leveled_up,
    'xp_granted', v_actual_xp
  );
end;
$$;

-- ── 4. get_room_xp_stats RPC ─────────────────────────────────────────────────

create or replace function public.get_room_xp_stats(p_room_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select jsonb_build_object(
    'room_xp',           r.room_xp,
    'room_level',        r.room_level,
    'xp_today',          r.xp_today_gift + r.xp_today_passive,
    'xp_week',           r.xp_week,
    'daily_streak',      r.daily_streak,
    'streak_multiplier', r.streak_multiplier
  )
  from public.rooms r
  where r.id = p_room_id;
$$;

grant execute on function public.grant_room_xp(uuid, bigint, text) to authenticated;
grant execute on function public.get_room_xp_stats(uuid) to authenticated;

-- ── 5. update_room_streak — called daily by pg_cron ──────────────────────────
-- Increments streak when room was active yesterday, resets otherwise.
-- Computes streak multiplier from streak days.

create or replace function public.update_room_streaks()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Reset daily passive cap counters for all rooms
  update public.rooms set xp_today_gift = 0, xp_today_passive = 0;

  -- Streak: active yesterday → increment, otherwise reset
  update public.rooms set
    daily_streak = case
      when last_active_date = current_date - 1 then daily_streak + 1
      when last_active_date = current_date     then daily_streak  -- already ran today
      else 0
    end,
    streak_multiplier = case
      when last_active_date = current_date - 1 then
        case
          when daily_streak + 1 >= 30 then 2.00
          when daily_streak + 1 >= 14 then 1.50
          when daily_streak + 1 >= 7  then 1.25
          when daily_streak + 1 >= 3  then 1.10
          else 1.00
        end
      when last_active_date = current_date then streak_multiplier
      else 1.00
    end
  where last_active_date is not null;
end;
$$;

-- Weekly XP reset
create or replace function public.reset_room_weekly_xp()
returns void
language sql
security definer
set search_path = public
as $$
  update public.rooms set xp_week = 0;
$$;

grant execute on function public.update_room_streaks()    to service_role;
grant execute on function public.reset_room_weekly_xp()   to service_role;

-- ── 6. Auto-grant gift XP via trigger on room_gifts ──────────────────────────
-- When a gift transaction lands in the room, gift coins → room XP (1:1).
-- Big gift bonus: coins > 500 → +20%, coins > 2000 → +50%

create or replace function public.trg_gift_grant_room_xp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coins  bigint;
  v_xp     bigint;
begin
  v_coins := coalesce(new.coins_amount, 0);
  if v_coins <= 0 then return new; end if;

  -- Big gift bonus
  v_xp := case
    when v_coins > 2000 then ceil(v_coins * 1.50)
    when v_coins > 500  then ceil(v_coins * 1.20)
    else v_coins
  end;

  perform public.grant_room_xp(new.room_id::uuid, v_xp, 'gift');
  return new;
end;
$$;

-- Only create trigger if room_gifts table exists and has room_id + coins_amount
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'room_gifts'
      and column_name  = 'coins_amount'
  ) then
    drop trigger if exists trg_gift_grant_room_xp on public.room_gifts;
    create trigger trg_gift_grant_room_xp
      after insert on public.room_gifts
      for each row execute function public.trg_gift_grant_room_xp();
  end if;
end $$;

-- ── 7. pg_cron jobs (register manually if pg_cron is enabled) ────────────────
-- Run daily at 00:00 UTC:
--   select cron.schedule('reset-room-streaks', '0 0 * * *', 'select public.update_room_streaks()');
-- Run weekly Monday 00:05 UTC:
--   select cron.schedule('reset-room-week-xp', '5 0 * * 1', 'select public.reset_room_weekly_xp()');
