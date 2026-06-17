import 'package:flutter/material.dart';

import '../../features/profile/widgets/country_picker_sheet.dart';

/// Resolves a country to its flag emoji.
///
/// Priority:
///   1. [countryCode] (ISO 3166-1 alpha-2, e.g. "AO") — converted to regional
///      indicator emoji directly, no list lookup needed.
///   2. [countryName] — resolved via [countryFromStored] which handles "Angola",
///      "AO", legacy free-text, partial matches, etc.
///   3. Falls back to '🏳' (white flag / unknown).
String resolveCountryFlag({String? countryCode, String? countryName}) {
  // Try ISO code first — convert to emoji flag via regional indicator chars.
  final code = countryCode?.trim().toUpperCase();
  if (code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
    return _codeToEmoji(code);
  }
  // Try name / partial / legacy via the shared resolver.
  final match = countryFromStored(countryName) ?? countryFromStored(code);
  if (match != null) return match.flag;
  return '🏳';
}

String _codeToEmoji(String code) {
  const base = 0x1F1E0 - 0x41; // Regional Indicator A offset
  final chars = code.codeUnits.map((c) => String.fromCharCode(base + c)).join();
  return chars;
}

// ─────────────────────────────────────────────────────────────────────────────

/// A country flag with optional premium visual treatment.
///
/// When [style] == 'normal' (default), renders just the flag emoji in a plain
/// neutral chip — identical in appearance to the existing flag chips in the
/// app, so normal users are visually unchanged.
///
/// For premium styles the flag is wrapped in a styled container matching the
/// GoldenIdBadge colour system.
///
/// Style values : normal | gold | diamond | royal | neon | fire | purple
/// Frame values : classic | crown | glow | shield | luxury
class PremiumCountryFlag extends StatelessWidget {
  const PremiumCountryFlag({
    this.countryCode,
    this.countryName,
    this.style = 'normal',
    this.frame = 'classic',
    this.compact = false,
    super.key,
  });

  final String? countryCode;
  final String? countryName;
  final String style;
  final String frame;
  final bool compact;

  // ── Style palette (matches GoldenIdBadge._styleData) ─────────────────────
  static const _styleData = <String, _FlagStyle>{
    'normal': _FlagStyle(
      gradient: [Color(0x10FFFFFF), Color(0x08FFFFFF)],
      border:   Color(0x33FFFFFF),
      glow:     Color(0x00000000),
    ),
    'gold': _FlagStyle(
      gradient: [Color(0x33FFE9A8), Color(0x22C8952D)],
      border:   Color(0xFFF0C15A),
      glow:     Color(0x4DF0C15A),
    ),
    'diamond': _FlagStyle(
      gradient: [Color(0x33B8E8FF), Color(0x228BB8D4)],
      border:   Color(0xFF8ECFEE),
      glow:     Color(0x4D8ECFEE),
    ),
    'royal': _FlagStyle(
      gradient: [Color(0x44C084FC), Color(0x22C8952D)],
      border:   Color(0xFFAB6FE8),
      glow:     Color(0x4DAB6FE8),
    ),
    'neon': _FlagStyle(
      gradient: [Color(0x3300FFCC), Color(0x22FF00CC)],
      border:   Color(0xFF00FFCC),
      glow:     Color(0x5500FFCC),
    ),
    'fire': _FlagStyle(
      gradient: [Color(0x44FF8C00), Color(0x33FF2D00)],
      border:   Color(0xFFFF6A00),
      glow:     Color(0x55FF6A00),
    ),
    'purple': _FlagStyle(
      gradient: [Color(0x448B5CF6), Color(0x226D28D9)],
      border:   Color(0xFF8B5CF6),
      glow:     Color(0x558B5CF6),
    ),
  };

  static IconData? _frameIcon(String frame) {
    switch (frame) {
      case 'crown':   return Icons.emoji_events_rounded;
      case 'glow':    return Icons.flare_rounded;
      case 'shield':  return Icons.shield_rounded;
      case 'luxury':  return Icons.auto_awesome_rounded;
      case 'classic':
      default:        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final flag   = resolveCountryFlag(countryCode: countryCode, countryName: countryName);
    final spec   = _styleData[style] ?? _styleData['normal']!;
    final icon   = _frameIcon(frame);
    final h      = compact ? 24.0 : 30.0;
    final fSize  = compact ? 14.0 : 16.0;
    final px     = compact ? 7.0  : 10.0;
    final isPremium = style != 'normal';

    final shadows = isPremium && spec.glow.a > 0
        ? [BoxShadow(color: spec.glow, blurRadius: frame == 'glow' ? 14 : 8)]
        : <BoxShadow>[];

    final content = Container(
      height: h,
      padding: EdgeInsets.symmetric(horizontal: px),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: spec.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isPremium
              ? spec.border.withValues(alpha: 0.65)
              : spec.border,
          width: isPremium ? 1.2 : 1,
        ),
        boxShadow: shadows,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: isPremium ? spec.border : Colors.white54, size: compact ? 10 : 12),
            SizedBox(width: compact ? 3 : 4),
          ],
          Text(flag, style: TextStyle(fontSize: fSize, height: 1.0)),
        ],
      ),
    );

    return content;
  }
}

@immutable
class _FlagStyle {
  const _FlagStyle({
    required this.gradient,
    required this.border,
    required this.glow,
  });
  final List<Color> gradient;
  final Color border;
  final Color glow;
}
