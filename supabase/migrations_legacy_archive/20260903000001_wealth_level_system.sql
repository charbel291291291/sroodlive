-- =============================================================================
-- Wealth Level System
--
-- A 100-level wealth progression system separate from VIP and from the
-- existing user-level (activity XP) system.
--
-- Wealth XP sources:
--   - Coins recharged (approved by admin): 1 coin = 1 wealth XP
--   - Coins spent sending gifts:           1 coin = 1 wealth XP
--
-- 10 visual tiers, 10 levels each:
--   1-10   Bronze    #8B5E3C
--   11-20  Silver    #9E9E9E
--   21-30  Gold      #F0C15A
--   31-40  Emerald   #2ECC71
--   41-50  Sapphire  #2E86DE
--   51-60  Ruby      #E74C3C
--   61-70  Diamond   #00D4FF
--   71-80  Master    #9B59B6
--   81-90  Royal     #8B26D9
--   91-100 Legend    #FFD700
--
-- Nothing in this migration changes VIP logic, charm logic, wallet math,
-- or activity level (user_levels / level_rules).
-- =============================================================================

-- ── 1. Tables ─────────────────────────────────────────────────────────────────

create table if not exists public.wealth_level_rules (
  level        integer      primary key check (level between 1 and 100),
  tier_number  integer      not null    check (tier_number between 1 and 10),
  tier_name    text         not null,
  required_xp  bigint       not null    default 0,
  badge_key    text         not null,
  color_hex    text         not null,
  is_active    boolean      not null    default true
);

create table if not exists public.user_wealth (
  user_id              uuid        primary key references auth.users(id) on delete cascade,
  wealth_xp            bigint      not null default 0,
  wealth_level         integer     not null default 1,
  tier_number          integer     not null default 1,
  total_recharged_xp   bigint      not null default 0,
  total_spent_gift_xp  bigint      not null default 0,
  last_xp_at           timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- RLS
alter table public.wealth_level_rules enable row level security;
alter table public.user_wealth        enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='wealth_level_rules' and policyname='wealth_rules_public_read'
  ) then
    create policy wealth_rules_public_read on public.wealth_level_rules
      for select using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='user_wealth' and policyname='user_wealth_own_read'
  ) then
    create policy user_wealth_own_read on public.user_wealth
      for select using (auth.uid() = user_id);
  end if;
end $$;

-- ── 2. Seed wealth_level_rules (100 rows) ────────────────────────────────────
-- Cumulative XP boundaries per tier:
--   Bronze   L1-10:  0          - 90,000         step 10,000
--   Silver   L11-20: 100,000    - 460,000        step 40,000
--   Gold     L21-30: 500,000    - 1,850,000      step 150,000
--   Emerald  L31-40: 2,000,000  - 7,400,000      step 600,000
--   Sapphire L41-50: 8,000,000  - 27,800,000     step 2,200,000
--   Ruby     L51-60: 30,000,000 - 93,000,000     step 7,000,000
--   Diamond  L61-70: 100,000,000- 280,000,000    step 20,000,000
--   Master   L71-80: 300,000,000- 750,000,000    step 50,000,000
--   Royal    L81-90: 800,000,000- 1,880,000,000  step 120,000,000
--   Legend   L91-100:2,000,000,000-4,700,000,000 step 300,000,000

insert into public.wealth_level_rules
  (level, tier_number, tier_name, required_xp, badge_key, color_hex)
