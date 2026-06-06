class Room {
  const Room({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.livekitRoomName,
    required this.maxSeats,
    required this.isPrivate,
    required this.isLocked,
    required this.isClosed,
    required this.createdAt,
    this.description,
    this.language = 'ar',
  });

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String language;
  final String livekitRoomName;
  final int maxSeats;
  final bool isPrivate;
  final bool isLocked;
  final bool isClosed;
  final DateTime createdAt;

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'].toString(),
      ownerId: json['owner_id'].toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      language: json['language']?.toString() ?? 'ar',
      livekitRoomName: json['livekit_room_name']?.toString() ?? '',
      maxSeats: json['max_seats'] as int? ?? 12,
      isPrivate: json['is_private'] as bool? ?? false,
      isLocked: json['is_locked'] as bool? ?? false,
      isClosed: json['is_closed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}
