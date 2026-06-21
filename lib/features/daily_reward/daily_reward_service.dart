import '../../core/supabase/supabase_service.dart';
import 'daily_reward_models.dart';

/// Thin wrapper over the daily-reward RPCs. All claim/admin logic is enforced
/// server-side (SECURITY DEFINER); this client only reads state and triggers
/// the RPCs.
class DailyRewardService {
  const DailyRewardService();

  Future<DailyRewardState> getState() async {
    final data =
        await SupabaseService.requiredClient.rpc('get_daily_reward_state');
    return DailyRewardState.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DailyRewardClaimResult> claim() async {
    final data =
        await SupabaseService.requiredClient.rpc('claim_daily_reward');
    return DailyRewardClaimResult.fromJson(
        Map<String, dynamic>.from(data as Map));
  }

  // ── Admin ──────────────────────────────────────────────────────────────────
  Future<void> adminSetConfig({
    required bool enabled,
    required bool popupEnabled,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_daily_reward_config',
      params: {'p_enabled': enabled, 'p_popup_enabled': popupEnabled},
    );
  }

  Future<void> adminUpsertRule({
    required int dayNumber,
    required bool enabled,
    required String rewardType,
    required String title,
    String? description,
    required int amount,
    int? durationDays,
    String? imageUrl,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_upsert_daily_reward_rule',
      params: {
        'p_day_number': dayNumber,
        'p_enabled': enabled,
        'p_reward_type': rewardType,
        'p_title': title,
        'p_description': description,
        'p_amount': amount,
        'p_duration_days': durationDays,
        'p_image_url': imageUrl,
      },
    );
  }
}
