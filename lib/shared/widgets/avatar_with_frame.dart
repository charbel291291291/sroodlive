import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/vip/vip_spec.dart';
import '../../features/rooms/utils/vip_room_features.dart';

enum _FrameAnimType {
  glowPulse,
  shimmerSweep,
  sparkleAura;

  static _FrameAnimType _forKey(String frameKey) {
    if (frameKey == 'custom_super_admin' ||
        frameKey == 'custom_admin' ||
        frameKey == 'custom_srood_live' ||
        frameKey == 'luxury_diamond_purple' ||
        frameKey == 'luxury_black_gold_crown') {
      return sparkleAura;
    }
    if (frameKey.contains('gold') ||
        frameKey.contains('diamond') ||
        frameKey.startsWith('luxury_') ||
        frameKey == 'custom_luxury_gold' ||
        frameKey == 'custom_luxury_diamond') {
      return shimmerSweep;
    }
    return glowPulse;
  }
}

const Map<String, String> avatarFrameAssetPaths = {
  'luxury_ruby_royal': 'assets/avatar_frames/luxury_ruby_royal.png',
  'luxury_ruby_royal_dark': 'assets/avatar_frames/luxury_ruby_royal_dark.png',
  'custom_srood_live': 'assets/avatar_frames/custom/srood_live_frame_final.png',
  'custom_super_admin':
      'assets/avatar_frames/custom/super_admin_frame_transparent.png',
  'custom_admin': 'assets/avatar_frames/custom/admin_frame_transparent.png',
  'custom_luxury_gold':
      'assets/avatar_frames/custom/luxury_gold_frame_transparent.png',
  'custom_luxury_diamond':
      'assets/avatar_frames/custom/luxury_diamond_frame_transparent.png',
};

class AvatarWithFrame extends StatelessWidget {
  const AvatarWithFrame({
    required this.imageUrl,
    required this.radius,
    this.frameKey,
    this.publicUserId,
    this.nickname,
    this.vipLevel,
    this.showVipBadge = false,
    this.autoVipFrame = true,
    this.compact = false,
    this.avatarScale,
    this.frameScale,
    this.imageAlignment = Alignment.center,
    this.fallbackIcon = Icons.person_rounded,
    this.animated = false,
    super.key,
  });

  final String? imageUrl;
  final double radius;
  final String? frameKey;
  final String? publicUserId;
  final String? nickname;
  final int? vipLevel;
  final bool showVipBadge;

  /// When true (default) and no explicit [frameKey] is selected, a VIP user
  /// automatically gets the matching `vip_$level` PNG frame. Set to false when
  /// the caller draws its own VIP frame (e.g. the profile hero's webp frame) to
  /// avoid stacking two frames on one avatar.
  final bool autoVipFrame;
  final bool compact;
  final double? avatarScale;
  final double? frameScale;
  final Alignment imageAlignment;
  final IconData fallbackIcon;

  /// When true, overlays a lightweight animation on the frame ring.
  /// Has no effect when there is no active frame. Defaults to false so
  /// existing call sites are unaffected.
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final frame = _effectiveFrameKey(frameKey?.trim());
    final hasFrame = frame != null && frame.isNotEmpty;
    final isVipPngFrame = hasFrame && frame.startsWith('vip_');
    final baseAvatarSize = radius * 2;
    final frameSize = hasFrame
        ? baseAvatarSize * (frameScale ?? _frameScale(frame, compact: compact))
        : baseAvatarSize;
    final avatarSize =
        baseAvatarSize *
        (hasFrame ? (avatarScale ?? _avatarScale(frame)) : 1.0).clamp(
          0.70,
          1.0,
        );
    final frameAssetPath = _frameAssetPath(frame);
    final url = imageUrl?.trim();

