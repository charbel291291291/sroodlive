class CrashV3Event {
  const CrashV3Event({
    required this.roundId,
    required this.sequence,
    required this.type,
    required this.serverTimestamp,
  });
  final String roundId, type;
  final int sequence;
  final DateTime serverTimestamp;
  factory CrashV3Event.fromJson(Map<String, dynamic> json) => CrashV3Event(
    roundId: json['round_id'] as String,
    sequence: (json['event_sequence'] as num).toInt(),
    type: json['event_type'] as String,
    serverTimestamp: DateTime.parse(
      (json['server_timestamp'] ?? json['created_at']) as String,
    ).toUtc(),
  );
}
