-- =============================================================================
-- BASELINE — manual foundation reconstruction (forward-only recovery)
--
-- ROOT CAUSE: the migration history has no baseline. It begins by ALTERing a
-- production schema that was built manually (out of band). 29 production tables
-- — including the foundational profiles / rooms / room_members — are never
-- created by any migration, yet are referenced by 70 / 71 / 51 migrations
-- respectively. A clean `db reset` from zero therefore failed at the first
-- migration that touches one of them (20260602122424 → room_members policy).
--
-- FIX: this migration recreates those 29 tables EXACTLY from READ-ONLY
-- production metadata (columns, defaults, primary/unique/check constraints) so
-- the historical ALTER-migrations replay on top. It runs BEFORE any historical
-- migration (timestamp 20260602000000) and uses CREATE TABLE IF NOT EXISTS +
-- guarded RLS enablement, so it introduces NO duplicate architecture:
--   • Tables the migrations DO create (136 of them) are untouched here.
--   • RLS is ENABLED on every reconstructed table (never disabled); individual
--     policies remain owned by the historical migrations that manage them
--     (drop-if-exists/create), so nothing is duplicated.
--   • No values are guessed — every column/type/default/constraint is copied
--     verbatim from production catalog introspection.
-- Nothing in this file is applied to production; it exists only so a local
-- `supabase db reset` can build the same foundation prod already has.
-- =============================================================================

-- ── Default-generator helpers (plpgsql, late-bound to their tables) ──────────
create or replace function public.generate_5digit_room_code()
returns text language plpgsql security definer set search_path to 'public'
as $function$
declare v_candidate text; v_attempts int := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    if v_attempts > 100 then raise exception 'generate_5digit_room_code: no unique code found after 100 attempts'; end if;
    v_candidate := (floor(random() * 90000) + 10000)::bigint::text;
    exit when not exists (select 1 from public.rooms where public_room_code = v_candidate);
  end loop;
  return v_candidate;
end;
$function$;

create or replace function public.generate_6digit_public_user_id()
returns text language plpgsql security definer set search_path to 'public'
as $function$
declare v_candidate text; v_attempts int := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    if v_attempts > 50 then raise exception 'generate_6digit_public_user_id: could not find unique ID after 50 attempts'; end if;
    v_candidate := (floor(random() * 900000) + 100000)::bigint::text;
    exit when not exists (select 1 from public.profiles where public_user_id = v_candidate);
  end loop;
  return v_candidate;
end;
$function$;

-- ── Foundational tables (verbatim from production) ───────────────────────────

create table if not exists public.profiles (
  id uuid not null,
  email text,
  username text,
  display_name text,
  avatar_url text,
  role text default 'user'::text not null,
  is_banned boolean default false not null,
  coins_balance integer default 0 not null,
  vip_level integer default 0 not null,
  vip_expires_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  public_user_id text default generate_6digit_public_user_id() not null,
  date_of_birth date,
  bio text,
  selected_avatar_frame_key text,
  vip_started_at timestamptz,
  vip_title text,
  is_golden_id boolean default false not null,
  golden_id_expires_at timestamptz,
  follower_count integer default 0 not null,
  following_count integer default 0 not null,
  friends_count integer default 0 not null,
  room_count integer default 0 not null,
  total_gifts_sent integer default 0 not null,
  total_gifts_received integer default 0 not null,
  cover_url text,
  country text,
  gender text,
  is_online boolean default false not null,
  last_seen timestamptz,
  level integer default 1 not null,
  followers_count integer default 0 not null,
  followings_count integer default 0 not null,
  friend_count integer default 0 not null,
  rooms_count integer default 0 not null,
  gifts_sent_count integer default 0 not null,
  gifts_received_count integer default 0 not null,
  coins_sent integer default 0 not null,
  coins_received integer default 0 not null,
  total_earned integer default 0 not null,
  total_spent integer default 0 not null,
  full_name text,
  visitors_count integer default 0 not null,
  visitor_count integer default 0 not null,
  views_count integer default 0 not null,
  view_count integer default 0 not null,
  likes_count integer default 0 not null,
  like_count integer default 0 not null,
  posts_count integer default 0 not null,
  post_count integer default 0 not null,
  fans_count integer default 0 not null,
  fan_count integer default 0 not null,
  badge_count integer default 0 not null,
  badges_count integer default 0 not null,
  charm_count integer default 0 not null,
  charms_count integer default 0 not null,
  popularity_score integer default 0 not null,
  wealth_score integer default 0 not null,
  charm_score integer default 0 not null,
  contribution_score integer default 0 not null,
  experience_points integer default 0 not null,
  xp integer default 0 not null,
  status text,
  mood text,
  city text,
  birthdate date,
  vip_recharge_exp bigint default 0 not null,
  vip_monthly_exp bigint default 0 not null,
  vip_cycle_started_at timestamptz,
  vip_last_recharge_at timestamptz,
  golden_id_style text default 'gold'::text not null,
  golden_id_frame text default 'classic'::text not null,
  country_code text,
  country_flag_style text default 'normal'::text not null,
  country_flag_frame text default 'classic'::text not null,
  country_flag_expires_at timestamptz,
  gender_changed_once boolean default false not null,
  country_changed_once boolean default false not null,
  gender_changed_at timestamptz,
  country_changed_at timestamptz,
  constraint profiles_pkey primary key (id),
  constraint profiles_username_key unique (username),
  constraint profiles_public_user_id_key unique (public_user_id),
  constraint profiles_vip_recharge_exp_check check (vip_recharge_exp >= 0),
  constraint profiles_vip_monthly_exp_check check (vip_monthly_exp >= 0),
  constraint profiles_vip_level_range check (vip_level >= 0 and vip_level <= 9),
  constraint profiles_public_user_id_format check (public_user_id ~ '^SR[0-9]{1,28}$' or public_user_id ~ '^[a-z0-9_]{2,30}$')
);

