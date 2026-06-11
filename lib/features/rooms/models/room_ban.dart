class RoomBan {
  const RoomBan({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.bannedBy,
    required this.createdAt,
    this.reason,
    this.expiresAt,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String roomId;
  final String userId;
  final String bannedBy;
  final String? reason;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final String? displayName;
  final String? avatarUrl;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isPermanent => expiresAt == null;

  factory RoomBan.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return RoomBan(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      bannedBy: json['banned_by'] as String,
      reason: json['reason'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      displayName: profile?['display_name'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'user_id': userId,
        'banned_by': bannedBy,
        'reason': reason,
        'expires_at': expiresAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
