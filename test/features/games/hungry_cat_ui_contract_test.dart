import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;
  final screen = File(
    '${root.path}/lib/features/games/screens/hungry_cat_webview_screen.dart',
  );

  test('all eight premium food assets exist and are registered', () {
    final source = screen.readAsStringSync();
    for (final food in const [
      'corn',
      'chicken',
      'tomato',
      'shrimp',
      'cow',
      'carrot',
      'fish',
      'green_pepper',
    ]) {
      final relative = 'assets/games/hungry_cat/$food.png';
      expect(File('${root.path}/$relative').existsSync(), isTrue);
      expect(source, contains("'$relative'"));
    }
  });

  test(
    'responsive controls retain scrolling and compact multiplier labels',
    () {
      final source = screen.readAsStringSync();

      expect(source, contains("'Last Results'"));
      expect(source, contains("multLabel.endsWith('x')"));
      expect(source, contains('CoinChipRow('));
      expect(source, contains('FittedBox('));
      expect(source, contains('BoxFit.contain'));
      expect(source, isNot(contains("'\$raw times'")));
    },
  );

  test('bet values and default multipliers remain unchanged', () {
    final source = screen.readAsStringSync();

    expect(
      source,
      contains('const _kBetChips = [100, 1000, 5000, 10000, 20000, 100000];'),
    );
    for (final multiplier in const ['45.0', '25.0', '15.0', '10.0']) {
      expect(source, contains('mult: $multiplier'));
    }
    expect(RegExp(r'mult: 5\.0').allMatches(source).length, 4);
  });
}
