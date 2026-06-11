class RoomAnnouncement {
  const RoomAnnouncement({
    required this.id,
    required this.roomId,
    required this.createdBy,
    required this.message,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String roomId;
  final String createdBy;
  final String message;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoomAnnouncement.fromJson(Map<String, dynamic> json) =>
      RoomAnnouncement(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        createdBy: json['created_by'] as String,
        message: json['message'] as String,
        isActive: (json['is_active'] as bool?) ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'created_by': createdBy,
        'message': message,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