    // VIP wreath frames have a crown on top + a "VIP" label at the bottom that
    // push the visual opening below the geometric centre. Nudge the photo down
    // so it sits inside the opening instead of behind the crown.
    final avatarDy = isVipPngFrame ? frameSize * 0.035 : 0.0;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final avatarCachePx = (avatarSize * dpr).round();
    final frameCachePx = (frameSize * dpr).round();

    final sizedBox = SizedBox(
      width: frameSize,
      height: frameSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(0, avatarDy),
            child: SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: ClipOval(
                child: url != null && url.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        alignment: imageAlignment,
                        width: avatarSize,
                        height: avatarSize,
                        memCacheWidth: avatarCachePx,
                        memCacheHeight: avatarCachePx,
                        errorWidget: (context, error, stackTrace) =>
                            _AvatarFallback(
                              icon: fallbackIcon,
                              size: avatarSize,
                            ),
                      )
                    : _AvatarFallback(icon: fallbackIcon, size: avatarSize),
              ),
            ),
          ),
          if (hasFrame && frameAssetPath != null)
            Center(
              child: IgnorePointer(
                child: SizedBox.square(
                  dimension: frameSize,
                  child: Image.asset(
                    frameAssetPath,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    cacheWidth: frameCachePx,
                    cacheHeight: frameCachePx,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            )
          else if (hasFrame)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AvatarFramePainter(frame, compact: compact),
                ),
              ),
            ),
          if (hasFrame &&
              !compact &&
              frameAssetPath == null &&
              _FrameStyle.fromKey(frame).accentIcon != null)
            Positioned(
              top: -radius * 0.08,
              child: Icon(
                _FrameStyle.fromKey(frame).accentIcon,
                color: _FrameStyle.fromKey(frame).accentColor,
                size: math.max(12, radius * 0.48),
              ),
            ),
          if (showVipBadge && (vipLevel ?? 0) > 0)
            Positioned(
              right: -radius * 0.04,
              bottom: -radius * 0.03,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: math.max(4, radius * 0.14),
                  vertical: math.max(2, radius * 0.06),
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0C15A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF160B26), width: 1),
                ),
                child: Text(
                  'VIP ${vipLevel ?? 0}',
                  style: TextStyle(
                    color: const Color(0xFF160B26),
                    fontWeight: FontWeight.w900,
                    fontSize: math.max(7, radius * 0.18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (animated && hasFrame) {
      return RepaintBoundary(
        child: _AnimatedFrameWrapper(
          frameSize: frameSize,
          glowColor: _effectiveGlowColor(frame),
          animType: _FrameAnimType._forKey(frame),
          child: sizedBox,
        ),
      );
    }
    return sizedBox;
  }

  static Color _effectiveGlowColor(String? frameKey) {
    if (frameKey == null) return Colors.transparent;
    if (frameKey == 'luxury_ruby_royal' || frameKey == 'luxury_ruby_royal_dark') {
      return const Color(0x88FF244A);
    }
    return switch (frameKey) {
      'custom_luxury_gold' => const Color(0x99FFD978),
      'custom_luxury_diamond' => const Color(0x998B26D9),
      'custom_super_admin' => const Color(0xAA8B26D9),
      'custom_admin' => const Color(0xAA316BFF),
      String s when s.startsWith('custom_') => const Color(0x99B000FF),
      String s when s.startsWith('vip_') => const Color(0x99F0C15A),
      _ => _FrameStyle.fromKey(frameKey).glowColor,
    };
  }

  String? _effectiveFrameKey(String? value) {
    if (value == null || value.isEmpty) {
      // No custom frame selected - auto-assign the matching VIP PNG frame
      // when the user has an active VIP level, unless the caller opted out
      // (it is drawing its own VIP frame).
      if (!autoVipFrame) return null;
      final level = (vipLevel ?? 0).clamp(0, 9);
      if (level > 0) return 'vip_$level';
      return null;
    }

    if (!VipFeatures.canUseVipFrame(value, vipLevel ?? 0)) {
      return null;
    }

    return value;
  }

  double _frameScale(String? frameKey, {required bool compact}) {
    if (frameKey != null && frameKey.startsWith('vip_')) {
      // Delegate to the shared helper for consistent scale across all widgets.
      return vipFrameScale(
        int.tryParse(frameKey.substring(4)) ?? 0,
        compact: compact,
      );
    }
    return switch (frameKey) {
      'custom_srood_live' ||
      'custom_super_admin' ||
      'custom_admin' ||
      'custom_luxury_gold' ||
      'custom_luxury_diamond' => vipFrameScale(
        0,
        compact: compact,
        custom: true,
      ),
      'luxury_ruby_royal' || 'luxury_ruby_royal_dark' => 1.42,
      _ => compact ? 1.08 : 1.18,
    };
  }

  double _avatarScale(String? frameKey) {
    if (frameKey == null || frameKey.isEmpty) return 1.0;
    if (frameKey.startsWith('vip_')) return 0.94;
    return 0.92;
  }

  String? _frameAssetPath(String? frameKey) {
    if (frameKey == null) return null;
    final staticPath = avatarFrameAssetPaths[frameKey];
    if (staticPath != null) return staticPath;
    if (frameKey.startsWith('vip_')) {
      final level = int.tryParse(frameKey.substring(4));
      if (level != null) return vipFrameAssetPath(level);
    }
    return null;
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF2D1247), Color(0xFF12091D)],
        ),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.50),
    );
  }
}