create table if not exists public.rooms (
  id uuid default gen_random_uuid() not null,
  owner_id uuid not null,
  name text not null,
  description text,
  language text default 'ar'::text not null,
  is_private boolean default false not null,
  is_locked boolean default false not null,
  max_seats integer default 12 not null,
  livekit_room_name text not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  room_password_hash text,
  is_closed boolean default false not null,
  closed_at timestamptz,
  closed_by uuid,
  closed_reason text,
  is_live boolean default false not null,
  ended_at timestamptz,
  cover_url text,
  member_count integer default 0 not null,
  max_members integer,
  category text,
  tags text[] default '{}'::text[] not null,
  background_url text,
  room_avatar_url text,
  room_pin_enabled boolean default false not null,
  room_pin_hash text,
  is_personal_room boolean default false not null,
  closed_seats integer[] default '{}'::integer[] not null,
  room_level smallint default 1 not null,
  allow_images boolean default true not null,
  public_room_code text default generate_5digit_room_code() not null,
  is_room_muted boolean default false not null,
  country_code text,
  golden_room_id text,
  is_golden_room boolean default false not null,
  golden_room_expires_at timestamptz,
  room_xp bigint default 0 not null,
  xp_today_gift integer default 0 not null,
  xp_today_passive integer default 0 not null,
  xp_week bigint default 0 not null,
  daily_streak smallint default 0 not null,
  streak_multiplier numeric(4,2) default 1.00 not null,
  last_active_date date,
  last_xp_at timestamptz,
  archived_at timestamptz,
  archived_by uuid,
  archive_reason text,
  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  access_mode text default 'open'::text not null,
  constraint rooms_pkey primary key (id),
  constraint rooms_public_room_code_key unique (public_room_code),
  constraint rooms_livekit_room_name_key unique (livekit_room_name),
  constraint rooms_golden_room_id_key unique (golden_room_id),
  constraint rooms_room_level_check check (room_level >= 1 and room_level <= 50),
  constraint rooms_public_room_code_format check (public_room_code ~ '^[1-9][0-9]{4}$'),
  constraint rooms_access_mode_valid check (access_mode = any (array['open'::text,'watch'::text]))
);

create table if not exists public.room_members (
  id uuid default gen_random_uuid() not null,
  room_id uuid not null,
  user_id uuid not null,
  role text default 'listener'::text not null,
  seat_number integer,
  is_muted boolean default false not null,
  joined_at timestamptz default now() not null,
  left_at timestamptz,
  last_seen_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  force_muted boolean default false not null,
  constraint room_members_pkey primary key (id),
  constraint room_members_room_id_user_id_key unique (room_id, user_id),
  constraint room_members_seat_number_valid check (seat_number is null or (seat_number >= 1 and seat_number <= 100))
);

