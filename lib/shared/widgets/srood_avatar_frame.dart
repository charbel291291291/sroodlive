/// Frame System v2 — the single reusable framed-avatar component.
///
/// One widget for every avatar location: profile, room mic seats, chat,
/// leaderboards, search, follower lists, agency screens, and admin previews.
/// It resolves the stored frame code through [FrameRegistry] (legacy aliases,
/// unknown ids, expired entitlements, fallbacks) and renders through exactly
/// one of:
///
/// - the proven legacy pipeline ([AvatarWithFrame]) — pixel-identical for
///   every pre-v2 frame code, so adopting this widget causes no visual drift;
/// - a v2 network catalog asset (with loading/error fallbacks);
/// - the v2 VIP tier placeholder painter (opt-in via [preferV2TierArt], or
///   the database-controlled `frames_v2_rendering_enabled` flag when
///   [preferV2TierArt] is left null — see [FramesV2RenderingFlagService]).
///
/// Performance rules baked in: assets decode at display size, at most one
/// animation controller per instance (created only when an animated frame is
/// actually visible and motion is allowed), controllers are disposed, tickers
/// respect [TickerMode], and reduced-motion devices always get a static frame.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/frames/frame_registry.dart';
import '../../core/frames/frame_tier_painter.dart';
import '../../core/frames/frames_v2_rendering_flag_service.dart';
import '../../core/frames/srood_frame.dart';
import 'avatar_with_frame.dart';

/// Preset avatar diameters used across the app.
enum SroodAvatarFrameSize {
  /// Chat rows, compact lists.
  small(36),

  /// Room mic seats, standard lists.
  medium(48),

  /// Profile headers, previews.
  large(96);

  const SroodAvatarFrameSize(this.avatarDiameter);

  final double avatarDiameter;
}

class SroodAvatarFrame extends StatefulWidget {
  const SroodAvatarFrame({
    this.imageUrl,
    this.frameCode,
    this.vipLevel = 0,
    this.sizePreset,
    this.size,
    this.animate = false,
    this.preferV2TierArt,
    this.showVipBadge = false,
    this.isLoading = false,
    this.fallbackIcon = Icons.person_rounded,
    this.compactOverride,
    this.frameOverride,
    super.key,
  }) : assert(
         sizePreset != null || size != null,
         'Provide sizePreset or a custom size',
       );

  final String? imageUrl;

  /// Raw stored frame code (legacy `frame_key` or v2 `code`); null → the
  /// implicit VIP tier frame when [vipLevel] > 0, otherwise no frame.
  final String? frameCode;

  /// The avatar owner's EFFECTIVE VIP level (expired VIP must be passed
  /// as 0 — use `VipFeatures.effectiveVipLevel`).
  final int vipLevel;

  final SroodAvatarFrameSize? sizePreset;

  /// Custom avatar diameter; overrides [sizePreset].
  final double? size;

  /// Opt-in animation. Even when true, animation only runs for frames that
  /// declare an animated treatment and when the platform allows motion.
  final bool animate;

  /// Render VIP tiers with the v2 placeholder art instead of the legacy
  /// bundled bitmaps. Explicit `true`/`false` always wins (used by admin
  /// preview screens). Left `null`, this follows the database-controlled
  /// `frames_v2_rendering_enabled` flag (see
  /// [FramesV2RenderingFlagService.instance]), which defaults to `false` —
  /// so until the flag is loaded or an admin enables it, every avatar in the
  /// app renders through the exact current legacy pipeline.
  final bool? preferV2TierArt;

  final bool showVipBadge;

  /// Shimmer placeholder while the owning screen is still loading data.
  final bool isLoading;

  final IconData fallbackIcon;

  /// Forces the legacy frame ring's compact styling on or off, bypassing the
  /// default size-based heuristic (`avatarDiameter < 44`). Used by call
  /// sites where compactness is a data-driven distinction (e.g. host vs.
  /// regular mic seats sharing the same avatar size) rather than a function
  /// of the avatar's on-screen size.
  final bool? compactOverride;

  /// Admin-only: render this exact frame instead of resolving [frameCode]
  /// through [FrameRegistry]. Production call sites leave this null.
  ///
  /// The frame editor's live preview needs to draw a frame that has no catalog
  /// row yet, and must draw it through this same widget so what an admin
  /// approves is what users see. Entitlement checks are skipped — the override
  /// grants nothing, it only chooses what to paint.
  final SroodFrame? frameOverride;

  double get _avatarDiameter =>
      size ??
      sizePreset?.avatarDiameter ??
      SroodAvatarFrameSize.medium.avatarDiameter;

  @override
  State<SroodAvatarFrame> createState() => _SroodAvatarFrameState();
}

