import 'package:flutter/material.dart';

import '../../core/vip/vip_spec.dart';

/// Renders a username with the VIP visual style for its level.
///
/// - Non-VIP (null / 0 / expired → pass 0) renders plain white text.
/// - VIP 1–5: solid escalating colour + soft glow from VIP 5.
/// - VIP 6–9: gradient name paint with stronger glow.
///
/// Display only — never grants or changes VIP.
class VipUsername extends StatelessWidget {
  const VipUsername({
    required this.name,
    required this.vipLevel,
    this.fontSize = 16,
    this.fontWeight,
    this.textAlign,
    this.maxLines = 1,
    this.normalColor = Colors.white,
    super.key,
  });

  final String name;
  final int? vipLevel;
  final double fontSize;
  final FontWeight? fontWeight;
  final TextAlign? textAlign;
  final int maxLines;
  final Color normalColor;

  @override
  Widget build(BuildContext context) {
    final level = vipLevel ?? 0;
    final spec  = VipSpecResolver.resolve(level);

    if (!spec.hasBadge) {
      return Text(
        name,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.0,
          fontWeight: fontWeight ?? FontWeight.w900,
          color: normalColor,
        ),
      );
    }

    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.0,
      fontWeight: fontWeight ?? spec.nameFontWeight,
      color: spec.nameColor,
      shadows: spec.nameShadows(),
    );

    final text = Text(
      name,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: baseStyle,
    );

    if (!spec.useNameGradient) return text;

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: spec.nameGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        name,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: baseStyle.copyWith(color: Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Golden ID Badge
// ─────────────────────────────────────────────────────────────────────────────

/// A premium styled chip for a user's public ID.
///
/// When [isGoldenId] is false (default) renders a plain neutral chip.
/// When true, applies the colour scheme dictated by [goldenIdStyle] and the
/// icon/decoration from [goldenIdFrame].
///
/// Style values: gold | diamond | royal | neon | fire | purple
/// Frame values: classic | crown | wings | glow | shield | luxury
class GoldenIdBadge extends StatelessWidget {
  const GoldenIdBadge({
    required this.idText,
    this.isGoldenId = true,
    this.goldenIdStyle = 'gold',
    this.goldenIdFrame = 'classic',
    this.onTap,
    this.compact = false,
    this.showCopyIcon = false,
    super.key,
  });

  final String idText;
  final bool isGoldenId;
  final String goldenIdStyle;
  final String goldenIdFrame;
  final VoidCallback? onTap;
  final bool compact;
  final bool showCopyIcon;

  // ── Style palette ─────────────────────────────────────────────────────────

  static const _styleData = <String, _StyleSpec>{
    'gold': _StyleSpec(
      gradient: [Color(0x33FFE9A8), Color(0x22C8952D)],
      border:   Color(0xFFF0C15A),
      text:     Color(0xFFFFE9A8),
      glow:     Color(0x4DF0C15A),
    ),
    'diamond': _StyleSpec(
      gradient: [Color(0x33B8E8FF), Color(0x228BB8D4)],
      border:   Color(0xFF8ECFEE),
      text:     Color(0xFFCBEEFF),
      glow:     Color(0x4D8ECFEE),
    ),
    'royal': _StyleSpec(
      gradient: [Color(0x44C084FC), Color(0x22C8952D)],
      border:   Color(0xFFAB6FE8),
      text:     Color(0xFFE8CEFF),
      glow:     Color(0x4DAB6FE8),
    ),
    'neon': _StyleSpec(
      gradient: [Color(0x3300FFCC), Color(0x22FF00CC)],
      border:   Color(0xFF00FFCC),
      text:     Color(0xFFAAFFEE),
      glow:     Color(0x5500FFCC),
    ),
    'fire': _StyleSpec(
      gradient: [Color(0x44FF8C00), Color(0x33FF2D00)],
      border:   Color(0xFFFF6A00),
      text:     Color(0xFFFFCCA0),
      glow:     Color(0x55FF6A00),
    ),
    'purple': _StyleSpec(
      gradient: [Color(0x448B5CF6), Color(0x226D28D9)],
      border:   Color(0xFF8B5CF6),
      text:     Color(0xFFD8B4FE),
      glow:     Color(0x558B5CF6),
    ),
  };

  // ── Frame icon/decoration ─────────────────────────────────────────────────

  static IconData? _frameLeadingIcon(String frame) {
    switch (frame) {
      case 'crown':   return Icons.emoji_events_rounded;
      case 'wings':   return Icons.air_rounded;
      case 'glow':    return Icons.flare_rounded;
      case 'shield':  return Icons.shield_rounded;
      case 'luxury':  return Icons.auto_awesome_rounded;
      case 'classic':
      default:        return Icons.workspace_premium_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Non-golden: plain neutral chip ────────────────────────────────────
    if (!isGoldenId) {
      final content = Container(
        height: compact ? 24 : 30,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Center(
          child: Text(
            idText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      if (onTap == null) return content;
      return InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: content);
    }

    // ── Golden styled chip ─────────────────────────────────────────────────
    final spec  = _styleData[goldenIdStyle] ?? _styleData['gold']!;
    final icon  = _frameLeadingIcon(goldenIdFrame);
    final extra = goldenIdFrame == 'glow'
        ? [BoxShadow(color: spec.glow, blurRadius: compact ? 10 : 16, spreadRadius: 1)]
        : [BoxShadow(color: spec.glow, blurRadius: compact ? 7 : 11)];

    final content = Container(
      height: compact ? 26 : 32,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: spec.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: spec.border.withValues(alpha: 0.65), width: 1.2),
        boxShadow: extra,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: spec.text, size: compact ? 12 : 14),
          SizedBox(width: compact ? 4 : 5),
          Flexible(
            child: Text(
              idText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: spec.text,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                shadows: [Shadow(color: spec.glow, blurRadius: 8)],
              ),
            ),
          ),
          if (showCopyIcon) ...[
            SizedBox(width: compact ? 4 : 5),
            Icon(Icons.copy_rounded, color: spec.border.withValues(alpha: 0.75), size: compact ? 12 : 14),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: content);
  }
}

@immutable
class _StyleSpec {
  const _StyleSpec({
    required this.gradient,
    required this.border,
    required this.text,
    required this.glow,
  });
  final List<Color> gradient;
  final Color border;
  final Color text;
  final Color glow;
}
