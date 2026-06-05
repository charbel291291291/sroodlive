import '../../../core/supabase/supabase_service.dart';

class FollowService {
  const FollowService();

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