create table if not exists public.room_youtube_state (
  room_id uuid not null,
  video_id text,
  video_url text,
  title text,
  is_playing boolean default false not null,
  position_seconds integer default 0 not null,
  started_at timestamptz,
  controller_user_id uuid,
  updated_at timestamptz default now() not null,
  thumbnail_url text,
  controlled_by_user_id uuid,
  controlled_by_name text,
  last_action text default 'idle'::text not null,
  constraint room_youtube_state_pkey primary key (room_id),
  constraint room_youtube_state_position_seconds_check check (position_seconds >= 0)
);

create table if not exists public.gifts (
  id uuid default gen_random_uuid() not null,
  code text not null,
  name text not null,
  arabic_name text not null,
  price_coins integer not null,
  icon text default 'gift'::text not null,
  is_active boolean default true not null,
  sort_order integer default 0 not null,
  created_at timestamptz default now() not null,
  category text default 'hot'::text not null,
  required_vip_level integer default 0 not null,
  animation_url text,
  is_featured boolean default false not null,
  icon_url text,
  updated_at timestamptz default now() not null,
  constraint gifts_pkey primary key (id),
  constraint gifts_code_key unique (code),
  constraint gifts_price_coins_check check (price_coins > 0),
  constraint gifts_category_check check (category = any (array['classic'::text,'love'::text,'luxury'::text,'lebanon'::text,'vip'::text,'event'::text,'legendary'::text,'hot'::text]))
);

create table if not exists public.gift_transactions (
  id uuid default gen_random_uuid() not null,
  room_id uuid not null,
  sender_id uuid not null,
  receiver_id uuid not null,
  gift_id uuid not null,
  gift_code text not null,
  gift_name text not null,
  gift_price_coins integer not null,
  created_at timestamptz default now() not null,
  quantity integer default 1 not null,
  total_cost_coins bigint default 0 not null,
  constraint gift_transactions_pkey primary key (id),
  constraint gift_transactions_quantity_check check (quantity > 0),
  constraint gift_transactions_gift_price_coins_check check (gift_price_coins > 0)
);

create table if not exists public.user_blocks (
  blocker_id uuid not null,
  blocked_id uuid not null,
  created_at timestamptz default now() not null,
  constraint user_blocks_pkey primary key (blocker_id, blocked_id)
);

create table if not exists public.backpack_items (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  item_id uuid not null,
  item_type text not null,
  equipped boolean default false not null,
  acquired_at timestamptz default now() not null,
  metadata jsonb default '{}'::jsonb not null,
  constraint backpack_items_pkey primary key (id),
  constraint backpack_items_user_id_item_id_key unique (user_id, item_id)
);

create table if not exists public.store_items (
  id uuid default gen_random_uuid() not null,
  name text not null,
  name_ar text not null,
  description text default ''::text not null,
  description_ar text default ''::text not null,
  item_type text not null,
  price_coins integer default 0 not null,
  price_diamonds integer default 0 not null,
  icon_name text,
  metadata jsonb default '{}'::jsonb not null,
  is_active boolean default true not null,
  sort_order integer default 0 not null,
  created_at timestamptz default now() not null,
  constraint store_items_pkey primary key (id),
  constraint store_items_price_coins_check check (price_coins >= 0),
  constraint store_items_price_diamonds_check check (price_diamonds >= 0),
  constraint store_items_item_type_check check (item_type = any (array['avatar_frame'::text,'badge'::text,'entrance_effect'::text,'coin_boost'::text]))
);

create table if not exists public.tasks (
  id uuid default gen_random_uuid() not null,
  title text not null,
  title_ar text not null,
  description text default ''::text not null,
  description_ar text default ''::text not null,
  task_type text not null,
  requirement_type text not null,
  requirement_count integer default 1 not null,
  reward_type text not null,
  reward_amount integer not null,
  sort_order integer default 0 not null,
  is_active boolean default true not null,
  created_at timestamptz default now() not null,
  constraint tasks_pkey primary key (id),
  constraint tasks_requirement_count_check check (requirement_count > 0),
  constraint tasks_reward_amount_check check (reward_amount > 0),
  constraint tasks_task_type_check check (task_type = any (array['daily'::text,'weekly'::text])),
  constraint tasks_reward_type_check check (reward_type = any (array['coins'::text,'diamonds'::text,'xp'::text]))
);

