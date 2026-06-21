import 'package:flutter/material.dart';

/// Small gender chip: blue for male, red/rose for female. Renders nothing for
/// unknown/other (callers should guard with [ProfileGenderChip.isKnown]).
class ProfileGenderChip extends StatelessWidget {
  const ProfileGenderChip({
    required this.gender,
    required this.isArabic,
    super.key,
  });

  final String gender;
  final bool isArabic;

  static const _male = Color(0xFF3B9BFF); // blue
  static const _female = Color(0xFFFF5C8A); // rose/red

  static bool isKnown(String? g) {
    final v = g?.trim().toLowerCase();
    return v == 'male' || v == 'female';
  }

  @override
  Widget build(BuildContext context) {
    final v = gender.trim().toLowerCase();
    if (v != 'male' && v != 'female') return const SizedBox.shrink();
    final male = v == 'male';
    final color = male ? _male : _female;
    final label = male
        ? (isArabic ? 'ذكر' : 'Male')
        : (isArabic ? 'أنثى' : 'Female');

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.25)!,
            color,
            Color.lerp(color, Colors.black, 0.22)!,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 7),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(male ? Icons.male_rounded : Icons.female_rounded,
              size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
