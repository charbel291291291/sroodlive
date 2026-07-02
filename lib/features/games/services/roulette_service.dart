import 'dart:math';

import '../../../core/supabase/supabase_service.dart';
import '../models/roulette_models.dart';

/// Srood Roulette game service. The round lifecycle, the winning number, the
/// wallet debit/credit, and every payout are all decided server-side by
/// `advance_roulette_round` / `settle_roulette_round` — this service only
/// reads state and forwards the caller's bet via `roulette_place_bet`.
class RouletteService {
  const RouletteService();

  static final Random _random = Random.secure();

  Future<RouletteState> fetchState({String? roomId}) async {
    final raw = await SupabaseService.requiredClient.rpc(
      'roulette_get_state',
      params: {'p_room_id': roomId},
    );
    return RouletteState.fromJson(raw as Map<String, dynamic>);
  }

  Future<RoulettePlaceBetResult> placeBet({
    required String roundId,
    required String betZone,
    required int betAmount,
  }) async {
    final clientBetId = _generateClientBetId();
    final raw = await SupabaseService.requiredClient.rpc(
      'roulette_place_bet',
      params: {
        'p_round_id': roundId,
        'p_bet_zone': betZone,
        'p_bet_amount': betAmount,
        'p_client_bet_id': clientBetId,
      },
    );
    return RoulettePlaceBetResult.fromJson(raw as Map<String, dynamic>);
  }

  String _generateClientBetId() {
    final userId =
        SupabaseService.requiredClient.auth.currentUser?.id ?? 'anon';
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32);
    return 'rl_${userId}_${nowMicros}_$salt';
  }
}
