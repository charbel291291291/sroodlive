/// Full-screen immersive room background: custom image (or cover) with a
/// cinematic readability scrim, falling back to the v2 deep-violet gradient
/// with soft accent glows.
library;

import 'package:flutter/material.dart';

import '../../../../models/room.dart';
import '../../../theme/srood_room_theme.dart';

class SroodRoomBackground extends StatelessWidget {
  const SroodRoomBackground({
    required this.room,
    this.backgroundUrl,
    super.key,
  });

  final Room room;
  final String? backgroundUrl;

  @override
  Widget build(BuildContext context) {
    // Custom uploaded background takes priority over room cover.
    final imageUrl = backgroundUrl ?? room.coverUrl;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => const _GradientBackdrop(),
            )
          else
            const _GradientBackdrop(),

          // Layered cinematic overlay — darker top for header, center reveals
          // the background, darker bottom for chat/controls readability.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: imageUrl != null ? 0.78 : 0.0),
                  Colors.black.withValues(alpha: imageUrl != null ? 0.52 : 0.0),
                  Colors.black.withValues(alpha: imageUrl != null ? 0.62 : 0.0),
                  Colors.black.withValues(alpha: 0.92),
                ],
                stops: const [0.0, 0.28, 0.55, 1.0],
              ),
            ),
          ),
          // Subtle violet vignette on the sides over images.
          if (imageUrl != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    SroodRoomColors.bgRaised.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.transparent,
                    SroodRoomColors.bgRaised.withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.25, 0.75, 1.0],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Deep violet gradient with soft violet / electric / cyan glows — used when
/// the room has no custom background.
class _GradientBackdrop extends StatelessWidget {
  const _GradientBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.4,
              colors: [
                Color(0xFF2A1655),
                SroodRoomColors.bg,
                SroodRoomColors.bgDeep,
              ],
            ),
          ),
        ),
        // Violet glow — top center.
        Positioned(
          top: -80,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SroodRoomColors.violet.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Electric blue glow — bottom right.
        Positioned(
          bottom: 50,
          right: -40,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  SroodRoomColors.electric.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Cyan glow — bottom left.
        Positioned(
          bottom: 120,
          left: -30,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  SroodRoomColors.cyan.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
