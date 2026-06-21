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

    await client.from('user_follows').upsert(
      {'follower_id': user.id, 'following_id': targetUserId},
      ignoreDuplicates: true,
    );
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

  /// Counts mutual follows (friends) for [userId].
  Future<int> friendsCount(String userId) async {
    try {
      final client = SupabaseService.requiredClient;
      final followingData = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', userId);
      final followingIds =
          (followingData as List<dynamic>).map((e) => e['following_id'] as String).toSet();
      if (followingIds.isEmpty) return 0;
      return await client
          .from('user_follows')
          .count()
          .eq('following_id', userId)
          .inFilter('follower_id', followingIds.toList());
    } catch (_) {
      return 0;
    }
  }

  Future<int> _safeCount({
    required String column,
    required String value,
  }) async {
    try {
      final rows = await SupabaseService.requiredClient
          .from('user_follows')
          .select('follower_id')
          .eq(column, value);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Loads a relationship list for [userId] via the server-side RPC, which
  /// resolves followers/following/friends from user_follows and returns only
  /// public profile fields (same data source as the counts). [kind] is one of
  /// 'followers', 'following', 'friends'.
  Future<List<FollowUser>> getFollowList(String userId, String kind) async {
    final data = await SupabaseService.requiredClient.rpc(
      'get_follow_list',
      params: {'p_user_id': userId, 'p_kind': kind},
    );
    return (data as List<dynamic>)
        .map((e) => FollowUser.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

/// One entry in a followers/following/friends list (public fields only).
class FollowUser {
  FollowUser({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.publicUserId,
    this.gender,
    this.vipLevel = 0,
    this.viewerFollows = false,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? publicUserId;
  final String? gender;
  final int vipLevel;
  bool viewerFollows;

  factory FollowUser.fromJson(Map<String, dynamic> j) => FollowUser(
    id: j['id']?.toString() ?? '',
    displayName: (j['display_name'] as String?)?.trim().isNotEmpty == true
        ? j['display_name'] as String
        : 'User',
    avatarUrl: j['avatar_url'] as String?,
    publicUserId: j['public_user_id']?.toString(),
    gender: j['gender']?.toString(),
    vipLevel: (j['vip_level'] as int?) ?? 0,
    viewerFollows: j['viewer_follows'] == true,
  );
}
