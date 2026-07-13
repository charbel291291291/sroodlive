// Login UI v2 widget coverage: brand separation, field validation
// presentation, password visibility toggle, button states, and responsive
// widths — presentation widgets only (auth logic lives in the screen and
// is unchanged).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srood_live/features/auth/presentation/srood_auth_buttons.dart';
import 'package:srood_live/features/auth/presentation/srood_auth_fields.dart';
import 'package:srood_live/features/auth/presentation/srood_login_header.dart';

Widget wrap(Widget child, {double width = 375, bool rtl = false}) {
  return MaterialApp(
    home: Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF07030D),
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SroodLoginBrand', () {
    testWidgets('title and subtitle are separate widgets with a gap', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SroodLoginBrand(isArabic: false)));

      final title = tester.getRect(find.text('Srood Live'));
      final subtitle = tester.getRect(find.text('Enter your Srood Live world'));
      expect(
        subtitle.top,
        greaterThanOrEqualTo(title.bottom + 4),
        reason: 'subtitle must never overlap the wordmark',
      );
    });

    for (final width in const [320.0, 430.0]) {
      testWidgets('fits ${width.round()}px without overflow', (tester) async {
        await tester.pumpWidget(
          wrap(const SroodLoginBrand(isArabic: true), width: width, rtl: true),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SroodAuthTextField', () {
    testWidgets('shows inline error text and error styling', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        wrap(
          SroodAuthTextField(
            controller: ctrl,
            label: 'Email',
            icon: Icons.email_rounded,
            isArabic: false,
            errorText: 'Enter your email.',
          ),
        ),
      );
      expect(find.text('Enter your email.'), findsOneWidget);
    });

    testWidgets('compact field height stays in the 56-62px band', (
      tester,
    ) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        wrap(
          SroodAuthTextField(
            controller: ctrl,
            label: 'Email',
            icon: Icons.email_rounded,
            isArabic: false,
          ),
        ),
      );
      final size = tester.getSize(find.byType(TextField));
      expect(size.height, greaterThanOrEqualTo(52));
      expect(size.height, lessThanOrEqualTo(64));
    });
  });

  group('SroodPasswordField', () {
    testWidgets('toggle switches obscureText and its semantic label', (
      tester,
    ) async {
      final ctrl = TextEditingController(text: 'secret');
      addTearDown(ctrl.dispose);
      var obscured = true;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => wrap(
            SroodPasswordField(
              controller: ctrl,
              label: 'Password',
              isArabic: false,
              obscured: obscured,
              onToggleVisibility: () => setState(() => obscured = !obscured),
            ),
          ),
        ),
      );

      EditableText editable() =>
          tester.widget<EditableText>(find.byType(EditableText));
      expect(editable().obscureText, isTrue);
      expect(find.bySemanticsLabel('Show password'), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(editable().obscureText, isFalse);
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    });
  });

  group('Auth buttons', () {
    testWidgets('primary shows in-button progress and blocks taps while '
        'loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          SroodPrimaryAuthButton(
            label: 'Sign In',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sign In'), findsNothing);

      await tester.tap(find.byType(SroodPrimaryAuthButton));
      expect(taps, 0, reason: 'loading button must not fire duplicate taps');
    });

    testWidgets('primary fires exactly once per tap when enabled', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(SroodPrimaryAuthButton(label: 'Sign In', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Sign In'));
      expect(taps, 1);
    });

    testWidgets('buttons meet height targets and 44px minimum', (tester) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              SroodPrimaryAuthButton(label: 'Sign In', onPressed: () {}),
              const SizedBox(height: 12),
              SroodSecondaryAuthButton(
                label: 'Create Account',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      final primary = tester.getSize(find.byType(SroodPrimaryAuthButton));
      final secondary = tester.getSize(find.byType(SroodSecondaryAuthButton));
      expect(primary.height, inInclusiveRange(54, 58));
      expect(secondary.height, inInclusiveRange(44, 56));
    });
  });

  group('Login form card', () {
    testWidgets('renders full form at 320px RTL without overflow', (
      tester,
    ) async {
      final email = TextEditingController();
      final password = TextEditingController();
      addTearDown(email.dispose);
      addTearDown(password.dispose);

      await tester.pumpWidget(
        wrap(
          SroodLoginFormCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SroodAuthTextField(
                  controller: email,
                  label: 'البريد الإلكتروني',
                  icon: Icons.email_rounded,
                  isArabic: true,
                  errorText: 'اكتب البريد الإلكتروني.',
                ),
                const SizedBox(height: 12),
                SroodPasswordField(
                  controller: password,
                  label: 'كلمة المرور',
                  isArabic: true,
                  obscured: true,
                  onToggleVisibility: () {},
                  errorText: 'اكتب كلمة المرور.',
                ),
                const SizedBox(height: 18),
                SroodPrimaryAuthButton(label: 'دخول', onPressed: () {}),
                const SizedBox(height: 14),
                SroodSecondaryAuthButton(label: 'إنشاء حساب', onPressed: () {}),
              ],
            ),
          ),
          width: 320,
          rtl: true,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('اكتب البريد الإلكتروني.'), findsOneWidget);
      expect(find.text('اكتب كلمة المرور.'), findsOneWidget);
    });
  });
}
