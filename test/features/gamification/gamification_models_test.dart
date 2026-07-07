import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/gamification/models/backpack_item.dart';
import 'package:srood_live/features/gamification/models/store_item.dart';
import 'package:srood_live/features/gamification/models/task_item.dart';

import '../../helpers/test_fixtures.dart';

void main() {
  group('Gamification models', () {
    test('store item parses catalog fields and metadata', () {
      final item = StoreItem.fromJson(storeItemFixture);

      expect(item.id, 'frame-gold');
      expect(item.priceCoins, 1500);
      expect(item.isFrame, isTrue);
      expect(item.frameKey, 'gold_frame');
      expect(item.owned, isTrue);
    });

    test('task progress is bounded and claim state is derived', () {
      final task = TaskItem.fromJson({
        ...taskFixture,
        'progress': 5,
        'completed': true,
      });

      expect(task.progressFraction, 1);
      expect(task.canClaim, isTrue);
      expect(task.isDaily, isTrue);
    });

    test('backpack item parses ownership and nested catalog item', () {
      final item = BackpackItem.fromJson(backpackItemFixture);

      expect(item.id, 'ownership-1');
      expect(item.equipped, isTrue);
      expect(item.isFrame, isTrue);
      expect(item.item.name, 'Gold Frame');
      expect(item.acquiredAt.toUtc(), DateTime.utc(2026, 7, 1, 10));
    });

    test('malformed optional values fall back safely', () {
      final store = StoreItem.fromJson(const {});
      final task = TaskItem.fromJson(const {
        'requirement_count': 0,
        'progress': 10,
      });

      expect(store.id, isEmpty);
      expect(store.metadata, isEmpty);
      expect(task.progressFraction, 0);
      expect(task.canClaim, isFalse);
    });
  });
}
