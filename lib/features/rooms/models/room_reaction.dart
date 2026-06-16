class RoomReaction {
  const RoomReaction({required this.emoji, required this.expiresAt});

  final String emoji;
  final DateTime expiresAt;

  bool get isActive => DateTime.now().isBefore(expiresAt);
}
