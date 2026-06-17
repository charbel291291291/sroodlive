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
    this.coverUrl,
    this.backgroundUrl,
    this.avatarUrl,
    this.roomPinEnabled = false,
    this.isPersonalRoom = false,
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
  final bool roomPinEnabled;
  final bool isPersonalRoom;
  final DateTime createdAt;
  final String? coverUrl;
  final String? backgroundUrl;
  final String? avatarUrl;

  factory Room.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawOwnerId = json['owner_id'];
    return Room(
      id: rawId != null ? rawId.toString() : '',
      ownerId: rawOwnerId != null ? rawOwnerId.toString() : '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      language: json['language']?.toString() ?? 'ar',
      livekitRoomName: json['livekit_room_name']?.toString() ?? '',
      maxSeats: json['max_seats'] as int? ?? 12,
      isPrivate: json['is_private'] as bool? ?? false,
      isLocked: json['is_locked'] as bool? ?? false,
      isClosed: json['is_closed'] as bool? ?? false,
      roomPinEnabled: json['room_pin_enabled'] as bool? ?? false,
      isPersonalRoom: json['is_personal_room'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      coverUrl: json['cover_url']?.toString(),
      backgroundUrl: json['background_url']?.toString(),
      avatarUrl: json['room_avatar_url']?.toString(),
    );
  }
}
