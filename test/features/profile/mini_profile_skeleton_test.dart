import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/profile/widgets/mini_profile_skeleton.dart';

void main() {
  for (final width in const [320.0, 360.0, 375.0, 390.0, 430.0]) {
    testWidgets('loading skeleton has no overflow at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniProfileSkeleton())),
      );
      await tester.pump();

      expect(find.byType(MiniProfileSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
