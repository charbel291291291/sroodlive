/// Login form building blocks: the glass form card, a compact auth text
/// field with inline validation, and the password variant with a labeled
/// show/hide toggle. All values and callbacks are owned by the screen.
library;

import 'package:flutter/material.dart';

const _kGold = Color(0xFFF0C15A);
const _kLavender = Color(0xFFBCAED6);
const _kError = Color(0xFFFF7A7A);

/// Violet glass wrapper around the form fields and actions.
class SroodLoginFormCard extends StatelessWidget {
  const SroodLoginFormCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF160B26).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Compact 58px auth field with icon, focus/error borders, autofill, and an
/// inline validation message below the field.
class SroodAuthTextField extends StatelessWidget {
  const SroodAuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isArabic,
    this.errorText,
    this.enabled = true,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.focusNode,
    this.onSubmitted,
    this.suffix,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isArabic;
  final String? errorText;
  final bool enabled;
  final TextInputType? keyboardType;
  final bool obscureText;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    const radius = 16.0;
    final hasError = errorText != null && errorText!.isNotEmpty;
    final fillColor = const Color(0xFF100718).withValues(alpha: 0.75);
    final borderColor = hasError
        ? _kError.withValues(alpha: 0.75)
        : const Color(0xFF8B5CF6).withValues(alpha: 0.35);

    OutlineInputBorder border(Color color, [double width = 1.0]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return Column(
      crossAxisAlignment: isArabic
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Semantics(
          label: label,
          textField: true,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            keyboardType: keyboardType,
            obscureText: obscureText,
            autofillHints: autofillHints,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            // Keeps the focused field above the keyboard while scrolling.
            scrollPadding: const EdgeInsets.only(bottom: 120),
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(
                color: _kLavender,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              floatingLabelStyle: TextStyle(
                color: hasError ? _kError : _kGold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              prefixIcon: Icon(
                icon,
                color: hasError ? _kError : _kGold,
                size: 20,
              ),
              suffixIcon: suffix,
              filled: true,
              fillColor: fillColor,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              border: border(borderColor),
              enabledBorder: border(borderColor),
              disabledBorder: border(borderColor.withValues(alpha: 0.4)),
              focusedBorder: border(hasError ? _kError : _kGold, 1.5),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 6, right: 6),
            child: Text(
              errorText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                color: _kError,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Password field with a 44px labeled show/hide toggle.
class SroodPasswordField extends StatelessWidget {
  const SroodPasswordField({
    required this.controller,
    required this.label,
    required this.isArabic,
    required this.obscured,
    required this.onToggleVisibility,
    this.errorText,
    this.enabled = true,
    this.focusNode,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool isArabic;
  final bool obscured;
  final VoidCallback onToggleVisibility;
  final String? errorText;
  final bool enabled;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SroodAuthTextField(
      controller: controller,
      label: label,
      icon: Icons.lock_rounded,
      isArabic: isArabic,
      errorText: errorText,
      enabled: enabled,
      obscureText: obscured,
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.done,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      suffix: Semantics(
        label: obscured
            ? (isArabic ? 'إظهار كلمة المرور' : 'Show password')
            : (isArabic ? 'إخفاء كلمة المرور' : 'Hide password'),
        button: true,
        child: IconButton(
          onPressed: enabled ? onToggleVisibility : null,
          iconSize: 20,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Icon(
            obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            color: _kLavender.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}
