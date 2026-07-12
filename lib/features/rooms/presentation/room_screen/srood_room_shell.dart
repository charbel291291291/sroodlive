/// Layout-only shell for the live room screen.
///
/// Owns the zone geometry — background, safe-area column (header → banners →
/// stage → chat), floating music chip, pinned bottom bar, and full-screen
/// overlays — while owning **no state**. The screen state class supplies each
/// zone as a prebuilt slot; this keeps state ownership untouched and makes
/// the layout independently testable across widths.
library;

import 'package:flutter/material.dart';

import '../theme/srood_room_theme.dart';

class SroodRoomShell extends StatelessWidget {
  const SroodRoomShell({
    required this.background,
    required this.header,
    required this.banners,
    required this.stage,
    required this.chatFeed,
    required this.bottomBar,
    this.musicChip,
    this.overlays = const <Widget>[],
    super.key,
  });

  /// Full-screen backdrop (image / gradient + scrim).
  final Widget background;

  /// Top zone: header bar (+ announcement strip).
  final Widget header;

  /// Event banners (gift / VIP entry / user entry) below the header.
  final List<Widget> banners;

  /// Main stage: mic grid, PK, counters.
  final Widget stage;

  /// Scrollable chat feed above the bottom bar.
  final Widget chatFeed;

  /// Floating now-playing chip (nullable — hidden when no music).
  final Widget? musicChip;

  /// Pinned bottom action bar (keyboard-aware).
  final Widget bottomBar;

  /// Full-screen overlays stacked above everything (gift events, luxury
  /// videos, lucky bag, closing overlay...).
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom;
    final kbHeight = media.viewInsets.bottom;
    final keyboardOpen = kbHeight > 0;

    // Chat zone height: fraction of screen with clamps so mic seats keep
    // priority on short screens.
    final chatHeight = (media.size.height * SroodRoomDims.chatHeightFraction)
        .clamp(SroodRoomDims.chatHeightMin, SroodRoomDims.chatHeightMax);

    // Space reserved under the chat so the pinned bottom bar (and gesture
    // area) never covers messages.
    final lowerInteractionReserve = keyboardOpen
        ? SroodRoomDims.bottomBarHeight + 2.0
        : SroodRoomDims.bottomBarHeight + 80.0 + bottomPad;

    return Stack(
      children: [
        // ── 1. Immersive background ─────────────────────────────────────────
        RepaintBoundary(child: background),

        // ── 2. Fixed column: header → banners → stage → chat ────────────────
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SroodRoomDims.gutter,
                  0,
                  SroodRoomDims.gutter,
                  0,
                ),
                child: header,
              ),
              ...banners,
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.0),
                              Colors.black.withValues(alpha: 0.30),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            SroodRoomDims.space2,
                            SroodRoomDims.space4,
                            SroodRoomDims.space2,
                            SroodRoomDims.space6,
                          ),
                          child: stage,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: chatHeight,
                      child: RepaintBoundary(child: chatFeed),
                    ),
                    SizedBox(height: lowerInteractionReserve),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 3. Floating music chip ──────────────────────────────────────────
        if (musicChip != null)
          Positioned(
            bottom: bottomPad + SroodRoomDims.bottomBarHeight + 80,
            left: 0,
            right: 0,
            child: musicChip!,
          ),

        // ── 4. Pinned bottom action bar (keyboard-aware) ────────────────────
        Positioned(bottom: kbHeight, left: 0, right: 0, child: bottomBar),

        // ── 5. Overlays ─────────────────────────────────────────────────────
        ...overlays,
      ],
    );
  }
}
