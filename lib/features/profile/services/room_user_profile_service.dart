import '../../../core/config/supabase_config.dart';
import '../../../core/supabase/supabase_service.dart';
import '../models/room_user_profile.dart';
import 'follow_service.dart';

class RoomUserProfileService {
  const RoomUserProfileService();

  static const FollowService _followService = FollowService();

  Future<RoomUserProfile> fetchUserProfile(String userId) async {
    final client = SupabaseService.requiredClient;
    final data = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();

    final followers = await _followService.followersCount(userId);
    final following = await _followService.followingCount(userId);
    final gifts = await _safeCount(
      table: 'gift_transactions',
      column: 'receiver_id',
      value: userId,
    );

    return RoomUserProfile(
      userId: userId,
      nickname: data['display_name']?.toString().trim().isNotEmpty == true
          ? data['display_name'].toString()
          : (data['username']?.toString().trim().isNotEmpty == true
                ? data['username'].toString()
                : _fallbackUserLabel(userId)),
      publicUserId:
          data['public_user_id']?.toString() ?? _fallbackUserLabel(userId),
      avatarUrl: data['avatar_url']?.toString(),
      selectedAvatarFrame: data['selected_avatar_frame_key']?.toString(),
      bio: data['bio']?.toString(),
      dateOfBirth: data['date_of_birth']?.toString(),
      country: data['country']?.toString(),
      gender: data['gender']?.toString(),
      vipLevel: (data['vip_level'] as num?)?.toInt() ?? 0,
      vipStartedAt: _parseDate(data['vip_started_at']),
      vipExpiresAt: _parseDate(data['vip_expires_at']),
      isGoldenId: data['is_golden_id'] == true,
      goldenIdExpiresAt: _parseDate(data['golden_id_expires_at']),
      followersCount: followers,
      followingCount: following,
      friendsCount: 0,
      giftReceivedCount: gifts,
      charmScore: gifts,
      nobleLevel: 0,
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

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }

  String _fallbackUserLabel(String userId) {
    final shortId = userId.length >= 8 ? userId.substring(0, 8) : userId;
    return 'ID $shortId';
  }

  String? _giftImageUrl(String code) {
    if (code.trim().isEmpty) {
      return null;
    }

    return SupabaseConfig.getPublicStorageUrl('gift-assets', '$code.png');
  }
}
