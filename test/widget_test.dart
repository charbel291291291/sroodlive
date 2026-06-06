import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/main.dart';

void main() {
  testWidgets('SrOOd Live app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const SrOOdLiveApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Voice rooms. Gifts. Prestige.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });
}
