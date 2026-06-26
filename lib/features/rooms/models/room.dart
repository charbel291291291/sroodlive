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
    this.ownerCountry,
    this.closedSeats = const [],
    this.roomCode,
    this.countryCode,
    this.roomLevel = 1,
    this.isRoomMuted = false,
    this.allowImages = true,
    this.roomXp = 0,
    this.xpToday = 0,
    this.xpWeek = 0,
    this.dailyStreak = 0,
    this.streakMultiplier = 1.0,
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
  final String? ownerCountry;
  final String? coverUrl;
  final String? backgroundUrl;
  final String? avatarUrl;
  final List<int> closedSeats;
  final String? roomCode;      // 5-digit public display code
  final String? countryCode;   // ISO 3166-1 alpha-2 (e.g. "LB", "AE")
  final int roomLevel;
  final bool isRoomMuted;
  final bool allowImages;
  final int roomXp;
  final int xpToday;
  final int xpWeek;
  final int dailyStreak;
  final double streakMultiplier;

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
      ownerCountry: (json['profiles'] as Map<String, dynamic>?)?['country']
          ?.toString(),
      closedSeats: (json['closed_seats'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      roomCode: json['public_room_code']?.toString(),
      countryCode: json['country_code']?.toString().toUpperCase().trim().isEmpty == true
          ? null
          : json['country_code']?.toString().toUpperCase().trim(),
      roomLevel: (json['room_level'] as num?)?.toInt() ?? 1,
      isRoomMuted: json['is_room_muted'] as bool? ?? false,
      allowImages: json['allow_images'] as bool? ?? true,
      roomXp: (json['room_xp'] as num?)?.toInt() ?? 0,
      xpToday: ((json['xp_today_gift'] as num? ?? 0) +
                (json['xp_today_passive'] as num? ?? 0)).toInt(),
      xpWeek: (json['xp_week'] as num?)?.toInt() ?? 0,
      dailyStreak: (json['daily_streak'] as num?)?.toInt() ?? 0,
      streakMultiplier: (json['streak_multiplier'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
