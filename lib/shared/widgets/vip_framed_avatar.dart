import 'package:flutter/material.dart';

import '../../core/vip/vip_spec.dart';

// vipFrameAssetPath and vipFrameScale live in vip_spec.dart.
// Re-export so existing imports of this file keep working without changes.
export '../../core/vip/vip_spec.dart' show vipFrameAssetPath, vipFrameScale;

// ─────────────────────────────────────────────────────────────────────────────
// VipFramedAvatar
// ─────────────────────────────────────────────────────────────────────────────

/// A reusable avatar widget that composites a user photo with a VIP PNG frame.
///
/// Layout (Stack):
///   - **Bottom** : circular, clipped profile image (BoxFit.cover)
///   - **Top**    : PNG frame overlay (BoxFit.contain, IgnorePointer)
///
/// [size]             — outer bounding box (frame fills this completely).
/// [imageUrl]         — network URL for the profile photo; null shows [fallback].
/// [vipLevel]         — 1-9 renders the matching PNG; null or 0 = avatar only.
/// [innerAvatarScale] — fraction of [size] occupied by the clipped photo
///                      (default 0.74, consistent with vipFrameScale(level)=1.35).
/// [fallback]         — widget shown when no URL or the image fails to load.
class VipFramedAvatar extends StatelessWidget {
  const VipFramedAvatar({
    required this.size,
    this.imageUrl,
    this.vipLevel,
    this.innerAvatarScale = 0.74,
    this.fallback,
    super.key,
  });

  final double size;
  final String? imageUrl;
  final int? vipLevel;
  final double innerAvatarScale;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final level     = (vipLevel ?? 0).clamp(0, 9);
    final framePath = level > 0 ? vipFrameAssetPath(level) : null;
    final innerSize = size * innerAvatarScale.clamp(0.4, 1.0);
    final url       = imageUrl?.trim();

    // VIP wreath frames have a crown on top; nudge the photo down slightly so
    // it sits inside the opening rather than behind the crown.
    final avatarDy = framePath != null ? size * 0.045 : 0.0;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(0, avatarDy),
            child: SizedBox.square(
              dimension: innerSize,
              child: ClipOval(
                child: url != null && url.isNotEmpty
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: innerSize,
                        height: innerSize,
                        errorBuilder: (_, _, _) =>
                            fallback ?? _VipAvatarFallback(size: innerSize),
                      )
                    : fallback ?? _VipAvatarFallback(size: innerSize),
              ),
            ),
          ),
          if (framePath != null)
            IgnorePointer(
              child: SizedBox.square(
                dimension: size,
                child: Image.asset(
                  framePath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VipAvatarFallback extends StatelessWidget {
  const _VipAvatarFallback({required this.size});

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
      child:
          Icon(Icons.person_rounded, color: Colors.white, size: size * 0.50),
    );
  }
}
