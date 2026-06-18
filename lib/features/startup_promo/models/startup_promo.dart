class StartupPromo {
  const StartupPromo({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.durationSeconds,
    required this.frequency,
    required this.priority,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String imageUrl;
  final int durationSeconds;
  final String frequency;  // every_open | once_per_session | once_per_day | once_only
  final int priority;
  final DateTime updatedAt;

  factory StartupPromo.fromJson(Map<String, dynamic> json) {
    return StartupPromo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      durationSeconds: _int(json['duration_seconds'], 5),
      frequency: json['frequency']?.toString() ?? 'once_per_day',
      priority: _int(json['priority'], 0),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static int _int(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }
}

// Full admin model with all columns
class AdminStartupPromo {
  const AdminStartupPromo({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.storagePath,
    required this.isActive,
    this.startsAt,
    this.endsAt,
    required this.durationSeconds,
    required this.frequency,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String imageUrl;
  final String? storagePath;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int durationSeconds;
  final String frequency;
  final int priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AdminStartupPromo.fromJson(Map<String, dynamic> json) {
    return AdminStartupPromo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      storagePath: json['storage_path']?.toString(),
      isActive: json['is_active'] == true,
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? ''),
      durationSeconds: _int(json['duration_seconds'], 5),
      frequency: json['frequency']?.toString() ?? 'once_per_day',
      priority: _int(json['priority'], 0),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static int _int(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }
}
