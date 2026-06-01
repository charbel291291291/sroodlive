class RoomMember {
  const RoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    required this.isMuted,
    required this.joinedAt,
    this.seatNumber,
    this.leftAt,
  });

  final String id;
  final String roomId;
  final String userId;
  final String role;
  final int? seatNumber;
  final bool isMuted;
  final DateTime joinedAt;
  final DateTime? leftAt;

  factory RoomMember.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
