-- Preserve transaction types that predate Crash V3 when tightening the wallet
-- transaction type constraint. This forward migration is required for projects
-- where 20261111000001 has already been recorded.
alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check check (
    type = any (array[
      'credit','debit','transfer_in','transfer_out','gift_sent','gift_received',
      'purchase','reward','refund','admin_adjustment','recharge','withdrawal',
      'room_game_bet','room_game_win','room_game_refund',
      'srood_loto_ticket','srood_treasure_entry','srood_treasure_win',
      'blocks_play','daily_reward','magic_srood_bet','magic_srood_reward',
      'magic_srood_refund','fish_hunt_bet','fish_hunt_reward',
      'hungry_cat_bet','hungry_cat_reward','hungry_cat_refund',
      'gold_ladder_entry','gold_ladder_safe_payout',
      'red_envelope_sent','red_envelope_claimed','recharge_request','system',
      'roulette_bet','roulette_win','roulette_refund',
      'crash_rocket_bet','crash_rocket_win','crash_rocket_cashout',
      'crash_v3_bet','crash_v3_win',
      'crash_v3_refund','crash_v3_adjustment'
    ])
  );
