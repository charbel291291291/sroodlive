import 'package:flutter/foundation.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../moderation/services/moderation_service.dart';

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
    this.isRemoved = false,
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
  final bool isRemoved;

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
      senderVipLevel: _effectiveSenderVipLevel(profile),
      senderRole: (json['metadata'] as Map<String, dynamic>?)?['role']
              as String? ??
          'listener',
      message: json['message'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      createdAt: DateTime.parse(json['created_at'] as String),
      imageUrl:  json['image_url']  as String?,
      imagePath: json['image_path'] as String?,
      isRemoved: json['is_removed'] as bool? ?? false,
    );
  }

  RoomMessage copyWithRemoved() => RoomMessage(
    id: id, roomId: roomId, senderId: senderId, senderName: senderName,
    senderAvatarUrl: senderAvatarUrl, senderVipLevel: senderVipLevel,
    senderRole: senderRole, message: message, messageType: messageType,
    createdAt: createdAt, imageUrl: imageUrl, imagePath: imagePath,
    isRemoved: true,
  );

  static int _effectiveSenderVipLevel(Map<String, dynamic>? profile) {
    final level = (profile?['vip_level'] as int?) ?? 0;
    if (level <= 0) return 0;
    final expiresRaw = profile?['vip_expires_at']?.toString();
    if (expiresRaw == null) return level;
    final expires = DateTime.tryParse(expiresRaw);
    if (expires == null) return level;
    return expires.isAfter(DateTime.now()) ? level : 0;
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
          .select('*, profiles(display_name, username, avatar_url, vip_level, vip_expires_at)')
          .eq('room_id', roomId)
          .eq('is_removed', false)
          .order('created_at', ascending: false)
          .limit(_recentCount);

      return (rows as List)
          .map((r) => RoomMessage.fromJson(r as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } catch (e, st) {
      debugError('RoomMessagesService.fetchRecent', e, st);
      return [];
    }
  }

  /// Send a text message. Throws on error.
  /// Throws [UserMutedException] if the user has an active mute/ban.
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

    // Server-side mute check before sending.
    final muteInfo = await const ModerationService().checkActiveMute(roomId);
    if (muteInfo != null) {
      throw UserMutedException(muteInfo);
    }

    await client.from('room_messages').insert({
      'room_id': roomId,
      'sender_id': userId,
      'message': trimmed,
      'message_type': 'text',
      'metadata': {'role': senderRole},
    });
  }

  /// Mark a message as removed (admin / room owner / moderator only).
  Future<void> removeMessage(String messageId, {String? reason}) async {
    await SupabaseService.requiredClient.rpc('remove_room_message', params: {
      'p_message_id': messageId,
      'p_reason': reason,
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

    debugPrint('[RoomImage] rpc send_room_image_message start room=$roomId path=$imagePath role=$senderRole');
    await client.rpc('send_room_image_message', params: {
      'p_room_id':    roomId,
      'p_image_url':  imageUrl,
      'p_image_path': imagePath,
      'p_sender_role': senderRole,
    });
    debugPrint('[RoomImage] rpc send_room_image_message success');
  }
}