values
  -- Bronze
  (1,  1,'Bronze',          0,'wealth_bronze','#8B5E3C'),
  (2,  1,'Bronze',      10000,'wealth_bronze','#8B5E3C'),
  (3,  1,'Bronze',      20000,'wealth_bronze','#8B5E3C'),
  (4,  1,'Bronze',      30000,'wealth_bronze','#8B5E3C'),
  (5,  1,'Bronze',      40000,'wealth_bronze','#8B5E3C'),
  (6,  1,'Bronze',      50000,'wealth_bronze','#8B5E3C'),
  (7,  1,'Bronze',      60000,'wealth_bronze','#8B5E3C'),
  (8,  1,'Bronze',      70000,'wealth_bronze','#8B5E3C'),
  (9,  1,'Bronze',      80000,'wealth_bronze','#8B5E3C'),
  (10, 1,'Bronze',      90000,'wealth_bronze','#8B5E3C'),
  -- Silver
  (11, 2,'Silver',     100000,'wealth_silver','#9E9E9E'),
  (12, 2,'Silver',     140000,'wealth_silver','#9E9E9E'),
  (13, 2,'Silver',     180000,'wealth_silver','#9E9E9E'),
  (14, 2,'Silver',     220000,'wealth_silver','#9E9E9E'),
  (15, 2,'Silver',     260000,'wealth_silver','#9E9E9E'),
  (16, 2,'Silver',     300000,'wealth_silver','#9E9E9E'),
  (17, 2,'Silver',     340000,'wealth_silver','#9E9E9E'),
  (18, 2,'Silver',     380000,'wealth_silver','#9E9E9E'),
  (19, 2,'Silver',     420000,'wealth_silver','#9E9E9E'),
  (20, 2,'Silver',     460000,'wealth_silver','#9E9E9E'),
  -- Gold
  (21, 3,'Gold',       500000,'wealth_gold','#F0C15A'),
  (22, 3,'Gold',       650000,'wealth_gold','#F0C15A'),
  (23, 3,'Gold',       800000,'wealth_gold','#F0C15A'),
  (24, 3,'Gold',       950000,'wealth_gold','#F0C15A'),
  (25, 3,'Gold',      1100000,'wealth_gold','#F0C15A'),
  (26, 3,'Gold',      1250000,'wealth_gold','#F0C15A'),
  (27, 3,'Gold',      1400000,'wealth_gold','#F0C15A'),
  (28, 3,'Gold',      1550000,'wealth_gold','#F0C15A'),
  (29, 3,'Gold',      1700000,'wealth_gold','#F0C15A'),
  (30, 3,'Gold',      1850000,'wealth_gold','#F0C15A'),
  -- Emerald
  (31, 4,'Emerald',   2000000,'wealth_emerald','#2ECC71'),
  (32, 4,'Emerald',   2600000,'wealth_emerald','#2ECC71'),
  (33, 4,'Emerald',   3200000,'wealth_emerald','#2ECC71'),
  (34, 4,'Emerald',   3800000,'wealth_emerald','#2ECC71'),
  (35, 4,'Emerald',   4400000,'wealth_emerald','#2ECC71'),
  (36, 4,'Emerald',   5000000,'wealth_emerald','#2ECC71'),
  (37, 4,'Emerald',   5600000,'wealth_emerald','#2ECC71'),
  (38, 4,'Emerald',   6200000,'wealth_emerald','#2ECC71'),
  (39, 4,'Emerald',   6800000,'wealth_emerald','#2ECC71'),
  (40, 4,'Emerald',   7400000,'wealth_emerald','#2ECC71'),
  -- Sapphire
  (41, 5,'Sapphire',  8000000,'wealth_sapphire','#2E86DE'),
  (42, 5,'Sapphire', 10200000,'wealth_sapphire','#2E86DE'),
  (43, 5,'Sapphire', 12400000,'wealth_sapphire','#2E86DE'),
  (44, 5,'Sapphire', 14600000,'wealth_sapphire','#2E86DE'),
  (45, 5,'Sapphire', 16800000,'wealth_sapphire','#2E86DE'),
  (46, 5,'Sapphire', 19000000,'wealth_sapphire','#2E86DE'),
  (47, 5,'Sapphire', 21200000,'wealth_sapphire','#2E86DE'),
  (48, 5,'Sapphire', 23400000,'wealth_sapphire','#2E86DE'),
  (49, 5,'Sapphire', 25600000,'wealth_sapphire','#2E86DE'),
  (50, 5,'Sapphire', 27800000,'wealth_sapphire','#2E86DE'),
  -- Ruby
  (51, 6,'Ruby',     30000000,'wealth_ruby','#E74C3C'),
  (52, 6,'Ruby',     37000000,'wealth_ruby','#E74C3C'),
  (53, 6,'Ruby',     44000000,'wealth_ruby','#E74C3C'),
  (54, 6,'Ruby',     51000000,'wealth_ruby','#E74C3C'),
  (55, 6,'Ruby',     58000000,'wealth_ruby','#E74C3C'),
  (56, 6,'Ruby',     65000000,'wealth_ruby','#E74C3C'),
  (57, 6,'Ruby',     72000000,'wealth_ruby','#E74C3C'),
  (58, 6,'Ruby',     79000000,'wealth_ruby','#E74C3C'),
  (59, 6,'Ruby',     86000000,'wealth_ruby','#E74C3C'),
  (60, 6,'Ruby',     93000000,'wealth_ruby','#E74C3C'),
  -- Diamond
  (61, 7,'Diamond', 100000000,'wealth_diamond','#00D4FF'),
  (62, 7,'Diamond', 120000000,'wealth_diamond','#00D4FF'),
  (63, 7,'Diamond', 140000000,'wealth_diamond','#00D4FF'),
  (64, 7,'Diamond', 160000000,'wealth_diamond','#00D4FF'),
  (65, 7,'Diamond', 180000000,'wealth_diamond','#00D4FF'),
  (66, 7,'Diamond', 200000000,'wealth_diamond','#00D4FF'),
  (67, 7,'Diamond', 220000000,'wealth_diamond','#00D4FF'),
  (68, 7,'Diamond', 240000000,'wealth_diamond','#00D4FF'),
  (69, 7,'Diamond', 260000000,'wealth_diamond','#00D4FF'),
  (70, 7,'Diamond', 280000000,'wealth_diamond','#00D4FF'),
  -- Master
  (71, 8,'Master',  300000000,'wealth_master','#9B59B6'),
  (72, 8,'Master',  350000000,'wealth_master','#9B59B6'),
  (73, 8,'Master',  400000000,'wealth_master','#9B59B6'),
  (74, 8,'Master',  450000000,'wealth_master','#9B59B6'),
  (75, 8,'Master',  500000000,'wealth_master','#9B59B6'),
  (76, 8,'Master',  550000000,'wealth_master','#9B59B6'),
  (77, 8,'Master',  600000000,'wealth_master','#9B59B6'),
  (78, 8,'Master',  650000000,'wealth_master','#9B59B6'),
  (79, 8,'Master',  700000000,'wealth_master','#9B59B6'),
  (80, 8,'Master',  750000000,'wealth_master','#9B59B6'),
  -- Royal
  (81, 9,'Royal',   800000000,'wealth_royal','#8B26D9'),
  (82, 9,'Royal',   920000000,'wealth_royal','#8B26D9'),
  (83, 9,'Royal',  1040000000,'wealth_royal','#8B26D9'),
  (84, 9,'Royal',  1160000000,'wealth_royal','#8B26D9'),
  (85, 9,'Royal',  1280000000,'wealth_royal','#8B26D9'),
  (86, 9,'Royal',  1400000000,'wealth_royal','#8B26D9'),
  (87, 9,'Royal',  1520000000,'wealth_royal','#8B26D9'),
  (88, 9,'Royal',  1640000000,'wealth_royal','#8B26D9'),
  (89, 9,'Royal',  1760000000,'wealth_royal','#8B26D9'),
  (90, 9,'Royal',  1880000000,'wealth_royal','#8B26D9'),
  -- Legend
  (91, 10,'Legend',2000000000,'wealth_legend','#FFD700'),
  (92, 10,'Legend',2300000000,'wealth_legend','#FFD700'),
  (93, 10,'Legend',2600000000,'wealth_legend','#FFD700'),
  (94, 10,'Legend',2900000000,'wealth_legend','#FFD700'),
  (95, 10,'Legend',3200000000,'wealth_legend','#FFD700'),
  (96, 10,'Legend',3500000000,'wealth_legend','#FFD700'),
  (97, 10,'Legend',3800000000,'wealth_legend','#FFD700'),
  (98, 10,'Legend',4100000000,'wealth_legend','#FFD700'),
  (99, 10,'Legend',4400000000,'wealth_legend','#FFD700'),
  (100,10,'Legend',4700000000,'wealth_legend','#FFD700')
