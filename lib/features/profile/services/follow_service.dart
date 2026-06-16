import '../../../core/supabase/supabase_service.dart';
import '../../vip/services/vip_privilege_service.dart';

class FollowService {
  const FollowService();

  static const _vipSvc = VipPrivilegeService();

  Future<bool> isFollowing(String targetUserId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null || user.id == targetUserId) {
      return false;
    }

    try {
      final data = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', user.id)
          .eq('following_id', targetUserId)
          .maybeSingle();

      return data != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> followUser(String targetUserId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    if (user.id == targetUserId) {
      throw StateError('Cannot follow yourself.');
    }

    // Respect "Not being Followed" VIP privilege.
    final blocked = await _vipSvc.isFollowBlocked(targetUserId);
    if (blocked) {
      throw StateError('follow_blocked_by_vip');
    }

    await client.from('user_follows').upsert({
      'follower_id': user.id,
      'following_id': targetUserId,
    });
  }

  Future<void> unfollowUser(String targetUserId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    if (user.id == targetUserId) {
      return;
    }

    await client
        .from('user_follows')
        .delete()
        .eq('follower_id', user.id)
        .eq('following_id', targetUserId);
  }

  /// Returns true if [targetUserId] follows the current user (they follow ME).
  Future<bool> isFollowedBy(String targetUserId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null || user.id == targetUserId) return false;
    try {
      final data = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', targetUserId)
          .eq('following_id', user.id)
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  /// Returns true only when BOTH users follow each other (mutual / friends).
  Future<bool> isMutualFollow(String targetUserId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null || user.id == targetUserId) return false;
    try {
      final meFollowsThem = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', user.id)
          .eq('following_id', targetUserId)
          .maybeSingle();
      if (meFollowsThem == null) return false;
      final themFollowsMe = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', targetUserId)
          .eq('following_id', user.id)
          .maybeSingle();
      return themFollowsMe != null;
    } catch (_) {
      return false;
    }
  }

  Future<int> followersCount(String userId) {
    return _safeCount(column: 'following_id', value: userId);
  }

  Future<int> followingCount(String userId) {
    return _safeCount(column: 'follower_id', value: userId);
  }

  Future<int> _safeCount({
    required String column,
    required String value,
  }) async {
    try {
      return await SupabaseService.requiredClient
          .from('user_follows')
          .count()
          .eq(column, value);
    } catch (_) {
      return 0;
    }
  }
}
