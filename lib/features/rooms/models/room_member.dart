import '../utils/vip_room_features.dart';

class RoomMember {
  const RoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    required this.isMuted,
    this.seatNumber,
    required this.joinedAt,
    this.leftAt,
    this.displayName,
    this.username,
    this.publicUserId,
    this.avatarUrl,
    this.selectedAvatarFrameKey,
    this.vipLevel = 0,
    this.vipStartedAt,
    this.vipExpiresAt,
  });

  final String id;
  final String roomId;
  final String userId;
  final String role;
  final int? seatNumber;
  final bool isMuted;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final String? displayName;
  final String? username;
  final String? publicUserId;
  final String? avatarUrl;
  final String? selectedAvatarFrameKey;
  final int vipLevel;
  final DateTime? vipStartedAt;
  final DateTime? vipExpiresAt;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    String? resolvedName;

    if (profile is Map<String, dynamic>) {
      resolvedName =
          profile['display_name']?.toString() ??
          profile['username']?.toString();
    }

    resolvedName ??= json['display_name']?.toString();
    final resolvedUsername = profile is Map<String, dynamic>
        ? profile['username']?.toString()
        : json['username']?.toString();
    final resolvedPublicUserId = profile is Map<String, dynamic>
        ? profile['public_user_id']?.toString()
        : json['public_user_id']?.toString();
    final resolvedAvatarUrl = profile is Map<String, dynamic>
        ? profile['avatar_url']?.toString()
        : json['avatar_url']?.toString();
    final resolvedFrameKey = profile is Map<String, dynamic>
        ? profile['selected_avatar_frame_key']?.toString()
        : json['selected_avatar_frame_key']?.toString();
    final resolvedVipLevel = profile is Map<String, dynamic>
        ? (profile['vip_level'] as num?)?.toInt() ?? 0
        : (json['vip_level'] as num?)?.toInt() ?? 0;
    final resolvedVipStartedAt = profile is Map<String, dynamic>
        ? _parseDate(profile['vip_started_at'])
        : _parseDate(json['vip_started_at']);
    final resolvedVipExpiresAt = profile is Map<String, dynamic>
        ? _parseDate(profile['vip_expires_at'])
        : _parseDate(json['vip_expires_at']);

    return RoomMember(
      id: json['id'].toString(),
      roomId: json['room_id'].toString(),
      userId: json['user_id'].toString(),
      role: json['role']?.toString() ?? 'listener',
      seatNumber: json['seat_number'] as int?,
      isMuted: json['is_muted'] as bool? ?? false,
      joinedAt: DateTime.parse(json['joined_at'].toString()),
      leftAt: json['left_at'] == null
          ? null
          : DateTime.parse(json['left_at'].toString()),
      displayName: resolvedName,
      username: resolvedUsername,
      publicUserId: resolvedPublicUserId,
      avatarUrl: resolvedAvatarUrl,
      selectedAvatarFrameKey: resolvedFrameKey,
      vipLevel: resolvedVipLevel,
      vipStartedAt: resolvedVipStartedAt,
      vipExpiresAt: resolvedVipExpiresAt,
    );
  }

  int get effectiveVipLevel {
    return VipFeatures.effectiveVipLevel(
      vipLevel: vipLevel,
      vipExpiresAt: vipExpiresAt,
    );
  }

  String fallbackName(bool isArabic) {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim();
    }

    final shortId = userId.length >= 8 ? userId.substring(0, 8) : userId;
    return isArabic
        ? '\u0645\u0633\u062a\u062e\u062f\u0645 $shortId'
        : 'User $shortId';
  }

  String get displayCode {
    final code = publicUserId?.trim();

    if (code != null && code.isNotEmpty) {
      return code;
    }

    final shortId = userId.length >= 8 ? userId.substring(0, 8) : userId;
    return 'ID $shortId';
  }
}
