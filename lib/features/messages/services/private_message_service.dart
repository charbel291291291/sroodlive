import '../../../core/supabase/supabase_service.dart';
import '../models/private_conversation.dart';
import '../models/private_message.dart';

class PrivateMessageService {
  const PrivateMessageService();

  Future<String> getOrCreateConversation(String targetUserId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    if (user.id == targetUserId) {
      throw StateError('Cannot message yourself.');
    }

    final ids = [user.id, targetUserId]..sort();
    final existing = await client
        .from('private_conversations')
        .select('id')
        .eq('user_one_id', ids.first)
        .eq('user_two_id', ids.last)
        .maybeSingle();

    if (existing != null) {
      return existing['id'].toString();
    }

    final created = await client
        .from('private_conversations')
        .insert({'user_one_id': ids.first, 'user_two_id': ids.last})
        .select('id')
        .single();

    return created['id'].toString();
  }

  Future<void> sendMessage({
    required String targetUserId,
    required String body,
  }) async {
    final cleanBody = body.trim();
    if (cleanBody.isEmpty) {
      return;
    }

    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    if (user.id == targetUserId) {
      throw StateError('Cannot message yourself.');
    }

    final conversationId = await getOrCreateConversation(targetUserId);
    final now = DateTime.now().toUtc().toIso8601String();

    await client.from('private_messages').insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'receiver_id': targetUserId,
      'body': cleanBody,
    });

    await client
        .from('private_conversations')
        .update({
          'last_message': cleanBody,
          'last_message_at': now,
          'updated_at': now,
        })
        .eq('id', conversationId);
  }

  Future<void> sendHi(String targetUserId, {required bool isArabic}) {
    return sendMessage(
      targetUserId: targetUserId,
      body: isArabic
          ? '\u0645\u0631\u062d\u0628\u0627 \u{1F44B}'
          : 'Hi \u{1F44B}',
    );
  }

  Future<List<PrivateMessage>> fetchMessages(String conversationId) async {
    final data = await SupabaseService.requiredClient
        .from('private_messages')
        .select('id, conversation_id, sender_id, receiver_id, body, created_at, read_at, deleted_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return (data as List<dynamic>)
        .map((item) => PrivateMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Soft-deletes a message by setting deleted_at to now.
  /// Only the sender may call this — RLS enforces it on the server side.
  Future<void> deleteMessage(String messageId) async {
    final client = SupabaseService.requiredClient;
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');

    await client
        .from('private_messages')
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_by': uid,
        })
        .eq('id', messageId)
        .eq('sender_id', uid);
  }

  /// Loads the minimal profile fields needed for the chat header.
  /// Returns null if the user has no profile row yet.
  Future<Map<String, dynamic>?> fetchTargetProfile(String userId) async {
    final data = await SupabaseService.requiredClient
        .from('profiles')
        .select('id, display_name, username, avatar_url, selected_avatar_frame_key')
        .eq('id', userId)
        .maybeSingle();
    return data;
  }

  Future<List<PrivateConversationPreview>> fetchConversations() async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('No logged-in user found.');
    }

    final data = await client
        .from('private_conversations')
        .select()
        .or('user_one_id.eq.${user.id},user_two_id.eq.${user.id}')
        .order('updated_at', ascending: false);

    final rows = data as List<dynamic>;
    final otherIds = rows
        .map((item) {
          final row = item as Map<String, dynamic>;
          final one = row['user_one_id']?.toString() ?? '';
          final two = row['user_two_id']?.toString() ?? '';
          return one == user.id ? two : one;
        })
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final profiles = <String, Map<String, dynamic>>{};
    if (otherIds.isNotEmpty) {
      final profileData = await client
          .from('profiles')
          .select(
            'id, display_name, username, avatar_url, selected_avatar_frame_key, vip_level',
          )
          .inFilter('id', otherIds);

      for (final item in profileData as List<dynamic>) {
        final profile = item as Map<String, dynamic>;
        profiles[profile['id'].toString()] = profile;
      }
    }

    // Fetch unread counts for all conversations in a single query (no N+1).
    final unreadRows = await client
        .from('private_messages')
        .select('conversation_id')
        .eq('receiver_id', user.id)
        .filter('read_at', 'is', null);

    final unreadMap = <String, int>{};
    for (final item in unreadRows as List<dynamic>) {
      final cid =
          (item as Map<String, dynamic>)['conversation_id']?.toString() ?? '';
      if (cid.isNotEmpty) unreadMap[cid] = (unreadMap[cid] ?? 0) + 1;
    }

    return rows.map((item) {
      final row = item as Map<String, dynamic>;
      final one = row['user_one_id']?.toString() ?? '';
      final two = row['user_two_id']?.toString() ?? '';
      final otherId = one == user.id ? two : one;
      final profile = profiles[otherId];
      final nickname = _safeDisplayName(profile);
      final convId = row['id']?.toString() ?? '';

      return PrivateConversationPreview(
        conversationId: convId,
        otherUserId: otherId,
        otherNickname: nickname,
        otherAvatarUrl: profile?['avatar_url']?.toString(),
        otherFrameId: profile?['selected_avatar_frame_key']?.toString(),
        otherVipLevel: profile?['vip_level'] as int?,
        lastMessage: row['last_message']?.toString(),
        lastMessageAt: DateTime.tryParse(
          row['last_message_at']?.toString() ?? '',
        ),
        unreadCount: unreadMap[convId] ?? 0,
      );
    }).toList();
  }

  /// Mark all unread messages in [conversationId] as read for the current user.
  Future<void> markConversationRead(String conversationId) async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null) return;

    await client
        .from('private_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('receiver_id', user.id)
        .filter('read_at', 'is', null);
  }

  /// Returns total number of unread messages across all conversations.
  Future<int> fetchTotalUnreadCount() async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;
    if (user == null) return 0;

    final data = await client
        .from('private_messages')
        .select('id')
        .eq('receiver_id', user.id)
        .filter('read_at', 'is', null);

    return (data as List<dynamic>).length;
  }

  String _safeDisplayName(Map<String, dynamic>? profile) {
    final displayName = profile?['display_name']?.toString().trim();
    final fullName = profile?['full_name']?.toString().trim();
    final username = profile?['username']?.toString().trim();

    if (displayName != null && displayName.isNotEmpty) return displayName;
    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (username != null && username.isNotEmpty) return username;

    return 'Unknown user';
  }
}
