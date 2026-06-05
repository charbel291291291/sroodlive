class PrivateConversationPreview {
  const PrivateConversationPreview({
    required this.conversationId,
    required this.otherUserId,
    required this.otherNickname,
    this.otherAvatarUrl,
    this.otherFrameId,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String conversationId;
  final String otherUserId;
  final String otherNickname;
  final String? otherAvatarUrl;
  final String? otherFrameId;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
}
