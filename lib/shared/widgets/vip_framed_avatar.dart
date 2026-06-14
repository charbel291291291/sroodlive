import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// VIP frame asset mapping
// Original file names preserved exactly as provided.
// ---------------------------------------------------------------------------

/// Returns the asset path for the PNG frame that matches [level] (1-10).
/// Returns `null` for level 0 or any out-of-range value.
/// Returns the asset path for the VIP PNG frame matching [level] (1–9).
/// Returns `null` for level 0 or out-of-range. VIP10 is not supported.
String? vipFrameAssetPath(int level) => switch (level.clamp(0, 9)) {
  1 => 'assets/images/vip_frames/11.png',
  2 => 'assets/images/vip_frames/2.png',
  3 => 'assets/images/vip_frames/3.png',
  4 => 'assets/images/vip_frames/vip4.png',
  5 => 'assets/images/vip_frames/5.png',
  6 => 'assets/images/vip_frames/6.png',
  7 => 'assets/images/vip_frames/7.png',
  8 => 'assets/images/vip_frames/88.png',
  9 => 'assets/images/vip_frames/99.png',
  _ => null,
};

// ---------------------------------------------------------------------------
// VipFramedAvatar widget
// ---------------------------------------------------------------------------

/// A reusable avatar widget that composites a user photo with a VIP PNG frame.
///
/// Layout (Stack):
///   - **Bottom** : circular, clipped profile image (`BoxFit.cover`)
///   - **Top**    : PNG frame overlay (`BoxFit.contain`, `IgnorePointer`)
///
/// Parameters
/// ----------
/// [size]             - outer bounding box (frame fills this completely).
/// [imageUrl]         - network URL for the profile photo; null shows [fallback].
/// [vipLevel]         - 1-10 renders the matching PNG; null or 0 = avatar only.
/// [innerAvatarScale] - fraction of [size] occupied by the clipped photo
///                      (default 0.74, i.e. avatar = 74 % of frame dimension).
/// [fallback]         - widget shown when no URL or the image fails to load.
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
    final level = (vipLevel ?? 0).clamp(0, 9);
    final framePath = level > 0 ? vipFrameAssetPath(level) : null;
    final innerSize = size * innerAvatarScale.clamp(0.4, 1.0);
    final url = imageUrl?.trim();

    // VIP wreath frames have a crown on top + a "VIP" label at the bottom, so
    // the visual opening sits slightly below centre. Nudge the photo down to
    // land inside the opening instead of behind the crown.
    final avatarDy = framePath != null ? size * 0.045 : 0.0;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // -- Bottom: circular, clipped profile photo ----------------------
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

          // -- Top: VIP PNG frame overlay ------------------------------------
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

// ---------------------------------------------------------------------------
// Internal fallback avatar (matches the style used in AvatarWithFrame)
// ---------------------------------------------------------------------------

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
      child: Icon(Icons.person_rounded, color: Colors.white, size: size * 0.50),
    );
  }
}