create table if not exists public.user_task_progress (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  task_id uuid not null,
  period_key text not null,
  progress integer default 0 not null,
  completed boolean default false not null,
  claimed boolean default false not null,
  completed_at timestamptz,
  created_at timestamptz default now() not null,
  constraint user_task_progress_pkey primary key (id),
  constraint user_task_progress_user_id_task_id_period_key_key unique (user_id, task_id, period_key)
);

create table if not exists public.daily_checkins (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  checkin_date date default CURRENT_DATE not null,
  streak_day integer default 1 not null,
  reward_type text not null,
  reward_amount integer not null,
  created_at timestamptz default now() not null,
  constraint daily_checkins_pkey primary key (id),
  constraint daily_checkins_user_id_checkin_date_key unique (user_id, checkin_date),
  constraint daily_checkins_streak_day_check check (streak_day >= 1 and streak_day <= 7),
  constraint daily_checkins_reward_amount_check check (reward_amount > 0)
);

create table if not exists public.game_wallets (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  coins bigint default 0 not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint game_wallets_pkey primary key (id),
  constraint game_wallets_user_id_unique unique (user_id),
  constraint game_wallets_coins_check check (coins >= 0)
);

create table if not exists public.crash_transactions (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  round_id uuid not null,
  type text not null,
  amount bigint not null,
  balance_before bigint not null,
  balance_after bigint not null,
  created_at timestamptz default now() not null,
  bet_id uuid,
  constraint crash_transactions_pkey primary key (id),
  constraint crash_transactions_amount_check check (amount > 0),
  constraint crash_transactions_type_check check (type = any (array['bet'::text,'win'::text,'refund'::text]))
);

create table if not exists public.prediction_settings (
  id integer default 1 not null,
  winner_points integer default 3 not null,
  draw_points integer default 3 not null,
  exact_score_bonus integer default 5 not null,
  deadline_minutes integer default 30 not null,
  stacking_mode text default 'exact_score_plus_winner'::text not null,
  updated_at timestamptz default now() not null,
  constraint prediction_settings_pkey primary key (id),
  constraint prediction_settings_id_check check (id = 1),
  constraint prediction_settings_stacking_mode_check check (stacking_mode = any (array['exact_score_only'::text,'exact_score_plus_winner'::text,'all_correct_predictions'::text]))
);

create table if not exists public.wc_matches (
  id text not null,
  home_id text not null,
  away_id text not null,
  kickoff_at timestamptz not null,
  stage text default 'group'::text not null,
  group_name text,
  stadium text,
  city text,
  country text,
  status text default 'upcoming'::text not null,
  home_score integer,
  away_score integer,
  is_hot boolean default false not null,
  hot_label text default '🔥 Featured Match'::text,
  bonus_multiplier numeric(4,2) default 1.0 not null,
  predictions_locked boolean default false not null,
  points_calculated boolean default false not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint wc_matches_pkey primary key (id),
  constraint wc_matches_status_check check (status = any (array['upcoming'::text,'live'::text,'completed'::text]))
);

create table if not exists public.wc_predictions (
  id uuid default gen_random_uuid() not null,
  phone text not null,
  match_id text not null,
  predicted_winner text not null,
  home_score integer default 0 not null,
  away_score integer default 0 not null,
  points_awarded integer default 0 not null,
  result_status text default 'pending'::text not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint wc_predictions_pkey primary key (id),
  constraint wc_predictions_phone_match_id_key unique (phone, match_id),
  constraint wc_predictions_predicted_winner_check check (predicted_winner = any (array['home'::text,'draw'::text,'away'::text])),
  constraint wc_predictions_result_status_check check (result_status = any (array['pending'::text,'correct_winner'::text,'correct_exact'::text,'wrong'::text,'missed'::text]))
);

create table if not exists public.loyalty_customers (
  id uuid default gen_random_uuid() not null,
  phone text not null,
  name text,
  points integer default 0 not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint loyalty_customers_pkey primary key (id),
  constraint loyalty_customers_phone_key unique (phone)
);

