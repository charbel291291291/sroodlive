/// Frame Management v2 — shared admin palette.
///
/// These are the exact colours `frame_management_screen.dart` already used,
/// lifted out so the editor dialog, artwork field and live preview match the
/// screen they open from instead of each re-declaring hex literals. Nothing is
/// restyled: the dark luxury Srood admin look is preserved verbatim.
library;

import 'package:flutter/material.dart';

abstract final class FrameAdminTheme {
  /// Scaffold background.
  static const Color background = Color(0xFF0B0612);

  /// App bar, dialogs, sheets.
  static const Color surface = Color(0xFF160B26);

  /// List rows and secondary cards.
  static const Color card = Color(0xFF140A24);

  /// Raised cards (migration status, section panels).
  static const Color raisedCard = Color(0xFF1A0F2E);

  /// Field fill, one step above [surface] so inputs read as inputs.
  static const Color field = Color(0xFF1E1233);

  static const Color border = Color(0x22FFFFFF);
  static const Color borderFocused = Color(0x66B388FF);

  static const Color textPrimary = Colors.white;

  /// Body copy and field labels.
  static const Color textSecondary = Color(0xFFBCAED6);

  /// Metadata, hints, disabled copy.
  static const Color textMuted = Color(0xFF9E91B8);

  static const Color danger = Color(0xFFFF5C7A);
  static const Color warning = Color(0xFFF0C15A);
  static const Color success = Color(0xFF2ECC71);
  static const Color accent = Color(0xFFB388FF);

  /// Below this dialog width, two-column field rows stack.
  static const double stackBreakpoint = 780;

  /// Editor dialog width ceiling — wide enough for two columns, narrow enough
  /// that a 1920px display does not stretch labels across the screen.
  static const double dialogMaxWidth = 760;

  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    String? helper,
    String? error,
    Widget? suffix,
    Widget? prefix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      errorText: error,
      errorMaxLines: 3,
      suffixIcon: suffix,
      prefixIcon: prefix,
      isDense: true,
      filled: true,
      fillColor: field,
      labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: textMuted, fontSize: 12.5),
      helperStyle: const TextStyle(color: textMuted, fontSize: 11.5),
      errorStyle: const TextStyle(color: danger, fontSize: 11.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: borderFocused, width: 1.4),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: danger),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: danger, width: 1.4),
      ),
    );
  }

  static const TextStyle fieldTextStyle = TextStyle(
    color: textPrimary,
    fontSize: 14,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: textPrimary,
    fontWeight: FontWeight.w900,
    fontSize: 13,
    letterSpacing: 0.3,
  );

  static const TextStyle metaStyle = TextStyle(
    color: textMuted,
    fontSize: 11.5,
  );
}

/// Two fields side by side above [FrameAdminTheme.stackBreakpoint], stacked
/// below it. The same idiom `admin_dashboard_screen.dart` uses for its
/// responsive form rows.
class FrameFieldPair extends StatelessWidget {
  const FrameFieldPair({
    required this.first,
    required this.second,
    this.gap = 12,
    super.key,
  });

  final Widget first;
  final Widget second;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < FrameAdminTheme.stackBreakpoint - 120) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              SizedBox(height: gap),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: gap),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
