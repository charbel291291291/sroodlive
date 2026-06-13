import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_service.dart';

class CrashGameService {
  const CrashGameService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  // Reads from the real unified Srood wallet — not game_wallets.
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

  Future<Map<String, dynamic>> getRoundResult(String roundId) async {
    final data = await _client.rpc(
      'get_crash_round_status',
      params: {'p_round_id': roundId},
    ) as Map<String, dynamic>;
    return data;
  }

  Future<List<Map<String, dynamic>>> getRecentRounds() async {
    final data = await _client.rpc(
      'get_recent_crash_rounds',
      params: {'p_limit': 20},
    );
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }
}
