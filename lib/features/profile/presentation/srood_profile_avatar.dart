/// Fixed-shell profile avatar: the shell diameter is chosen by the header
/// (108–124px by screen width) and never changes with VIP tier, frame art,
/// or upload state. The VIP webp frame renders as an overlay inside the
/// shell using the existing per-tier [VipFrameLayout] calibration, and the
/// camera button keeps a 44px hit target.
library;

import 'package:flutter/material.dart';

import '../../../core/vip/vip_frame_layout.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../utils/vip_assets.dart';
import 'srood_profile_theme.dart';

class SroodProfileAvatar extends StatelessWidget {
  const SroodProfileAvatar({
    required this.shellSize,
    required this.avatarUrl,
    required this.frameKey,
    required this.vipLevel,
    required this.isUploadingAvatar,
    required this.isArabic,
    required this.onAvatarTap,
    required this.onFrameTap,
    this.animatedFrame = false,
    super.key,
  });

  final double shellSize;
  final String? avatarUrl;
  final String? frameKey;
  final int vipLevel;
  final bool isUploadingAvatar;
  final bool isArabic;
  final VoidCallback onAvatarTap;
  final VoidCallback onFrameTap;

  /// Whether the selected custom frame is an animated premium frame.
  final bool animatedFrame;

  @override
  Widget build(BuildContext context) {
    // The premium webp VIP frame is used when the user has no custom frame
    // selected. Per-tier calibration sizes/centres the avatar photo so it
    // fits that tier's opening — existing behavior, unchanged.
    final showWebpFrame =
        VipAssets.hasVip(vipLevel) &&
        (frameKey == null || frameKey!.trim().isEmpty);
    final frameLayout = VipFrameLayout.of(vipLevel);
    final avatarRadius = showWebpFrame
        ? (shellSize * frameLayout.avatarFillRatio) / 2
        : shellSize * 0.42;
    final avatarDy = showWebpFrame
        ? shellSize * frameLayout.avatarDyFraction
        : 0.0;

    return RepaintBoundary(
      child: SizedBox(
        width: shellSize,
        height: shellSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Single soft halo — controlled, no stacked rings.
            Container(
              width: shellSize * 0.86,
              height: shellSize * 0.86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SroodProfileColors.violetSoft.withValues(alpha: 0.38),
                    SroodProfileColors.violet.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),

            // Avatar photo (tap opens the frame picker, as before).
            Transform.translate(
              offset: Offset(0, avatarDy),
              child: Semantics(
                label: isArabic ? 'إطار الصورة الشخصية' : 'Avatar frame picker',
                button: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onFrameTap,
                  child: AvatarWithFrame(
                    imageUrl: avatarUrl,
                    radius: avatarRadius,
                    frameKey: frameKey,
                    vipLevel: vipLevel,
                    showVipBadge: false,
                    autoVipFrame: false,
                    compact: true,
                    animated: animatedFrame,
                  ),
                ),
              ),
            ),

            // VIP webp frame overlay — pure decoration inside the fixed shell;
            // never affects layout.
            if (showWebpFrame)
              IgnorePointer(
                child: Image.asset(
                  VipAssets.frame(vipLevel),
                  width: shellSize,
                  height: shellSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),

            // Camera button — 44px hit target, compact visual.
            PositionedDirectional(
              end: -6,
              bottom: -6,
              child: Semantics(
                label: isArabic ? 'تغيير الصورة الشخصية' : 'Change avatar',
                button: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: isUploadingAvatar ? null : onAvatarTap,
                  child: SizedBox(
                    width: SroodProfileDims.touchTarget,
                    height: SroodProfileDims.touchTarget,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF5D070), Color(0xFFD4A017)],
                          ),
                          border: Border.all(
                            color: SroodProfileColors.card,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: SroodProfileColors.gold.withValues(
                                alpha: 0.30,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          isUploadingAvatar
                              ? Icons.hourglass_top_rounded
                              : Icons.camera_alt_rounded,
                          color: const Color(0xFF160B26),
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
