import 'package:flutter/foundation.dart';
import '../../../core/supabase/supabase_service.dart';
import '../models/gold_ladder_models.dart';

/// All wallet changes go through Supabase RPCs — this service never touches
/// balances directly. Correct answers are not returned until after the player
/// has answered (enforced by the RPC).
class GoldLadderQuizService {
  const GoldLadderQuizService();

  Future<bool> isGameEnabled() async {
    try {
      final data = await SupabaseService.requiredClient
          .from('game_settings')
          .select('is_enabled')
          .eq('game_key', 'gold_ladder')
          .maybeSingle();
      return data == null || data['is_enabled'] == true;
    } catch (e) {
      if (kDebugMode) debugPrint('[GoldLadderQuizService] isGameEnabled: $e');
      return true;
    }
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

  Future<GoldLadderRunStarted> startRun({required int entryFee}) async {
    final data = await SupabaseService.requiredClient.rpc(
      'start_gold_ladder_run',
      params: {'p_entry_fee': entryFee},
    );
    return GoldLadderRunStarted.fromJson(data as Map<String, dynamic>);
  }

  Future<GoldLadderAnswerResult> answerQuestion({
    required String runId,
    required String questionId,
    required String selectedOption,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'answer_gold_ladder_question',
      params: {
        'p_run_id': runId,
        'p_question_id': questionId,
        'p_selected_option': selectedOption,
      },
    );
    return GoldLadderAnswerResult.fromJson(data as Map<String, dynamic>);
  }

  Future<GoldLadderPowerResult> usePower({
    required String runId,
    required String questionId,
    required String powerType,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'use_gold_ladder_power',
      params: {
        'p_run_id': runId,
        'p_question_id': questionId,
        'p_power_type': powerType,
      },
    );
    return GoldLadderPowerResult.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> cashoutRun({required String runId}) async {
    final data = await SupabaseService.requiredClient.rpc(
      'cashout_gold_ladder_run',
      params: {'p_run_id': runId},
    );
    return data as Map<String, dynamic>;
  }

  Future<List<GoldLadderWinner>> fetchRecentWinners({int limit = 10}) async {
    try {
      final data = await SupabaseService.requiredClient.rpc(
        'get_gold_ladder_recent_winners',
        params: {'p_limit': limit},
      );
      return (data as List<dynamic>)
          .map((e) => GoldLadderWinner.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[GoldLadderQuizService] fetchRecentWinners: $e');
      return [];
    }
  }
}
