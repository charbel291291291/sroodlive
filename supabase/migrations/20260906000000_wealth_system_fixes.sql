-- =============================================================================
-- Wealth system fixes
--
-- Finding 1: wealth_admin_adjustments.admin_user_id has ON DELETE SET NULL
--            but the column is NOT NULL - a contradiction that causes a FK
--            violation if the admin user is ever deleted.
--            Fix: drop the old FK and recreate with ON DELETE RESTRICT so
--            deletion of an admin who has audit rows is blocked instead of
--            trying to NULL the non-nullable column.
--
-- Finding 5: get_my_wealth_level() can return a negative level_progress when
--            an admin removes XP below the current level threshold. The
--            Flutter client already clamps, but the server should clamp too.
--            Fix: wrap the progress expression with greatest(0.0, ...).
--
-- Finding 10: add_wealth_xp() makes two separate UPDATE statements for the
--             wealth_xp column and the split counter (total_recharged_xp /
--             total_spent_gift_xp). Under concurrent gift sends the split
--             counter can lose increments.
--             Fix: atomic single UPDATE that handles both in one statement,
--             the UPDATE itself takes a row lock and prevents concurrent races.
-- =============================================================================


-- -- Finding 1: fix wealth_admin_adjustments FK --------------------------------

ALTER TABLE public.wealth_admin_adjustments
  DROP CONSTRAINT IF EXISTS wealth_admin_adjustments_admin_user_id_fkey;

ALTER TABLE public.wealth_admin_adjustments
  ADD CONSTRAINT wealth_admin_adjustments_admin_user_id_fkey
    FOREIGN KEY (admin_user_id)
    REFERENCES auth.users(id)
    ON DELETE RESTRICT;

-- Verify: admin_user_id remains NOT NULL; deletion of an admin with audit rows
-- is now blocked (RESTRICT) rather than silently setting a non-nullable column
-- to NULL (which would error anyway, but RESTRICT is explicit and safer).


-- -- Finding 10: atomic add_wealth_xp -----------------------------------------

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

  -- Ensure the row exists before locking it.
  insert into public.user_wealth (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  -- Atomic single UPDATE: accumulate XP and the correct split counter together.
  -- The atomic UPDATE row lock prevents concurrent calls from racing on
  -- either column.
  update public.user_wealth
  set wealth_xp           = wealth_xp + p_xp,
      total_recharged_xp  = case when p_source = 'recharge'
                                 then total_recharged_xp + p_xp
                                 else total_recharged_xp end,
      total_spent_gift_xp = case when p_source = 'gift_sent'
                                 then total_spent_gift_xp + p_xp
                                 else total_spent_gift_xp end,
      last_xp_at          = now(),
      updated_at          = now()
  where user_id = p_user_id
  returning wealth_xp into v_new_xp;

  -- Calculate new level from XP table.
  select level, tier_number
  into   v_new_level, v_new_tier
  from   public.wealth_level_rules
  where  required_xp <= v_new_xp
    and  is_active = true
  order  by required_xp desc
  limit  1;

  v_new_level := coalesce(v_new_level, 1);
  v_new_tier  := coalesce(v_new_tier,  1);

  update public.user_wealth
  set    wealth_level = v_new_level,
         tier_number  = v_new_tier,
         updated_at   = now()
  where  user_id = p_user_id;
end;
$$;

-- Not granted to authenticated - called only by other SECURITY DEFINER functions.


-- -- Finding 5: clamp level_progress in get_my_wealth_level -------------------

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
  -- greatest(0.0, ...) guards against negative progress when XP has been
  -- reduced by an admin below the current level's required_xp threshold.
  if v_next_rule.level is not null then
    v_band_start := v_curr_rule.required_xp;
    v_band_size  := v_next_rule.required_xp - v_band_start;
    v_progress   := case when v_band_size > 0
                         then greatest(0.0, least(1.0,
                                (v_row.wealth_xp - v_band_start)::numeric / v_band_size))
                         else 1.0 end;
  else
    v_progress := 1.0;
  end if;

  return json_build_object(
    'wealth_level',           v_row.wealth_level,
    'wealth_xp',              v_row.wealth_xp,
    'tier_number',            v_row.tier_number,
    'tier_name',              v_curr_rule.tier_name,
    'color_hex',              v_curr_rule.color_hex,
    'badge_key',              v_curr_rule.badge_key,
    'next_level',             v_next_rule.level,
    'next_level_required_xp', v_next_rule.required_xp,
    'xp_to_next_level',       case when v_next_rule.level is not null
                                   then greatest(0, v_next_rule.required_xp - v_row.wealth_xp)
                                   else null end,
    'level_progress',         v_progress,
    'total_recharged_xp',     v_row.total_recharged_xp,
    'total_spent_gift_xp',    v_row.total_spent_gift_xp,
    'last_xp_at',             to_char(v_row.last_xp_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
end;
$$;

grant execute on function public.get_my_wealth_level() to authenticated;


