class CrashV3ClockService {
  Duration _offset = Duration.zero;
  DateTime get now => DateTime.now().toUtc().add(_offset);
  Duration get offset => _offset;
  void update({
    required DateTime sentAt,
    required DateTime receivedAt,
    required DateTime serverTime,
  }) {
    final midpoint = sentAt.add(receivedAt.difference(sentAt) ~/ 2);
    _offset = serverTime.difference(midpoint);
  }

  bool get hasExcessiveDrift => _offset.abs() > const Duration(seconds: 2);
}
