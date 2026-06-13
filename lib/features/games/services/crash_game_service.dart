import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_service.dart';

class CrashGameService {
  const CrashGameService();

  SupabaseClient get _client => SupabaseService.requiredClient;

  Future<int> fetchBalance() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('not_authenticated');
    final data = await _client
        .from('game_wallets')
        .select('coins')
        .eq('user_id', user.id)
        .maybeSingle();
    if (data == null) return 0;
    return (data['coins'] as num).toInt();
  }

  Future<Map<String, dynamic>> startRound(
      List<Map<String, dynamic>> bets) async {
    final response = await _client.functions.invoke(
      'start_crash_round',
      body: {'bets': bets},
    );
    if (response.status != 200) {
      final d = response.data;
      final msg = (d is Map ? d['error'] as String? : null) ?? 'Failed to start round';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> cashOut(String betId) async {
    final response = await _client.functions.invoke(
      'cash_out_crash_round',
      body: {'bet_id': betId},
    );
    if (response.status != 200) {
      final d = response.data;
      final msg = (d is Map ? d['error'] as String? : null) ?? 'Cash out failed';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getRoundResult(String roundId) async {
    final response = await _client.functions.invoke(
      'get_crash_round_result',
      body: {'round_id': roundId},
    );
    if (response.status != 200) throw Exception('get_result_failed');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getRecentRounds() async {
    final response =
        await _client.functions.invoke('get_recent_crash_rounds');
    if (response.status != 200) return [];
    final data = response.data;
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }
}
