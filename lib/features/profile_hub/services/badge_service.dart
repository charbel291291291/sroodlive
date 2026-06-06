import '../../../core/supabase/supabase_service.dart';
import '../models/profile_hub_models.dart';

class BadgeService {
  const BadgeService();

  Future<List<BadgeItem>> getBadges() async {
    final client = SupabaseService.requiredClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No logged-in user found.');
    }

    final badgesData = await client
        .from('badges')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    final ownedData = await client
        .from('user_badges')
        .select('badge_id, is_equipped')
        .eq('user_id', userId);

    final owned = <String, bool>{
      for (final item in ownedData as List<dynamic>)
        (item as Map<String, dynamic>)['badge_id'].toString():
            item['is_equipped'] == true,
    };

    return (badgesData as List<dynamic>).map((item) {
      final json = item as Map<String, dynamic>;
      final id = json['id']?.toString() ?? '';
      return BadgeItem.fromJson(
        json,
        isOwned: owned.containsKey(id),
        isEquipped: owned[id] == true,
      );
    }).toList();
  }

  Future<void> equipBadge(String badgeId) async {
    await SupabaseService.requiredClient.rpc(
      'equip_user_badge',
      params: {'p_badge_id': badgeId},
    );
  }
}