create table if not exists public.rewards (
  id uuid default gen_random_uuid() not null,
  phone text not null,
  user_name text,
  prize_id text not null,
  prize_name text not null,
  prize_description text,
  shop_name text default 'Don Louis'::text not null,
  shop_whatsapp text default '96181922779'::text not null,
  redeem_code text not null,
  verify_url text default ''::text not null,
  qr_code_url text default ''::text not null,
  status text default 'pending'::text not null,
  expires_at timestamptz default (now() + '7 days'::interval) not null,
  claimed_at timestamptz,
  claimed_by text,
  rejected_at timestamptz,
  rejection_reason text,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint rewards_pkey primary key (id),
  constraint rewards_redeem_code_key unique (redeem_code),
  constraint rewards_status_check check (status = any (array['pending'::text,'claimed'::text,'expired'::text,'rejected'::text]))
);

create table if not exists public.spin_wheels (
  id uuid default gen_random_uuid() not null,
  name text default 'Main Wheel'::text not null,
  title text default '🎰 Daily Spin'::text not null,
  subtitle text default 'Win prizes & points every day!'::text,
  daily_spin_limit integer default 1 not null,
  cooldown_minutes integer default 1440 not null,
  reset_rule text default 'daily'::text not null,
  active boolean default true not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint spin_wheels_pkey primary key (id),
  constraint spin_wheels_reset_rule_check check (reset_rule = any (array['daily'::text,'cooldown'::text]))
);

create table if not exists public.spin_segments (
  id uuid default gen_random_uuid() not null,
  wheel_id uuid not null,
  title text not null,
  display_label text,
  description text,
  icon text default '🎁'::text not null,
  color text default '#1a3a2a'::text not null,
  text_color text default '#D4AF37'::text not null,
  reward_type text default 'points'::text not null,
  points_value integer default 0 not null,
  prize_name text,
  prize_description text,
  chance_percentage numeric(7,2) default 10.0 not null,
  display_order integer default 0 not null,
  stock_quantity integer,
  stock_remaining integer,
  active boolean default true not null,
  start_at timestamptz,
  end_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint spin_segments_pkey primary key (id),
  constraint spin_segments_reward_type_check check (reward_type = any (array['points'::text,'prize'::text,'try_again'::text,'bonus_spin'::text,'empty'::text]))
);

create table if not exists public.spin_results (
  id uuid default gen_random_uuid() not null,
  phone text not null,
  wheel_id uuid not null,
  segment_id uuid not null,
  reward_type text not null,
  points_awarded integer default 0 not null,
  reward_id uuid,
  created_at timestamptz default now() not null,
  constraint spin_results_pkey primary key (id)
);

create table if not exists public.spin_wheel_prizes (
  label text not null,
  weight integer not null,
  reward_kind text not null,
  reward_amount integer default 0 not null,
  sort_order integer not null,
  is_active boolean default true not null,
  constraint spin_wheel_prizes_pkey primary key (label),
  constraint spin_wheel_prizes_weight_check check (weight > 0),
  constraint spin_wheel_prizes_reward_amount_check check (reward_amount >= 0),
  constraint spin_wheel_prizes_reward_kind_check check (reward_kind = any (array['coins'::text,'diamonds'::text,'none'::text]))
);

create table if not exists public.spin_wheel_spins (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  client_spin_id text,
  prize_label text not null,
  cost integer not null,
  coins_delta integer default 0 not null,
  diamonds_delta integer default 0 not null,
  created_at timestamptz default now() not null,
  constraint spin_wheel_spins_pkey primary key (id),
  constraint spin_wheel_spins_client_id_unique unique (user_id, client_spin_id)
);

create table if not exists public.fish_hunt_rounds (
  id uuid default gen_random_uuid() not null,
  room_id uuid,
  status text default 'active'::text not null,
  started_at timestamptz default now() not null,
  server_seed text default encode(gen_random_bytes(32), 'hex'::text) not null,
  created_at timestamptz default now() not null,
  constraint fish_hunt_rounds_pkey primary key (id),
  constraint fish_hunt_rounds_status_valid check (status = any (array['active'::text,'closed'::text]))
);

