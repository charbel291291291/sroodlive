import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class LevelService {
  const LevelService();

  Future<UserLevel> getMyLevel() async {
    final data = await SupabaseService.requiredClient.rpc('get_my_level');
    return UserLevel.fromJson(data as Map<String, dynamic>);
  }

  Future<List<LevelRule>> getLevelRules() async {
    final data = await SupabaseService.requiredClient
        .from('level_rules')
        .select()
        .eq('is_active', true)
        .order('level', ascending: true);

    return (data as List<dynamic>)
        .map((item) => LevelRule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<UserLevel> addXp(int xp, {String? source}) async {
    final userId = SupabaseService.requiredClient.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    final data = await SupabaseService.requiredClient.rpc(
      'add_user_xp',
      params: {'p_user_id': userId, 'p_xp': xp, 'p_source': source},
    );
    return UserLevel.fromJson(data as Map<String, dynamic>);
  }

  LevelRule? getNextLevel(UserLevel level, List<LevelRule> rules) {
    for (final rule in rules) {
      if (rule.requiredXp > level.xp) {
        return rule;
      }
    }

    return null;
  }

  int calculateLevelFromXp(int xp, List<LevelRule> rules) {
    var result = 1;
    for (final rule in rules) {
      if (xp >= rule.requiredXp) {
        result = rule.level;
      }
    }
    return result;
  }
}
