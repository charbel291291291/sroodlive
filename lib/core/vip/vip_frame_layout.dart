// =============================================================================
// VIP frame layout calibration (UI-only).
//
// Each `assets/vip/vipN/frame.webp` has a different transparent opening - the
// hole the avatar shows through. The openings vary in both size (min dimension
// 0.54 .. 0.93 of the frame) and vertical centre (-0.058 .. +0.036), so a single
// avatar size / centre cannot fit every tier. This helper returns per-tier
// values so the avatar sits cleanly inside each frame's opening.
//
// Values are FRACTIONS of the square frame box, so they scale with any render
// size. They were derived by measuring the alpha opening of every frame asset:
//   avatarFillRatio  = min(openingW, openingH) * ~0.86   (avatar diameter)
//   avatarDyFraction = opening vertical-centre offset    (+ = move avatar down)
//
// This is pure rendering math - no VIP / wallet / business logic. To re-tune
// after replacing an asset, re-measure that frame's opening and update its row.
// =============================================================================

class VipFrameLayout {
  const VipFrameLayout({
    required this.avatarFillRatio,
    required this.avatarDyFraction,
  });

  /// Avatar diameter as a fraction of the frame box (0..1).
  final double avatarFillRatio;

  /// Vertical offset of the avatar centre as a fraction of the frame box.
  /// Positive moves the avatar down, negative moves it up.
  final double avatarDyFraction;

  // Measured table for VIP 1..9 (see header for how these were derived).
  static const Map<int, VipFrameLayout> _table = {
    1: VipFrameLayout(avatarFillRatio: 0.66, avatarDyFraction: 0.006),
    2: VipFrameLayout(avatarFillRatio: 0.52, avatarDyFraction: -0.035),
    3: VipFrameLayout(avatarFillRatio: 0.79, avatarDyFraction: 0.036),
    4: VipFrameLayout(avatarFillRatio: 0.48, avatarDyFraction: -0.058),
    5: VipFrameLayout(avatarFillRatio: 0.76, avatarDyFraction: 0.020),
    6: VipFrameLayout(avatarFillRatio: 0.57, avatarDyFraction: -0.031),
    7: VipFrameLayout(avatarFillRatio: 0.78, avatarDyFraction: -0.022),
    8: VipFrameLayout(avatarFillRatio: 0.81, avatarDyFraction: 0.013),
    9: VipFrameLayout(avatarFillRatio: 0.74, avatarDyFraction: 0.034),
  };

  /// Neutral fallback for unknown / non-VIP levels - a centred avatar that
  /// comfortably clears any frame rim.
  static const VipFrameLayout _fallback = VipFrameLayout(
    avatarFillRatio: 0.66,
    avatarDyFraction: 0.0,
  );

  /// Calibration for [level]. Clamped to the 1..9 table; anything outside
  /// returns the safe [_fallback].
  static VipFrameLayout of(int? level) {
    return _table[level ?? 0] ?? _fallback;
  }
}