class _AvatarFramePainter extends CustomPainter {
  const _AvatarFramePainter(this.frameKey, {required this.compact});

  final String frameKey;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (frameKey == 'luxury_ruby_royal' || frameKey == 'ruby_royal') {
      _paintRubyRoyal(canvas, size, dark: false);
      return;
    }

    if (frameKey == 'luxury_ruby_royal_dark' || frameKey == 'ruby_royal_dark') {
      _paintRubyRoyal(canvas, size, dark: true);
      return;
    }

    if (frameKey == 'luxury_crystal_feather') {
      _paintCrystalFeather(canvas, size);
      return;
    }

    if (frameKey == 'luxury_autumn_bloom') {
      _paintAutumnBloom(canvas, size);
      return;
    }

    final style = _FrameStyle.fromKey(frameKey);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius * 0.88);
    final stroke = compact
        ? math.max(1.6, radius * style.strokeFactor * 0.62)
        : math.max(2.2, radius * style.strokeFactor);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? stroke * 1.2 : stroke * 1.9
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        compact ? stroke * 0.45 : stroke * 1.4,
      )
      ..color = style.glowColor;
    canvas.drawCircle(center, radius * 0.83, glowPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = SweepGradient(colors: style.colors).createShader(rect);
    canvas.drawCircle(center, radius * 0.83, ringPaint);

    if (style.sparkles && !compact) {
      final sparklePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = style.accentColor;
      for (final angle in [0.18, 1.95, 4.35]) {
        final point = Offset(
          center.dx + math.cos(angle) * radius * 0.78,
          center.dy + math.sin(angle) * radius * 0.78,
        );
        _drawDiamond(canvas, point, radius * 0.08, sparklePaint);
      }
    }
  }

  void _paintRubyRoyal(Canvas canvas, Size size, {required bool dark}) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final ringRadius = compact ? radius * 0.76 : radius * 0.80;
    final rect = Rect.fromCircle(center: center, radius: ringRadius);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact
          ? math.max(2.4, radius * 0.08)
          : math.max(5, radius * 0.18)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        compact ? radius * 0.035 : radius * 0.10,
      )
      ..color = dark ? const Color(0x6688001C) : const Color(0x66FF244A);
    canvas.drawCircle(center, ringRadius, glowPaint);

    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact
          ? math.max(2, radius * 0.055)
          : math.max(4, radius * 0.11)
      ..color = dark ? const Color(0xFF12090B) : const Color(0xFF26100A);
    canvas.drawCircle(center, ringRadius, shadowPaint);

    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = compact
          ? math.max(1.8, radius * 0.050)
          : math.max(2.8, radius * 0.075)
      ..shader = SweepGradient(
        colors: dark
            ? const [
                Color(0xFF2A0B10),
                Color(0xFFFFD77A),
                Color(0xFF7B1021),
                Color(0xFFFFE5A3),
                Color(0xFF1B0A0D),
                Color(0xFFB88A36),
                Color(0xFF2A0B10),
              ]
            : const [
                Color(0xFF6B180D),
                Color(0xFFFFECAD),
                Color(0xFFE0002B),
                Color(0xFFFFC857),
                Color(0xFF8A1E10),
                Color(0xFFFFF0BD),
                Color(0xFF6B180D),
              ],
      ).createShader(rect);
    canvas.drawCircle(center, ringRadius, goldPaint);

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact
          ? math.max(0.8, radius * 0.020)
          : math.max(1.2, radius * 0.030)
      ..color = dark ? const Color(0xFFE6B35D) : const Color(0xFFFFE1A1);
    canvas.drawCircle(center, radius * 0.65, innerPaint);

    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact
          ? math.max(0.8, radius * 0.020)
          : math.max(1.2, radius * 0.030)
      ..color = dark ? const Color(0xFF7D1825) : const Color(0xFFE01832);
    canvas.drawCircle(center, radius * 0.91, outerPaint);

    if (compact) {
      return;
    }

    final gemPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader =
          RadialGradient(
            colors: dark
                ? const [Color(0xFFFF4A64), Color(0xFF720013)]
                : const [Color(0xFFFF7A8C), Color(0xFFE0002B)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(center.dx, center.dy - radius * 0.84),
              radius: radius * 0.16,
            ),
          );
    _drawDiamond(
      canvas,
      Offset(center.dx, center.dy - radius * 0.84),
      radius * 0.14,
      gemPaint,
    );

    final accentPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = dark ? const Color(0xFFB50E25) : const Color(0xFFFF244A);
    for (final angle in [
      math.pi * 0.18,
      math.pi * 0.38,
      math.pi * 0.62,
      math.pi * 0.82,
      math.pi * 1.18,
      math.pi * 1.82,
    ]) {
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(angle) * radius * 0.88,
          center.dy + math.sin(angle) * radius * 0.88,
        ),
        math.max(2, radius * 0.045),
        accentPaint,
      );
    }

    final ornamentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, radius * 0.035)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD978);
    final bottomY = center.dy + radius * 0.86;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, bottomY - radius * 0.02),
        width: radius * 0.52,
        height: radius * 0.28,
      ),
      math.pi * 0.05,
      math.pi * 0.90,
      false,
      ornamentPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, bottomY - radius * 0.02),
        width: radius * 0.52,
        height: radius * 0.28,
      ),
      math.pi * 1.05,
      math.pi * 0.90,
      false,
      ornamentPaint,
    );
  }

  void _paintCrystalFeather(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius * 0.88);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(5, radius * 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.08)
      ..color = const Color(0x66EBCB8A);
    canvas.drawCircle(center, radius * 0.78, glowPaint);

    final darkBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(4, radius * 0.12)
      ..shader = const SweepGradient(
        colors: [
          Color(0xFF2C1A14),
          Color(0xFFFFDF9A),
          Color(0xFF1B1820),
          Color(0xFFB26D35),
          Color(0xFFFFF3C4),
          Color(0xFF2C1A14),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius * 0.79, darkBase);

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, radius * 0.035)
      ..color = const Color(0xFFFFE7B0);
    canvas.drawCircle(center, radius * 0.67, innerPaint);

    final featherPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, radius * 0.034);
    for (var i = 0; i < 18; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final t = (i / 17.0) * math.pi * 1.42 + math.pi * 0.80;
      final mirroredT = side < 0 ? t : math.pi - t;
      final start = Offset(
        center.dx + math.cos(mirroredT) * radius * 0.72,
        center.dy + math.sin(mirroredT) * radius * 0.72,
      );
      final end = Offset(
        center.dx + math.cos(mirroredT + side * 0.20) * radius * 0.97,
        center.dy + math.sin(mirroredT + side * 0.20) * radius * 0.97,
      );
      featherPaint.color = i % 3 == 0
          ? const Color(0xFFFFD98A)
          : (i % 3 == 1 ? const Color(0xFF76D8FF) : const Color(0xFFFF6F7E));
      canvas.drawLine(start, end, featherPaint);
    }

    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2, radius * 0.045)
      ..color = const Color(0xFFFFD98A);
    for (final angle in [math.pi * 1.18, math.pi * 1.82]) {
      final path = Path()
        ..moveTo(
          center.dx + math.cos(angle - 0.20) * radius * 0.83,
          center.dy + math.sin(angle - 0.20) * radius * 0.83,
        )
        ..quadraticBezierTo(
          center.dx + math.cos(angle) * radius * 1.13,
          center.dy + math.sin(angle) * radius * 1.13,
          center.dx + math.cos(angle + 0.20) * radius * 0.83,
          center.dy + math.sin(angle + 0.20) * radius * 0.83,
        );
      canvas.drawPath(path, goldPaint);
    }
  }

  void _paintAutumnBloom(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius * 0.84);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(5, radius * 0.17)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.10)
      ..color = const Color(0x66FF8A2A);
    canvas.drawCircle(center, radius * 0.76, glowPaint);

    final vinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.2, radius * 0.055)
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFFC071),
          Color(0xFF5A2C1F),
          Color(0xFFFF7A24),
          Color(0xFFFFE3AD),
          Color(0xFF6E3524),
          Color(0xFFFFC071),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius * 0.78, vinePaint);

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.3, radius * 0.028)
      ..color = const Color(0xFFFFD5A0);
    canvas.drawCircle(center, radius * 0.66, innerPaint);

    final petalPaint = Paint()..style = PaintingStyle.fill;
    for (final angle in [
      math.pi * 0.25,
      math.pi * 0.42,
      math.pi * 0.58,
      math.pi * 1.25,
      math.pi * 1.42,
      math.pi * 1.58,
    ]) {
      final flowerCenter = Offset(
        center.dx + math.cos(angle) * radius * 0.82,
        center.dy + math.sin(angle) * radius * 0.82,
      );
      for (var i = 0; i < 6; i++) {
        final petalAngle = angle + (i * math.pi / 3);
        final petalRect = Rect.fromCenter(
          center: Offset(
            flowerCenter.dx + math.cos(petalAngle) * radius * 0.07,
            flowerCenter.dy + math.sin(petalAngle) * radius * 0.07,
          ),
          width: radius * 0.12,
          height: radius * 0.20,
        );
        canvas.save();
        canvas.translate(petalRect.center.dx, petalRect.center.dy);
        canvas.rotate(petalAngle);
        petalPaint.color = i.isEven
            ? const Color(0xFFFF9A36)
            : const Color(0xFFFFC15A);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: petalRect.width,
            height: petalRect.height,
          ),
          petalPaint,
        );
        canvas.restore();
      }
      petalPaint.color = const Color(0xFFFFE0A3);
      canvas.drawCircle(flowerCenter, radius * 0.045, petalPaint);
    }

    final sparklePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFF0B8);
    for (final angle in [0.06, 0.95, 2.15, 3.8, 5.25]) {
      _drawDiamond(
        canvas,
        Offset(
          center.dx + math.cos(angle) * radius * 0.92,
          center.dy + math.sin(angle) * radius * 0.92,
        ),
        radius * 0.035,
        sparklePaint,
      );
    }
  }

  void _drawDiamond(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..lineTo(center.dx + size, center.dy)
      ..lineTo(center.dx, center.dy + size)
      ..lineTo(center.dx - size, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AvatarFramePainter oldDelegate) {
    return oldDelegate.frameKey != frameKey || oldDelegate.compact != compact;
  }
}

