class RoomModerator {
  const RoomModerator({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.createdBy,
    required this.canManageMics,
    required this.canMute,
    required this.canKick,
    required this.canManageSchedule,
    required this.createdAt,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String roomId;
  final String userId;
  final String createdBy;
  final bool canManageMics;
  final bool canMute;
  final bool canKick;
  final bool canManageSchedule;
  final DateTime createdAt;
  final String? displayName;
  final String? avatarUrl;

  factory RoomModerator.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return RoomModerator(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      createdBy: json['created_by'] as String,
      canManageMics: (json['can_manage_mics'] as bool?) ?? true,
      canMute: (json['can_mute'] as bool?) ?? true,
      canKick: (json['can_kick'] as bool?) ?? false,
      canManageSchedule: (json['can_manage_schedule'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      displayName: profile?['display_name'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'user_id': userId,
        'created_by': createdBy,
        'can_manage_mics': canManageMics,
        'can_mute': canMute,
        'can_kick': canKick,
        'can_manage_schedule': canManageSchedule,
        'created_at': createdAt.toIso8601String(),
      };

  RoomModerator copyWith({
    bool? canManageMics,
    bool? canMute,
    bool? canKick,
    bool? canManageSchedule,
  }) =>
      RoomModerator(
        id: id,
        roomId: roomId,
        userId: userId,
        createdBy: createdBy,
        canManageMics: canManageMics ?? this.canManageMics,
        canMute: canMute ?? this.canMute,
        canKick: canKick ?? this.canKick,
        canManageSchedule: canManageSchedule ?? this.canManageSchedule,
        createdAt: createdAt,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
}
