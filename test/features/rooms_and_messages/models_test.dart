import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/messages/models/private_message.dart';
import 'package:srood_live/features/rooms/models/room.dart';

import '../../helpers/test_fixtures.dart';

void main() {
  group('Room parsing', () {
    test('preserves access flags and aggregates daily XP', () {
      final room = Room.fromJson(roomFixture);

      expect(room.isPrivate, isTrue);
      expect(room.isLocked, isTrue);
      expect(room.roomPinEnabled, isTrue);
      expect(room.closedSeats, [2, 5]);
      expect(room.countryCode, 'LB');
      expect(room.xpToday, 50);
      expect(room.ownerCountry, 'Lebanon');
    });

    test('uses safe defaults for sparse rows', () {
      final room = Room.fromJson(const {});

      expect(room.id, isEmpty);
      expect(room.maxSeats, 12);
      expect(room.allowImages, isTrue);
      expect(room.roomLevel, 1);
    });
  });

  group('Private message parsing', () {
    test('parses read messages without marking them deleted', () {
      final message = PrivateMessage.fromJson(privateMessageFixture);

      expect(message.body, 'Hello');
      expect(message.readAt, isNotNull);
      expect(message.isDeleted, isFalse);
    });

    test('deleted state is derived from deleted_at', () {
      final message = PrivateMessage.fromJson({
        ...privateMessageFixture,
        'deleted_at': '2026-07-01T10:02:00Z',
      });

      expect(message.isDeleted, isTrue);
    });
  });
}
