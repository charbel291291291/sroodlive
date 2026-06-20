import '../../../core/supabase/supabase_service.dart';
import '../models/wealth_models.dart';

class WealthService {
  const WealthService();

  // Returns the authenticated user's full wealth progress.
  Future<UserWealth> getMyWealth() async {
    final data = await SupabaseService.requiredClient.rpc('get_my_wealth_level');
    return UserWealth.fromJson(data as Map<String, dynamic>);
  }

  // Returns display-only wealth info for any user (badge rendering).
  Future<UserWealth> getUserWealth(String userId) async {
    final data = await SupabaseService.requiredClient.rpc(
      'get_user_wealth_level',
      params: {'p_user_id': userId},
    );
    return UserWealth.displayFromJson(data as Map<String, dynamic>);
  }

  // Fetches all 100 wealth level rules (for the tier table in WealthCenterScreen).
  Future<List<WealthLevelRule>> getWealthRules() async {
    final rows = await SupabaseService.requiredClient
        .from('wealth_level_rules')
        .select()
        .eq('is_active', true)
        .order('level', ascending: true);
    return (rows as List<dynamic>)
        .map((r) => WealthLevelRule.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