class _FrameStyle {
  const _FrameStyle({
    required this.colors,
    required this.glowColor,
    required this.accentColor,
    required this.strokeFactor,
    this.accentIcon,
    this.sparkles = false,
  });

  final List<Color> colors;
  final Color glowColor;
  final Color accentColor;
  final double strokeFactor;
  final IconData? accentIcon;
  final bool sparkles;

  static _FrameStyle fromKey(String? frameKey) {
    return switch (frameKey) {
      'normal_silver_ring' => const _FrameStyle(
        colors: [Color(0xFFE6E8EF), Color(0xFF8A92A6), Color(0xFFFFFFFF)],
        glowColor: Color(0x668A92A6),
        accentColor: Color(0xFFE6E8EF),
        strokeFactor: 0.075,
      ),
      'normal_blue_glow' => const _FrameStyle(
        colors: [Color(0xFF72E4FF), Color(0xFF316BFF), Color(0xFFB9F7FF)],
        glowColor: Color(0x88316BFF),
        accentColor: Color(0xFF72E4FF),
        strokeFactor: 0.075,
      ),
      'normal_soft_gold' => const _FrameStyle(
        colors: [Color(0xFFFFE7A3), Color(0xFFD59B2D), Color(0xFFFFF2C2)],
        glowColor: Color(0x66D59B2D),
        accentColor: Color(0xFFFFD978),
        strokeFactor: 0.078,
      ),
      'luxury_royal_gold' => const _FrameStyle(
        colors: [Color(0xFFFFF0A8), Color(0xFFC88516), Color(0xFFFFD978)],
        glowColor: Color(0x99F0C15A),
        accentColor: Color(0xFFFFD978),
        strokeFactor: 0.10,
        accentIcon: Icons.workspace_premium_rounded,
      ),
      'luxury_diamond_purple' => const _FrameStyle(
        colors: [Color(0xFFE4B5FF), Color(0xFF8B26D9), Color(0xFFFFFFFF)],
        glowColor: Color(0x998B26D9),
        accentColor: Color(0xFFE4B5FF),
        strokeFactor: 0.095,
        accentIcon: Icons.diamond_rounded,
        sparkles: true,
      ),
      'luxury_black_gold_crown' => const _FrameStyle(
        colors: [Color(0xFF0C0712), Color(0xFFFFD978), Color(0xFF4A2D0C)],
        glowColor: Color(0x88F0C15A),
        accentColor: Color(0xFFFFD978),
        strokeFactor: 0.105,
        accentIcon: Icons.emoji_events_rounded,
      ),
      'vip_bronze_star' => const _FrameStyle(
        colors: [Color(0xFFFFC073), Color(0xFF9B5B22), Color(0xFFFFE1B5)],
        glowColor: Color(0x88B66A2B),
        accentColor: Color(0xFFFFC073),
        strokeFactor: 0.095,
        accentIcon: Icons.star_rounded,
      ),
      'vip_silver_flame' => const _FrameStyle(
        colors: [Color(0xFFFFFFFF), Color(0xFFB9C2D3), Color(0xFF72E4FF)],
        glowColor: Color(0x99B9C2D3),
        accentColor: Color(0xFFE6E8EF),
        strokeFactor: 0.10,
        accentIcon: Icons.local_fire_department_rounded,
      ),
      'vip_gold_crown' => const _FrameStyle(
        colors: [Color(0xFFFFF4B8), Color(0xFFFFB800), Color(0xFFFFE27A)],
        glowColor: Color(0xAAF0C15A),
        accentColor: Color(0xFFFFD978),
        strokeFactor: 0.11,
        accentIcon: Icons.workspace_premium_rounded,
      ),
      'vip_platinum_diamond' => const _FrameStyle(
        colors: [Color(0xFFFFFFFF), Color(0xFFD8F6FF), Color(0xFF8B26D9)],
        glowColor: Color(0x99D8F6FF),
        accentColor: Color(0xFFFFFFFF),
        strokeFactor: 0.11,
        accentIcon: Icons.diamond_rounded,
        sparkles: true,
      ),
      'vip_royal_king' => const _FrameStyle(
        colors: [Color(0xFFFFD978), Color(0xFF6B16C8), Color(0xFFFFF1B8)],
        glowColor: Color(0xB3B000FF),
        accentColor: Color(0xFFFFD978),
        strokeFactor: 0.12,
        accentIcon: Icons.emoji_events_rounded,
        sparkles: true,
      ),
      _ => const _FrameStyle(
        colors: [Color(0xFFE6E8EF), Color(0xFF8A92A6), Color(0xFFFFFFFF)],
        glowColor: Color(0x00000000),
        accentColor: Color(0xFFE6E8EF),
        strokeFactor: 0.075,
      ),
    };
  }
}

