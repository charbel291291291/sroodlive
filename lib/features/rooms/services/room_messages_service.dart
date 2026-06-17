import '../../../core/supabase/supabase_service.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class RoomMessage {
  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.senderVipLevel,
    required this.senderRole,
    required this.message,
    required this.messageType,
    required this.createdAt,
    this.imageUrl,
    this.imagePath,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final int senderVipLevel;
  final String senderRole;
  final String message;
  final String messageType; // 'text' | 'system' | 'image'
  final DateTime createdAt;
  final String? imageUrl;
  final String? imagePath;

  bool get isSystem => messageType == 'system';
  bool get isImage  => messageType == 'image';

  factory RoomMessage.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return RoomMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String,
      senderName: profile?['display_name'] as String? ??
          profile?['username'] as String? ??
          'User',
      senderAvatarUrl: profile?['avatar_url'] as String?,
      senderVipLevel: (profile?['vip_level'] as int?) ?? 0,
      senderRole: (json['metadata'] as Map<String, dynamic>?)?['role']
              as String? ??
          'listener',
      message: json['message'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      createdAt: DateTime.parse(json['created_at'] as String),
      imageUrl:  json['image_url']  as String?,
      imagePath: json['image_path'] as String?,
    );
  }

  /// Create a local-only system message (not persisted).
  factory RoomMessage.local({
    required String roomId,
    required String message,
    String messageType = 'system',
  }) {
    return RoomMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      roomId: roomId,
      senderId: '',
      senderName: 'System',
      senderAvatarUrl: null,
      senderVipLevel: 0,
      senderRole: 'system',
      message: message,
      messageType: messageType,
      createdAt: DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class RoomMessagesService {
  const RoomMessagesService();

  static const int _maxMessageLength = 300;
  static const int _recentCount = 50;

  /// Fetch the most recent messages for a room (newest last).
  Future<List<RoomMessage>> fetchRecent(String roomId) async {
    try {
      final rows = await SupabaseService.requiredClient
          .from('room_messages')
          .select('*, profiles(display_name, username, avatar_url, vip_level)')
          .eq('room_id', roomId)
          .order('created_at', ascending: false)
          .limit(_recentCount)
          // image_url and image_path are returned automatically by select(*)
          ;

      return (rows as List)
          .map((r) => RoomMessage.fromJson(r as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Send a text message. Throws on error.
  Future<void> sendMessage({
    required String roomId,
    required String message,
    required String senderRole,
  }) async {
    final client = SupabaseService.requiredClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    final trimmed = message.trim();
    if (trimmed.isEmpty) throw ArgumentError('Message is empty');
    if (trimmed.length > _maxMessageLength) {
      throw ArgumentError('Message too long');
    }

    await client.from('room_messages').insert({
      'room_id': roomId,
      'sender_id': userId,
      'message': trimmed,
      'message_type': 'text',
      'metadata': {'role': senderRole},
    });
  }

  /// Send an image message via the backend RPC (validates VIP7+ server-side).
  Future<void> sendImageMessage({
    required String roomId,
    required String imageUrl,
    required String imagePath,
    required String senderRole,
  }) async {
    final client = SupabaseService.requiredClient;
    if (client.auth.currentUser == null) throw StateError('Not authenticated');

    await client.rpc('send_room_image_message', params: {
      'p_room_id':    roomId,
      'p_image_url':  imageUrl,
      'p_image_path': imagePath,
      'p_sender_role': senderRole,
    });
  }
}
