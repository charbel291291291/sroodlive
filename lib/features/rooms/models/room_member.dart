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

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    String? resolvedName;

    if (profile is Map<String, dynamic>) {
      resolvedName =
          profile['display_name']?.toString() ??
          profile['full_name']?.toString() ??
          profile['username']?.toString() ??
          profile['name']?.toString();
    }

    resolvedName ??= json['display_name']?.toString();

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
    );
  }

  String fallbackName(bool isArabic) {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim();
    }

    final shortId = userId.length >= 8 ? userId.substring(0, 8) : userId;
    return isArabic ? '?????? $shortId' : 'User $shortId';
  }
}