// ── Animation layer ───────────────────────────────────────────────────────────

class _AnimatedFrameWrapper extends StatefulWidget {
  const _AnimatedFrameWrapper({
    required this.frameSize,
    required this.glowColor,
    required this.animType,
    required this.child,
  });

  final double frameSize;
  final Color glowColor;
  final _FrameAnimType animType;
  final Widget child;

  @override
  State<_AnimatedFrameWrapper> createState() => _AnimatedFrameWrapperState();
}

class _AnimatedFrameWrapperState extends State<_AnimatedFrameWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: switch (widget.animType) {
        _FrameAnimType.glowPulse => const Duration(milliseconds: 2000),
        _FrameAnimType.shimmerSweep => const Duration(milliseconds: 2800),
        _FrameAnimType.sparkleAura => const Duration(milliseconds: 1600),
      },
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _FrameAnimPainter(
          t: _ctrl.value,
          glowColor: widget.glowColor,
          animType: widget.animType,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _FrameAnimPainter extends CustomPainter {
  const _FrameAnimPainter({
    required this.t,
    required this.glowColor,
    required this.animType,
  });

  final double t;
  final Color glowColor;
  final _FrameAnimType animType;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    switch (animType) {
      case _FrameAnimType.glowPulse:
        _paintGlowPulse(canvas, center, radius);
      case _FrameAnimType.shimmerSweep:
        _paintShimmerSweep(canvas, center, radius);
      case _FrameAnimType.sparkleAura:
        _paintSparkleAura(canvas, center, radius);
    }
  }

  void _paintGlowPulse(Canvas canvas, Offset center, double radius) {
    final pulse = (math.sin(t * math.pi * 2) + 1) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.15
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.20)
      ..color = glowColor.withValues(alpha: 0.35 + pulse * 0.50);
    canvas.drawCircle(center, radius * 0.88, paint);
  }

  void _paintShimmerSweep(Canvas canvas, Offset center, double radius) {
    _paintGlowPulse(canvas, center, radius);
    final sweepStart = t * math.pi * 2;
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.11
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: sweepStart,
        endAngle: sweepStart + math.pi * 0.65,
        colors: [
          Colors.transparent,
          glowColor.withValues(alpha: 0.90),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.88));
    canvas.drawCircle(center, radius * 0.88, sweepPaint);
  }

  void _paintSparkleAura(Canvas canvas, Offset center, double radius) {
    _paintGlowPulse(canvas, center, radius);
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 4; i++) {
      final angle = (i * math.pi / 2) + t * math.pi * 2;
      final phase = (t + i * 0.25) % 1.0;
      final alpha = (math.sin(phase * math.pi * 2) + 1) / 2 * 0.70 + 0.20;
      dotPaint.color = glowColor.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(angle) * radius * 0.92,
          center.dy + math.sin(angle) * radius * 0.92,
        ),
        radius * 0.080,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FrameAnimPainter old) =>
      old.t != t || old.glowColor != glowColor || old.animType != animType;
}
