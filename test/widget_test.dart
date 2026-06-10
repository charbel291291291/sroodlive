import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:srood_live/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.test',
    );
  });

  testWidgets('SrOOd Live app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const SrOOdLiveApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });
}
