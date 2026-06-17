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

    // Level 0: plain text, no VIP styling.
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

    // Premium tiers: paint glyphs with the tier gradient.
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

/// A premium golden-style chip for a user's public ID.
///
/// Use only when [isGoldenIdActive] returns true. Shows the *same* ID value
/// (never altered) wrapped in a luxurious gold gradient, border and glow.
class GoldenIdBadge extends StatelessWidget {
  const GoldenIdBadge({
    required this.idText,
    this.onTap,
    this.compact = false,
    this.showCopyIcon = false,
    super.key,
  });

  final String idText;
  final VoidCallback? onTap;
  final bool compact;
  final bool showCopyIcon;

  static const _gold       = Color(0xFFF0C15A);
  static const _goldBright = Color(0xFFFFE9A8);

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: compact ? 26 : 32,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x33FFE9A8), Color(0x22C8952D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withValues(alpha: 0.65), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.30),
            blurRadius: compact ? 7 : 11,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            color: _goldBright,
            size: compact ? 12 : 14,
          ),
          SizedBox(width: compact ? 4 : 5),
          Flexible(
            child: Text(
              idText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _goldBright,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                shadows: const [
                  Shadow(color: Color(0x66F0C15A), blurRadius: 8),
                ],
              ),
            ),
          ),
          if (showCopyIcon) ...[
            SizedBox(width: compact ? 4 : 5),
            Icon(
              Icons.copy_rounded,
              color: _gold.withValues(alpha: 0.75),
              size: compact ? 12 : 14,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: content,
    );
  }
}
