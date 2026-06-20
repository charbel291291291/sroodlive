import '../../../core/config/supabase_config.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../wealth/services/wealth_service.dart';
import '../models/room_user_profile.dart';
import 'follow_service.dart';

class RoomUserProfileService {
  const RoomUserProfileService();

  static const FollowService _followService = FollowService();
  static const WealthService _wealthService = WealthService();

  Future<RoomUserProfile> fetchUserProfile(String userId) async {
    final client = SupabaseService.requiredClient;
    final data = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    final followers = await _followService.followersCount(userId);
    final following = await _followService.followingCount(userId);
    final gifts = await _safeCount(
      table: 'gift_transactions',
      column: 'receiver_id',
      value: userId,
    );

    // Fetch wealth level for badge display (non-fatal - defaults to level 1).
    int wealthLevel = 1;
    int wealthTierNumber = 1;
    try {
      final w = await _wealthService.getUserWealth(userId);
      wealthLevel = w.wealthLevel;
      wealthTierNumber = w.tierNumber;
    } catch (_) {}

    return RoomUserProfile(
      userId: userId,
      nickname: _safeDisplayName(data),
      publicUserId: data?['public_user_id']?.toString() ?? '',
      avatarUrl: data?['avatar_url']?.toString(),
      selectedAvatarFrame: data?['selected_avatar_frame_key']?.toString(),
      bio: data?['bio']?.toString(),
      country: data?['country']?.toString(),
      vipLevel: data?['vip_level'] as int? ?? 0,
      vipExpiresAt: data?['vip_expires_at'] != null
          ? DateTime.tryParse(data!['vip_expires_at'].toString())
          : null,
      isGoldenId: data?['is_golden_id'] == true,
      goldenIdExpiresAt: data?['golden_id_expires_at'] != null
          ? DateTime.tryParse(data!['golden_id_expires_at'].toString())
          : null,
      goldenIdStyle: data?['golden_id_style']?.toString() ?? 'gold',
      goldenIdFrame: data?['golden_id_frame']?.toString() ?? 'classic',
      followersCount: followers,
      followingCount: following,
      giftReceivedCount: gifts,
      charmScore: gifts,
      nobleLevel: 0,
      wealthLevel: wealthLevel,
      wealthTierNumber: wealthTierNumber,
      isFollowedByMe: await _followService.isFollowing(userId),
    );
  }

  Future<bool> isFollowing(String targetUserId) async {
    return _followService.isFollowing(targetUserId);
  }

  Future<void> followUser(String targetUserId) async {
    await _followService.followUser(targetUserId);
  }

  Future<void> unfollowUser(String targetUserId) async {
    await _followService.unfollowUser(targetUserId);
  }

  Future<void> createReminder(String targetUserId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    if (user.id == targetUserId) {
      return;
    }

    await client.from('user_reminders').insert({
      'from_user_id': user.id,
      'to_user_id': targetUserId,
    });
  }

  Future<List<GiftWallItem>> fetchGiftWall(
    String userId, {
    int limit = 3,
  }) async {
    final client = SupabaseService.requiredClient;

    try {
      final data = await client
          .from('gift_transactions')
          .select('gift_code, gift_name')
          .eq('receiver_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List<dynamic>).map((item) {
        final row = item as Map<String, dynamic>;
        final code = row['gift_code']?.toString() ?? '';

        return GiftWallItem(
          giftCode: code,
          giftName: row['gift_name']?.toString() ?? 'Gift',
          imageUrl: _giftImageUrl(code),
          count: 1,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> _safeCount({
    required String table,
    required String column,
    required String value,
  }) async {
    try {
      final response = await SupabaseService.requiredClient
          .from(table)
          .count()
          .eq(column, value);

      return response;
    } catch (_) {
      return 0;
    }
  }


  String _safeDisplayName(Map<String, dynamic>? profile) {
    final displayName = profile?['display_name']?.toString().trim();
    final fullName = profile?['full_name']?.toString().trim();
    final username = profile?['username']?.toString().trim();

    if (displayName != null && displayName.isNotEmpty) return displayName;
    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (username != null && username.isNotEmpty) return username;

    return 'Unknown user';
  }

  String? _giftImageUrl(String code) {
    if (code.trim().isEmpty) {
      return null;
    }

    return SupabaseConfig.getPublicStorageUrl('gift-assets', '$code.png');
  }
}
