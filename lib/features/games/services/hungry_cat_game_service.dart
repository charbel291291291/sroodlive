import '../../../core/supabase/supabase_service.dart';
import '../models/hungry_cat_models.dart';

/// All wallet changes go through the `play_hungry_cat_spin` RPC — the server
/// deducts the bet, picks the weighted random food, credits the reward, and
/// records the spin atomically. This service never touches balances directly.
class HungryCatGameService {
  const HungryCatGameService();

  Future<bool> isGameEnabled() async {
    try {
      final data = await SupabaseService.requiredClient
          .from('game_settings')
          .select('is_enabled')
          .eq('game_key', 'hungry_cat')
          .maybeSingle();
      return data == null || data['is_enabled'] == true;
    } catch (_) {
      // If the settings table is unreachable, fail open for reads — the RPC
      // re-checks the flag server-side before any money moves.
      return true;
    }
  }

  Future<List<HungryCatFood>> fetchFoodConfig() async {
    final data = await SupabaseService.requiredClient
        .from('hungry_cat_config')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return (data as List<dynamic>)
        .map((e) => HungryCatFood.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> fetchCoinBalance() async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) return 0;
    final data = await SupabaseService.requiredClient
        .from('wallets')
        .select('coins_balance')
        .eq('user_id', userId)
        .maybeSingle();
    return (data?['coins_balance'] as int?) ?? 0;
  }

  Future<List<HungryCatHistoryEntry>> fetchRecentSpins({
    int limit = 20,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'get_hungry_cat_history',
      params: {'p_limit': limit},
    );
    final rows = data as List<dynamic>;
    return rows
        .map((e) =>
            HungryCatHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<HungryCatSpinResult> playSpin({
    required int betAmount,
    required String clientSpinId,
    String? roomId,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'play_hungry_cat_spin',
      params: {
        'p_bet_amount': betAmount,
        'p_client_spin_id': clientSpinId,
        'p_room_id': roomId,
      },
    );

    final rows = data as List<dynamic>;
    if (rows.isEmpty) {
      throw Exception('empty_spin_result');
    }
    return HungryCatSpinResult.fromJson(rows.first as Map<String, dynamic>);
  }

  // ── Betting round methods ────────────────────────────────────────────────────

  Future<HungryCatRoundInfo> startRound() async {
    final data = await SupabaseService.requiredClient
        .rpc('start_hungry_cat_round') as Map<String, dynamic>;
    return HungryCatRoundInfo.fromJson(data);
  }

  Future<Map<String, dynamic>> placeBet({
    required String roundId,
    required String foodId,
    required int amount,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'place_hungry_cat_bet',
      params: {
        'p_round_id': roundId,
        'p_food_id': foodId,
        'p_amount': amount,
      },
    ) as Map<String, dynamic>;
    return data;
  }

  Future<Map<String, dynamic>> refundRoundBets({
    required String roundId,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'refund_hungry_cat_round_bets',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    return data;
  }

  Future<HungryCatRoundResult> settleRound({
    required String roundId,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'settle_hungry_cat_round',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    return HungryCatRoundResult.fromJson(data);
  }

  Future<List<HungryCatHistoryEntry>> fetchRecentRounds({
    int limit = 20,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'get_hungry_cat_recent_rounds',
      params: {'p_limit': limit},
    );
    final rows = data as List<dynamic>;
    return rows
        .map((e) =>
            HungryCatHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Global round methods ─────────────────────────────────────────────────────

  Future<HungryCatGlobalRound> getOrCreateRound() async {
    final data = await SupabaseService.requiredClient
        .rpc('get_or_create_hungry_cat_round') as Map<String, dynamic>;
    return HungryCatGlobalRound.fromJson(data);
  }

  Future<int> placeGlobalBet({
    required String roundId,
    required String foodId,
    required int amount,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'place_hungry_cat_global_bet',
      params: {
        'p_round_id': roundId,
        'p_food_id':  foodId,
        'p_amount':   amount,
      },
    ) as Map<String, dynamic>;
    return (data['new_balance'] as int?) ?? 0;
  }

  Future<HungryCatGlobalRound> settleGlobalRound(String roundId) async {
    final data = await SupabaseService.requiredClient.rpc(
      'settle_hungry_cat_global_round',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    // settle RPC returns the settled round without betting_ends_at/server_now,
    // so we normalise missing fields
    return HungryCatGlobalRound(
      roundId:           data['round_id']?.toString() ?? roundId,
      roundNumber:       0,
      status:            data['status']?.toString() ?? 'settled',
      bettingEndsAt:     DateTime.now().toUtc(),
      serverNow:         DateTime.parse(data['server_now'] as String).toUtc(),
      winningFoodId:     data['winning_food_id']?.toString(),
      winningFoodIcon:   data['winning_food_icon']?.toString(),
      winningFoodName:   data['winning_food_name']?.toString(),
      winningMultiplier: data['winning_multiplier'] == null
          ? null
          : (data['winning_multiplier'] as num).toDouble(),
    );
  }

  Future<List<HungryCatHistoryEntry>> getGlobalHistory({
    int limit = 20,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'get_hungry_cat_global_history',
      params: {'p_limit': limit},
    );
    final rows = data as List<dynamic>;
    return rows
        .map((e) => HungryCatHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