on conflict (level) do update
  set tier_number = excluded.tier_number,
      tier_name   = excluded.tier_name,
      required_xp = excluded.required_xp,
      badge_key   = excluded.badge_key,
      color_hex   = excluded.color_hex;

-- ── 3. add_wealth_xp(uuid, bigint, text) ─────────────────────────────────────
-- SECURITY DEFINER — called only from other SECURITY DEFINER functions.
-- Awards wealth XP to a user and recalculates their wealth level.
-- Never raises; caller wraps in BEGIN...EXCEPTION WHEN OTHERS THEN NULL.

create or replace function public.add_wealth_xp(
  p_user_id uuid,
  p_xp      bigint,
  p_source  text default null
)
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
  if p_xp <= 0 then return; end if;

  -- Upsert user_wealth row and accumulate XP.
  insert into public.user_wealth (user_id, wealth_xp, last_xp_at, updated_at)
  values (p_user_id, p_xp, now(), now())
  on conflict (user_id) do update
    set wealth_xp   = public.user_wealth.wealth_xp + p_xp,
        last_xp_at  = now(),
        updated_at  = now();

  -- Also increment the split counter based on source.
  if p_source = 'recharge' then
    update public.user_wealth
    set total_recharged_xp = total_recharged_xp + p_xp
    where user_id = p_user_id;
  elsif p_source = 'gift_sent' then
    update public.user_wealth
    set total_spent_gift_xp = total_spent_gift_xp + p_xp
    where user_id = p_user_id;
  end if;

  -- Read updated total XP.
  select wealth_xp into v_new_xp
  from public.user_wealth
  where user_id = p_user_id;

  -- Calculate new level from XP table.
  select level, tier_number
  into   v_new_level, v_new_tier
  from   public.wealth_level_rules
  where  required_xp <= v_new_xp
    and  is_active = true
  order  by required_xp desc
  limit  1;

  -- Default to level 1 / tier 1 if somehow no rule matched.
  v_new_level := coalesce(v_new_level, 1);
  v_new_tier  := coalesce(v_new_tier,  1);

  -- Persist the recalculated level and tier.
  update public.user_wealth
  set    wealth_level = v_new_level,
         tier_number  = v_new_tier,
         updated_at   = now()
  where  user_id = p_user_id;
