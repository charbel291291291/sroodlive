import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/shared/widgets/coin_ui.dart';

void main() {
  group('formatCoinAmount', () {
    test('formats raw, thousands, and millions consistently', () {
      expect(formatCoinAmount(999), '999');
      expect(formatCoinAmount(1000), '1K');
      expect(formatCoinAmount(1250), '1.3K');
      expect(formatCoinAmount(1000000), '1M');
      expect(formatCoinAmount(1500000), '1.5M');
    });
  });
}