create table if not exists public.fish_hunt_fish (
  id uuid default gen_random_uuid() not null,
  round_id uuid not null,
  fish_type text not null,
  reward_multiplier numeric not null,
  hit_probability numeric not null,
  spawned_at timestamptz default now() not null,
  expires_at timestamptz not null,
  status text default 'alive'::text not null,
  killed_by uuid,
  created_at timestamptz default now() not null,
  constraint fish_hunt_fish_pkey primary key (id),
  constraint fish_hunt_fish_expiry_valid check (expires_at > spawned_at),
  constraint fish_hunt_fish_multiplier_positive check (reward_multiplier > (0)::numeric),
  constraint fish_hunt_fish_probability_valid check (hit_probability >= (0)::numeric and hit_probability <= (1)::numeric),
  constraint fish_hunt_fish_status_valid check (status = any (array['alive'::text,'killed'::text,'expired'::text]))
);

create table if not exists public.fish_hunt_shots (
  id uuid default gen_random_uuid() not null,
  client_shot_id text not null,
  user_id uuid not null,
  round_id uuid not null,
  fish_id uuid not null,
  bet_amount bigint not null,
  result text not null,
  payout_amount bigint default 0 not null,
  created_at timestamptz default now() not null,
  constraint fish_hunt_shots_pkey primary key (id),
  constraint fish_hunt_shots_client_shot_id_key unique (client_shot_id),
  constraint fish_hunt_shots_result_valid check (result = any (array['hit'::text,'miss'::text])),
  constraint fish_hunt_shots_bet_amount_positive check (bet_amount > 0),
  constraint fish_hunt_shots_payout_nonnegative check (payout_amount >= 0)
);

create table if not exists public.roulette_rounds (
  id uuid default gen_random_uuid() not null,
  room_id uuid,
  status text default 'betting_open'::text not null,
  winning_number integer,
  server_seed_hash text,
  started_at timestamptz default now() not null,
  betting_closes_at timestamptz not null,
  settled_at timestamptz,
  created_at timestamptz default now() not null,
  constraint roulette_rounds_pkey primary key (id),
  constraint roulette_rounds_winning_number_valid check (winning_number is null or (winning_number >= 0 and winning_number <= 36)),
  constraint roulette_rounds_status_valid check (status = any (array['betting_open'::text,'locked'::text,'spinning'::text,'settled'::text]))
);

create table if not exists public.roulette_bets (
  id uuid default gen_random_uuid() not null,
  client_bet_id text not null,
  round_id uuid not null,
  user_id uuid not null,
  bet_zone text not null,
  bet_amount bigint not null,
  payout_multiplier numeric not null,
  status text default 'active'::text not null,
  payout_amount bigint default 0 not null,
  created_at timestamptz default now() not null,
  constraint roulette_bets_pkey primary key (id),
  constraint roulette_bets_client_bet_id_key unique (client_bet_id),
  constraint roulette_bets_status_valid check (status = any (array['active'::text,'won'::text,'lost'::text,'refunded'::text])),
  constraint roulette_bets_multiplier_positive check (payout_multiplier > (0)::numeric),
  constraint roulette_bets_amount_positive check (bet_amount > 0),
  constraint roulette_bets_zone_valid check (bet_zone = any (array['straight_zero'::text,'low'::text,'mid'::text,'high'::text,'red'::text,'black'::text,'even'::text,'odd'::text])),
  constraint roulette_bets_payout_non_negative check (payout_amount >= 0)
);

-- ── Enable RLS on every reconstructed table (never disabled; policies remain
--    owned by the historical migrations that manage them) ────────────────────
do $$
declare r text;
begin
  foreach r in array array[
    'profiles','rooms','room_members','room_youtube_state','gifts','gift_transactions',
    'user_blocks','backpack_items','store_items','tasks','user_task_progress','daily_checkins',
    'game_wallets','crash_transactions','prediction_settings','wc_matches','wc_predictions',
    'loyalty_customers','rewards','spin_wheels','spin_segments','spin_results','spin_wheel_prizes',
    'spin_wheel_spins','fish_hunt_rounds','fish_hunt_fish','fish_hunt_shots','roulette_rounds','roulette_bets'
  ] loop
    execute format('alter table public.%I enable row level security', r);
  end loop;
end $$;

-- =============================================================================
-- End of baseline_manual_foundation
-- =============================================================================
