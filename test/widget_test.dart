import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/main.dart';

void main() {
  testWidgets('SrOOd Live app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const SrOOdLiveApp());

    expect(find.text('SrOOd Live'), findsOneWidget);
    expect(find.text('Voice rooms. Gifts. Prestige.'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });
}
