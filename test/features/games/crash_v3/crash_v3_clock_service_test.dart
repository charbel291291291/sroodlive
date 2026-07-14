import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/games/crash_v3/services/crash_v3_clock_service.dart';

void main() {
  test('estimates server offset from request midpoint', () {
    final clock = CrashV3ClockService();
    final sent = DateTime.utc(2026, 1, 1, 12);
    clock.update(
      sentAt: sent,
      receivedAt: sent.add(const Duration(milliseconds: 200)),
      serverTime: sent.add(const Duration(milliseconds: 600)),
    );
    expect(clock.offset, const Duration(milliseconds: 500));
  });
}
