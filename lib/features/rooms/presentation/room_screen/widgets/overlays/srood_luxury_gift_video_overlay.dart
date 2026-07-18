/// Full-stage luxury gift video overlay with the gift/receiver info card.
/// Video lifecycle is self-contained; the screen's 6-second force-clear
/// timer remains the hard backstop for stuck playback.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/srood_room_theme.dart';
import '../../models/srood_gift_events.dart';

/// Maps luxury gift codes to their full-screen video assets.
class SroodLuxuryGiftVideoConfig {
  const SroodLuxuryGiftVideoConfig({required this.assetPath});

  final String assetPath;

  static SroodLuxuryGiftVideoConfig? fromCode(String code) {
    switch (code) {
      case 'golden_lion':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/golden_lion_roar.mp4',
        );
      case 'baalbek_temple':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/baalbek_temple_royal.mp4',
        );
      case 'odrob':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/odrob_royal.mp4',
        );
      case 'lebanese_phoenix':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/lebanese_phoenix.mp4',
        );
      case 'cedar_throne':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/cedar_throne.mp4',
        );
      case 'phoenician_ship':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/phoenician_ship.mp4',
        );
      case 'jeita_crystal_palace':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/jeita_crystal_palace.mp4',
        );
      case 'byblos_royal_crown':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/byblos_royal_crown.mp4',
        );
      case 'egypt_royal':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/egypt_royal.mp4',
        );
      case 'iraq_royal':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/iraq_royal.mp4',
        );
      case 'jordan_royal':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/jordan_royal.mp4',
        );
      case 'lebanon_royal':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/lebanon_royal.mp4',
        );
      case 'palestine_royal':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/palestine_royal.mp4',
        );
      case 'saudi_arabia_royal':
        return const SroodLuxuryGiftVideoConfig(
          assetPath: 'assets/gift_effects/videos/saudi_arabia_royal.mp4',
        );
      default:
        return null;
    }
  }
}

class SroodLuxuryGiftVideoOverlay extends StatefulWidget {
  const SroodLuxuryGiftVideoOverlay({
    required this.playback,
    required this.onDone,
    this.soundEnabled = true,
    super.key,
  });

  final SroodActiveLuxuryGiftVideo playback;
  final VoidCallback onDone;
  final bool soundEnabled;

  @override
  State<SroodLuxuryGiftVideoOverlay> createState() =>
      _SroodLuxuryGiftVideoOverlayState();
}

class _SroodLuxuryGiftVideoOverlayState
    extends State<SroodLuxuryGiftVideoOverlay> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  // Guards against the position listener firing onDone repeatedly once the
  // video reaches its end (the listener ticks every frame).
  bool _completed = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset(widget.playback.assetPath)
      ..setVolume(widget.soundEnabled ? 1.0 : 0.0)
      ..initialize().then((_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _ready = true;
        });

        _controller.play();
      });

    _controller.addListener(_handleVideoState);
  }

  void _handleVideoState() {
    if (_completed || !_controller.value.isInitialized) {
      return;
    }

    if (_controller.value.position >= _controller.value.duration) {
      _completed = true;
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleVideoState);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;

    // The stage starts below the header zone so room controls stay visible.
    final double topBound = mq.padding.top + kToolbarHeight;

    // Never cover the bottom action bar or gesture-navigation handles.
    const double kBottomBarH = 88.0;
    final double bottomBound = kBottomBarH + mq.padding.bottom;

    // BoxFit.cover fills the stage width (no letterbox bars); ClipRect
    // confines overflow. RepaintBoundary isolates the video texture layer
    // from the frequently-rebuilding room UI.
    final Widget videoChild = _ready
        ? RepaintBoundary(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          )
        : const Center(child: CircularProgressIndicator());

    // Info card spans ~88% of screen width, centred at the stage bottom.
    final double cardHPad = screenW * 0.06;

    return Positioned(
      key: widget.playback.key,
      top: topBound,
      bottom: bottomBound,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(child: SizedBox.expand(child: videoChild)),
            Positioned(
              bottom: 14,
              left: cardHPad,
              right: cardHPad,
              child: _LuxuryGiftInfoCard(
                giftName: widget.playback.giftName,
                receiverName: widget.playback.receiverName,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LuxuryGiftInfoCard extends StatelessWidget {
  const _LuxuryGiftInfoCard({
    required this.giftName,
    required this.receiverName,
  });

  final String giftName;
  final String receiverName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2B1A45).withValues(alpha: 0.92),
            SroodRoomColors.bg.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd + 2),
        border: Border.all(
          color: const Color(0xFFD4A017).withValues(alpha: 0.75),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: SroodRoomColors.gold.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            giftName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: SroodRoomDims.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_rounded,
                color: Color(0xFFD4A017),
                size: 13,
              ),
              const SizedBox(width: SroodRoomDims.space4),
              Flexible(
                child: Text(
                  receiverName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontSize: SroodRoomDims.textMd,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
