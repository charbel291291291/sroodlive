import '../../../core/supabase/supabase_service.dart';
import '../models/srood_blocks_models.dart';

class SroodBlocksService {
  static Future<BlocksDailyStatus> getDailyStatus() async {
    final res = await SupabaseService.requiredClient
        .rpc('get_srood_blocks_daily_status');
    return BlocksDailyStatus.fromJson(res as Map<String, dynamic>);
  }

  static Future<void> startPlay({required bool isPaid}) async {
    await SupabaseService.requiredClient.rpc(
      'start_srood_blocks_play',
      params: {'p_is_paid': isPaid},
    );
  }

  static Future<BlocksSubmitResult> submitScore({
    required int score,
    required int lines,
    required int level,
    required int durationSec,
  }) async {
    final res = await SupabaseService.requiredClient.rpc(
      'submit_srood_blocks_score',
      params: {
        'p_score':        score,
        'p_lines':        lines,
        'p_level':        level,
        'p_duration_sec': durationSec,
      },
    );
    return BlocksSubmitResult.fromJson(res as Map<String, dynamic>);
  }

  static Future<List<BlocksLeaderboardEntry>> getWeeklyLeaderboard({
    int limit = 50,
  }) async {
    final res = await SupabaseService.requiredClient.rpc(
      'get_srood_blocks_weekly_leaderboard',
      params: {'p_limit': limit},
    );
    return (res as List<dynamic>)
        .map((e) => BlocksLeaderboardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
