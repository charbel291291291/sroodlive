class PrivateMessage {
  const PrivateMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  factory PrivateMessage.fromJson(Map<String, dynamic> json) {
    return PrivateMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      receiverId: json['receiver_id']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
}