end;
$$;

-- Not granted to authenticated — called only by other SECURITY DEFINER functions.

-- ── 4. get_my_wealth_level() ─────────────────────────────────────────────────
-- Returns the calling user's full wealth progress snapshot as JSON.

create or replace function public.get_my_wealth_level()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_row        public.user_wealth;
  v_curr_rule  public.wealth_level_rules;
  v_next_rule  public.wealth_level_rules;
  v_band_start bigint;
  v_band_size  bigint;
  v_progress   numeric;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  -- Ensure the row exists.
  insert into public.user_wealth (user_id) values (v_user_id)
  on conflict (user_id) do nothing;

  select * into v_row from public.user_wealth where user_id = v_user_id;

  -- Current level rule.
  select * into v_curr_rule
  from   public.wealth_level_rules
  where  level = v_row.wealth_level;

  -- Next level rule (null at level 100).
  select * into v_next_rule
  from   public.wealth_level_rules
  where  level = v_row.wealth_level + 1;

  -- Progress within current level band (0.0 - 1.0).
  if v_next_rule.level is not null then
    v_band_start := v_curr_rule.required_xp;
    v_band_size  := v_next_rule.required_xp - v_band_start;
    v_progress   := case when v_band_size > 0
                         then least(1.0, (v_row.wealth_xp - v_band_start)::numeric / v_band_size)
                         else 1.0 end;
  else
    v_progress := 1.0;
  end if;

  return json_build_object(
    'wealth_level',        v_row.wealth_level,
    'wealth_xp',           v_row.wealth_xp,
    'tier_number',         v_row.tier_number,
    'tier_name',           v_curr_rule.tier_name,
    'color_hex',           v_curr_rule.color_hex,
    'badge_key',           v_curr_rule.badge_key,
    'next_level',          v_next_rule.level,
    'next_level_required_xp', v_next_rule.required_xp,
    'xp_to_next_level',   case when v_next_rule.level is not null
                               then greatest(0, v_next_rule.required_xp - v_row.wealth_xp)
                               else null end,
    'level_progress',      v_progress,
    'total_recharged_xp',  v_row.total_recharged_xp,
    'total_spent_gift_xp', v_row.total_spent_gift_xp,
    'last_xp_at',          to_char(v_row.last_xp_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
end;
$$;

grant execute on function public.get_my_wealth_level() to authenticated;

-- ── 5. get_user_wealth_level(uuid) ───────────────────────────────────────────
-- Public display: returns another user's wealth level and tier for badge rendering.

create or replace function public.get_user_wealth_level(p_user_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   public.user_wealth;
  v_rule  public.wealth_level_rules;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  select * into v_row from public.user_wealth where user_id = p_user_id;

  if not found then
    return json_build_object(
      'wealth_level', 1, 'tier_number', 1, 'tier_name', 'Bronze',
      'color_hex', '#8B5E3C', 'badge_key', 'wealth_bronze'
    );
  end if;

  select * into v_rule from public.wealth_level_rules where level = v_row.wealth_level;

  return json_build_object(
    'wealth_level', v_row.wealth_level,
    'tier_number',  v_row.tier_number,
    'tier_name',    v_rule.tier_name,
    'color_hex',    v_rule.color_hex,
    'badge_key',    v_rule.badge_key
  );
end;
$$;

grant execute on function public.get_user_wealth_level(uuid) to authenticated;

-- ── 6. Hook wealth XP into send_gift_with_wallet ─────────────────────────────
-- Body copied verbatim from 20260706000000_user_level_phase_l3_gift_xp.sql.
-- Only addition: the Wealth XP side-effect block after the Level XP block.

CREATE OR REPLACE FUNCTION public.send_gift_with_wallet(
  p_room_id     uuid,
  p_receiver_id uuid,
  p_gift_id     uuid,
  p_quantity    integer DEFAULT 1
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id           uuid    := auth.uid();
  v_quantity            integer := GREATEST(COALESCE(p_quantity, 1), 1);
  v_gift                record;
  v_total_cost          integer;
  v_diamonds_earned     integer;
  v_sender_wallet       public.wallets;
  v_receiver_wallet     public.wallets;
  v_gift_transaction_id uuid;
BEGIN
  -- ── Auth & validation ─────────────────────────────────────────────────────
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_receiver_id IS NULL OR p_receiver_id = v_sender_id THEN
    RAISE EXCEPTION 'invalid_receiver';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_members rm
    WHERE rm.room_id = p_room_id
      AND rm.user_id = v_sender_id
      AND rm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'sender_not_in_room';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_members rm
    WHERE rm.room_id = p_room_id
      AND rm.user_id = p_receiver_id
      AND rm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'receiver_not_in_room';
  END IF;

  -- ── Gift lookup ───────────────────────────────────────────────────────────
  SELECT g.id, g.code, g.name, g.price_coins
  INTO   v_gift
  FROM   public.gifts g
  WHERE  g.id = p_gift_id
    AND  COALESCE(g.is_active, true)
  LIMIT  1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'gift_not_found';
  END IF;

  v_total_cost      := v_gift.price_coins::integer * v_quantity;
  v_diamonds_earned := v_total_cost;

  IF v_total_cost <= 0 THEN
    RAISE EXCEPTION 'invalid_gift_price';
  END IF;

  -- ── Ensure wallets exist ──────────────────────────────────────────────────
  INSERT INTO public.wallets (user_id) VALUES (v_sender_id)
    ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.wallets (user_id) VALUES (p_receiver_id)
    ON CONFLICT (user_id) DO NOTHING;

  -- ── Lock sender wallet and check balance ──────────────────────────────────
  SELECT * INTO v_sender_wallet
  FROM   public.wallets
  WHERE  user_id = v_sender_id
  FOR UPDATE;

  IF v_sender_wallet.coins_balance < v_total_cost THEN
    RAISE EXCEPTION 'insufficient_coins';
  END IF;

  -- ── Debit sender / credit receiver ───────────────────────────────────────
  UPDATE public.wallets
  SET    coins_balance        = coins_balance        - v_total_cost,
         lifetime_coins_spent = lifetime_coins_spent + v_total_cost,
         updated_at           = now()
  WHERE  user_id = v_sender_id
  RETURNING * INTO v_sender_wallet;

  UPDATE public.wallets
  SET    diamonds_balance         = diamonds_balance         + v_diamonds_earned,
         lifetime_diamonds_earned = lifetime_diamonds_earned + v_diamonds_earned,
         updated_at               = now()
  WHERE  user_id = p_receiver_id
  RETURNING * INTO v_receiver_wallet;

  -- ── Record gift transaction ───────────────────────────────────────────────
  INSERT INTO public.gift_transactions (
    room_id, sender_id, receiver_id,
    gift_id, gift_code, gift_name, gift_price_coins
  ) VALUES (
    p_room_id, v_sender_id, p_receiver_id,
    v_gift.id, v_gift.code, v_gift.name, v_total_cost
  )
  RETURNING id INTO v_gift_transaction_id;

  -- ── Wallet transaction ledger — sender ────────────────────────────────────
  INSERT INTO public.wallet_transactions (
    user_id, type, direction, coins_delta,
    balance_coins_after, balance_diamonds_after,
    related_user_id, related_room_id, related_gift_id,
    related_gift_transaction_id, note, metadata
  ) VALUES (
    v_sender_id, 'gift_sent', 'debit', -v_total_cost,
    v_sender_wallet.coins_balance, v_sender_wallet.diamonds_balance,
    p_receiver_id, p_room_id, v_gift.id,
    v_gift_transaction_id, 'Gift sent',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  -- ── Wallet transaction ledger — receiver ──────────────────────────────────
  INSERT INTO public.wallet_transactions (
    user_id, type, direction, diamonds_delta,
    balance_coins_after, balance_diamonds_after,
    related_user_id, related_room_id, related_gift_id,
    related_gift_transaction_id, note, metadata
  ) VALUES (
    p_receiver_id, 'gift_received', 'credit', v_diamonds_earned,
    v_receiver_wallet.coins_balance, v_receiver_wallet.diamonds_balance,
    v_sender_id, p_room_id, v_gift.id,
    v_gift_transaction_id, 'Gift received',
    jsonb_build_object('quantity', v_quantity, 'gift_code', v_gift.code)
  );

  -- ── Team PK scoring side-effect ───────────────────────────────────────────
  BEGIN
    PERFORM public.record_team_pk_gift_support(
      p_room_id,
      v_sender_id,
      p_receiver_id,
      v_gift_transaction_id,
      v_gift.code,
      v_total_cost::bigint
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- ── User Level XP side-effect (Phase L3) ─────────────────────────────────
  BEGIN
    PERFORM public.add_user_xp(
      v_sender_id,
      v_total_cost::bigint,
      'gift_sent'
    );

    UPDATE public.user_levels
    SET    total_gifts_sent = total_gifts_sent + v_quantity,
           updated_at       = now()
    WHERE  user_id = v_sender_id;

    INSERT INTO public.user_levels (user_id, total_gifts_received)
    VALUES (p_receiver_id, v_quantity)
    ON CONFLICT (user_id) DO UPDATE
      SET total_gifts_received = public.user_levels.total_gifts_received + v_quantity,
          updated_at           = now();

  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- ── Wealth XP side-effect ─────────────────────────────────────────────────
  -- 1 coin spent on a gift = 1 wealth XP to the sender.
  -- Swallowed so it can never break the gift flow.
  BEGIN
    PERFORM public.add_wealth_xp(
      v_sender_id,
      v_total_cost::bigint,
      'gift_sent'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_gift_transaction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_gift_with_wallet(uuid, uuid, uuid, integer) TO authenticated;

-- ── 7. Hook wealth XP into approve_recharge_request ──────────────────────────
-- Body copied verbatim from 20260703000000_vip_recharge_exp_phase_g.sql.
-- Only addition: the Wealth XP side-effect block after the VIP EXP hook.

CREATE OR REPLACE FUNCTION public.approve_recharge_request(
  p_request_id uuid,
  p_admin_note text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_request  public.recharge_requests;
  v_wallet   public.wallets;
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT public.has_finance_access() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT *
  INTO   v_request
  FROM   public.recharge_requests rr
  WHERE  rr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recharge_request_not_found';
  END IF;

  -- Double-apply guard: only pending requests can be approved
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'recharge_request_not_pending';
  END IF;

  -- ── Coin credit (unchanged) ───────────────────────────────────────────────

  INSERT INTO public.wallets (user_id)
  VALUES (v_request.user_id)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.wallets
  SET    coins_balance          = coins_balance          + v_request.requested_coins,
         lifetime_coins_charged = lifetime_coins_charged + v_request.requested_coins,
         updated_at             = now()
  WHERE  user_id = v_request.user_id
  RETURNING * INTO v_wallet;

  UPDATE public.recharge_requests
  SET    status        = 'approved',
         admin_user_id = v_admin_id,
         admin_note    = NULLIF(TRIM(COALESCE(p_admin_note, '')), ''),
         approved_at   = now(),
         updated_at    = now()
  WHERE  id = v_request.id;

  INSERT INTO public.wallet_transactions (
    user_id,
    type,
    direction,
    coins_delta,
    balance_coins_after,
    balance_diamonds_after,
    related_recharge_request_id,
    agency_id,
    agent_id,
    note
  )
  VALUES (
    v_request.user_id,
    CASE WHEN v_request.agent_id IS NULL THEN 'recharge_request' ELSE 'agency_recharge' END,
    'credit',
    v_request.requested_coins,
    v_wallet.coins_balance,
    v_wallet.diamonds_balance,
    v_request.id,
    v_request.agency_id,
    v_request.agent_id,
    p_admin_note
  );

  -- ── VIP EXP hook ─────────────────────────────────────────────────────────
  PERFORM public.apply_vip_recharge_exp(
    v_request.user_id,
    v_request.requested_coins::bigint
  );

  -- ── Wealth XP side-effect ─────────────────────────────────────────────────
  -- 1 recharged coin = 1 wealth XP.
  -- Swallowed so it can never break the recharge approval.
  BEGIN
    PERFORM public.add_wealth_xp(
      v_request.user_id,
      v_request.requested_coins::bigint,
      'recharge'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_recharge_request(uuid, text) TO authenticated;

-- ── 8. Realtime publication ───────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_wealth'
  ) then
    alter publication supabase_realtime add table public.user_wealth;
  end if;
end $$;
