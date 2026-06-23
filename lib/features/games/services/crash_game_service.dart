import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';

class CrashGameService {
  const CrashGameService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  // ── Wallet ────────────────────────────────────────────────────────────────

  Future<int> fetchBalance() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('not_authenticated');
    final data = await _client
        .from('wallets')
        .select('coins_balance')
        .eq('user_id', user.id)
        .maybeSingle();
    if (data == null) return 0;
    return (data['coins_balance'] as num).toInt();
  }

  // ── Local game RPCs (one bet per slot, JS drives the round loop) ──────────

  /// Deducts [amount] from wallet, creates a pending bet, returns
  /// `{bet_id: String, new_balance: int}`.
  Future<Map<String, dynamic>> armBet(int amount, {int slotIndex = 0}) async {
    final data = await _client.rpc(
      'arm_crash_bet',
      params: {'p_amount': amount, 'p_slot_index': slotIndex},
    ) as Map<String, dynamic>;
    return data;
  }

  /// Credits `floor(bet_amount × multiplier)` to wallet and marks the bet
  /// cashed_out. Returns `{win_amount: int, new_balance: int, multiplier: num}`.
  Future<Map<String, dynamic>> cashoutLocal(
      String betId, double multiplier) async {
    final data = await _client.rpc(
      'cashout_crash_bet_local',
      params: {
        'p_bet_id': betId,
        'p_multiplier': multiplier,
      },
    ) as Map<String, dynamic>;
    return data;
  }

  /// Refunds the full bet amount to wallet and marks the bet refunded.
  /// Returns `{refunded_amount: int, new_balance: int}`.
  Future<Map<String, dynamic>> refundBet(String betId) async {
    final data = await _client.rpc(
      'refund_crash_bet',
      params: {'p_bet_id': betId},
    ) as Map<String, dynamic>;
    return data;
  }

  /// Marks a bet as lost (no coin movement — already deducted on arm).
  Future<void> markBetLost(String betId, double crashMultiplier) async {
    await _client.rpc(
      'mark_crash_bet_lost',
      params: {
        'p_bet_id': betId,
        'p_crash_multiplier': crashMultiplier,
      },
    );
  }

  // ── Global round RPCs ─────────────────────────────────────────────────────

  /// Returns the current active round or creates a new 8-second betting window.
  /// Response: {round_id, round_number, status, betting_ends_at (epoch ms),
  ///            flight_starts_at (epoch ms | null), crash_multiplier, server_now}
  Future<Map<String, dynamic>> getOrCreateRocketRound() async {
    final data = await _client.rpc('get_or_create_rocket_crash_round')
        as Map<String, dynamic>;
    return data;
  }

  /// Places a bet during the betting phase. Returns {bet_id, new_balance}.
  Future<Map<String, dynamic>> placeRocketBet(
    String roundId,
    int amount, [
    double? autoCashoutMultiplier,
  ]) async {
    final data = await _client.rpc(
      'place_rocket_crash_bet',
      params: {
        'p_round_id':    roundId,
        'p_amount':      amount,
        'p_auto_cashout': autoCashoutMultiplier,
      },
    ) as Map<String, dynamic>;
    return data;
  }

  /// Server-calculated cashout (multiplier = exp(0.055 × elapsed_seconds)).
  /// Returns {status, cashout_multiplier, win_amount, new_balance?}.
  Future<Map<String, dynamic>> cashOutRocketBet(String betId) async {
    final data = await _client.rpc(
      'cash_out_rocket_crash_bet',
      params: {'p_bet_id': betId},
    ) as Map<String, dynamic>;
    return data;
  }

  /// Last [limit] crashed round multipliers, newest first.
  Future<List<Map<String, dynamic>>> getRocketResults({int limit = 20}) async {
    final data = await _client.rpc(
      'get_rocket_crash_recent_results',
      params: {'p_limit': limit},
    );
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }

  /// Bet feed for a round (display_name, amounts, status, is_own).
  Future<List<Map<String, dynamic>>> getRocketRoundBets(String roundId) async {
    final data = await _client.rpc(
      'get_rocket_crash_round_bets',
      params: {'p_round_id': roundId},
    );
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }

  // ── Legacy batch-round RPCs (kept for compatibility) ──────────────────────

  Future<Map<String, dynamic>> startRound(
      List<Map<String, dynamic>> bets) async {
    final data = await _client.rpc(
      'start_crash_round',
      params: {'p_bets': bets},
    ) as Map<String, dynamic>;
    return data;
  }

  Future<Map<String, dynamic>> cashOut(String betId) async {
    final data = await _client.rpc(
      'cashout_crash_bet',
      params: {'p_bet_id': betId},
    ) as Map<String, dynamic>;
    return data;
  }

  Future<List<Map<String, dynamic>>> getRecentRounds() async {
    final data = await _client.rpc(
      'get_recent_crash_rounds',
      params: {'p_limit': 20},
    );
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }
}
