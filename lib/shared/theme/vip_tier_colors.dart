import 'package:flutter/material.dart';

class VipTierStyle {
  final int level;
  final Color start;
  final Color end;
  final Color border;
  final Color text;
  final Color shadow;
  final String label;

  const VipTierStyle({
    required this.level,
    required this.start,
    required this.end,
    required this.border,
    required this.text,
    required this.shadow,
    required this.label,
  });
}

class VipTierColors {
  static const Map<int, VipTierStyle> styles = {
    1: VipTierStyle(
      level: 1,
      label: 'VIP1',
      start: Color(0xFF7A7F8C),
      end: Color(0xFFB8BEC9),
      border: Color(0xFFD7DCE5),
      text: Color(0xFF11131A),
      shadow: Color(0x557A7F8C),
    ),
    2: VipTierStyle(
      level: 2,
      label: 'VIP2',
      start: Color(0xFF2E8CFF),
      end: Color(0xFF7ED7FF),
      border: Color(0xFFB9ECFF),
      text: Color(0xFF06121E),
      shadow: Color(0x552E8CFF),
    ),
    3: VipTierStyle(
      level: 3,
      label: 'VIP3',
      start: Color(0xFF18A66A),
      end: Color(0xFF7CFFC4),
      border: Color(0xFFA7FFD8),
      text: Color(0xFF061A11),
      shadow: Color(0x5518A66A),
    ),
    4: VipTierStyle(
      level: 4,
      label: 'VIP4',
      start: Color(0xFF7A3CFF),
      end: Color(0xFFC59BFF),
      border: Color(0xFFE0C7FF),
      text: Color(0xFF12061F),
      shadow: Color(0x557A3CFF),
    ),
    5: VipTierStyle(
      level: 5,
      label: 'VIP5',
      start: Color(0xFFFF8A00),
      end: Color(0xFFFFD36A),
      border: Color(0xFFFFE6A8),
      text: Color(0xFF211100),
      shadow: Color(0x55FF8A00),
    ),
    6: VipTierStyle(
      level: 6,
      label: 'VIP6',
      start: Color(0xFFFF3D7F),
      end: Color(0xFFFF9AC2),
      border: Color(0xFFFFC2D8),
      text: Color(0xFF21000B),
      shadow: Color(0x55FF3D7F),
    ),
    7: VipTierStyle(
      level: 7,
      label: 'VIP7',
      start: Color(0xFFE7B84B),
      end: Color(0xFFFFF0A3),
      border: Color(0xFFFFF6C7),
      text: Color(0xFF241900),
      shadow: Color(0x66E7B84B),
    ),
    8: VipTierStyle(
      level: 8,
      label: 'VIP8',
      start: Color(0xFF00C2FF),
      end: Color(0xFFB86DFF),
      border: Color(0xFFE2C4FF),
      text: Color(0xFF070B18),
      shadow: Color(0x6600C2FF),
    ),
    9: VipTierStyle(
      level: 9,
      label: 'VIP9',
      start: Color(0xFFFFD56A),
      end: Color(0xFFFF2FB3),
      border: Color(0xFFFFF1B8),
      text: Color(0xFF1B0611),
      shadow: Color(0x88FF2FB3),
    ),
  };

  static VipTierStyle of(int level) {
    return styles[level] ?? styles[1]!;
  }
}
