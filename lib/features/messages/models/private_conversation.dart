class PrivateConversationPreview {
  const PrivateConversationPreview({
    required this.conversationId,
    required this.otherUserId,
    required this.otherNickname,
    this.otherAvatarUrl,
    this.otherFrameId,
    this.otherVipLevel,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String conversationId;
  final String otherUserId;
  final String otherNickname;
  final String? otherAvatarUrl;
  final String? otherFrameId;

  /// VIP level (1-10) for the other participant. Null = not VIP.
  final int? otherVipLevel;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
}