class _SroodAvatarFrameState extends State<SroodAvatarFrame>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  FrameRenderSpec _resolve() {
    final preferV2 =
        widget.preferV2TierArt ?? FramesV2RenderingFlagService.instance.value;
    final override = widget.frameOverride;
    if (override != null) {
      return FrameRegistry.instance.specForFrame(
        override,
        preferV2TierArt: preferV2,
      );
    }
    return FrameRegistry.instance.resolveRender(
      rawCode: widget.frameCode,
      effectiveVipLevel: widget.vipLevel,
      preferV2TierArt: preferV2,
    );
  }

  bool _motionAllowed(BuildContext context) =>
      widget.animate && !MediaQuery.of(context).disableAnimations;

  /// Lazily creates (or tears down) the single animation controller so a
  /// non-animated frame never pays for a ticker. TickerMode still gates the
  /// ticker when the route is inactive.
  void _syncController({required bool needed}) {
    if (needed && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      )..repeat();
    } else if (!needed && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarDiameter = widget._avatarDiameter;
    final compact = widget.compactOverride ?? avatarDiameter < 44;

    if (widget.isLoading) {
      _syncController(needed: false);
      return _LoadingCircle(diameter: avatarDiameter);
    }

    final spec = _resolve();

    switch (spec.mode) {
      case FrameRenderMode.none:
      case FrameRenderMode.legacyDelegate:
        // The legacy pipeline manages its own (already profiled) animation
        // layer; no v2 controller needed.
        _syncController(needed: false);
        return AvatarWithFrame(
          imageUrl: widget.imageUrl,
          radius: avatarDiameter / 2,
          frameKey: spec.mode == FrameRenderMode.legacyDelegate
              ? spec.legacyKey
              : null,
          vipLevel: widget.vipLevel,
          autoVipFrame: false, // registry already resolved the implicit frame
          compact: compact,
          showVipBadge: widget.showVipBadge,
          fallbackIcon: widget.fallbackIcon,
          animated: spec.animated && _motionAllowed(context),
        );

      case FrameRenderMode.tierPainter:
        final animating = spec.animated && _motionAllowed(context);
        _syncController(needed: animating);
        return _framedBox(
          avatarDiameter: avatarDiameter,
          compact: compact,
          overlay: animating
              ? RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _controller!,
                    builder: (_, _) => CustomPaint(
                      painter: SroodTierFramePainter(
                        tier: spec.vipTier,
                        t: _controller!.value,
                        compact: compact,
                      ),
                    ),
                  ),
                )
              : CustomPaint(
                  painter: SroodTierFramePainter(
                    tier: spec.vipTier,
                    compact: compact,
                  ),
                ),
        );

      case FrameRenderMode.bundledAsset:
        _syncController(needed: false);
        final bundledBox = avatarDiameter * 1.35;
        final bundledDpr = MediaQuery.of(context).devicePixelRatio;
        return _framedBox(
          avatarDiameter: avatarDiameter,
          compact: compact,
          overlay: Image.asset(
            spec.assetPath!,
            fit: BoxFit.contain,
            cacheWidth: (bundledBox * bundledDpr).round(),
            cacheHeight: (bundledBox * bundledDpr).round(),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );

      case FrameRenderMode.networkAsset:
        _syncController(needed: false);
        final frameBox = avatarDiameter * 1.35;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        return _framedBox(
          avatarDiameter: avatarDiameter,
          compact: compact,
          overlay: CachedNetworkImage(
            imageUrl: spec.assetUrl!,
            fit: BoxFit.contain,
            memCacheWidth: (frameBox * dpr).round(),
            memCacheHeight: (frameBox * dpr).round(),
            // Missing/broken catalog asset → tier painter for VIP frames,
            // otherwise a clean unframed avatar (never a broken image).
            errorWidget: (_, _, _) => (spec.frame?.vipLevel ?? 0) > 0
                ? CustomPaint(
                    painter: SroodTierFramePainter(
                      tier: spec.frame!.vipLevel!,
                      compact: compact,
                    ),
                  )
                : const SizedBox.shrink(),
            placeholder: (_, _) => const SizedBox.shrink(),
          ),
        );
    }
  }

  /// Avatar photo (via the shared frameless pipeline) + a square frame
  /// overlay 1.35× the avatar, matching the legacy VIP frame ratio so v2
  /// frames read the same size everywhere.
  Widget _framedBox({
    required double avatarDiameter,
    required bool compact,
    required Widget overlay,
  }) {
    final frameBox = avatarDiameter * 1.35;
    return SizedBox(
      width: frameBox,
      height: frameBox,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AvatarWithFrame(
            imageUrl: widget.imageUrl,
            radius: avatarDiameter / 2 * 0.94,
            vipLevel: widget.vipLevel,
            autoVipFrame: false,
            compact: compact,
            showVipBadge: widget.showVipBadge,
            fallbackIcon: widget.fallbackIcon,
          ),
          Positioned.fill(child: IgnorePointer(child: overlay)),
        ],
      ),
    );
  }
}

class _LoadingCircle extends StatelessWidget {
  const _LoadingCircle({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter * 1.35,
      height: diameter * 1.35,
      child: Center(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
      ),
    );
  }
}
