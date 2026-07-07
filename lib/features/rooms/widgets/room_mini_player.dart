import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/room_music_service.dart';

// ── RoomMiniPlayer ─────────────────────────────────────────────────────────────
//
// Full-width docked now-playing bar that lives directly above the bottom
// action bar. Replaces the old floating draggable bubble.
//
// States:
//   1. Hidden      — no active music         →  SizedBox.shrink()
//   2. Active dock — music playing/paused    →  compact dock + progress
//
// Positioning is handled by the parent (room_details_screen) as an overlay
// above the bottom action bar so chat keeps its vertical space.
// ─────────────────────────────────────────────────────────────────────────────

class RoomMiniPlayer extends StatefulWidget {
  const RoomMiniPlayer({
    super.key,
    required this.musicService,
    this.onTap,
    this.onStop,
    this.onNonControllerAction,
    this.canManage = false,
    this.isManager = false,
    this.isArabic = false,
    this.controllerUserId,
    this.currentUserId,
    this.keyboardOpen = false,
  });

  final RoomMusicService musicService;

  /// Opens the full music panel.
  final VoidCallback? onTap;

  /// Stops music for the whole room. Only wired when [canManage] is true.
  final VoidCallback? onStop;

  /// Called when a non-controller taps a control.
  final VoidCallback? onNonControllerAction;

  /// True only for the music controller (can play/pause, stop).
  final bool canManage;

  /// True for room owners, hosts, moderators (can see idle "Add music" row).
  final bool isManager;

  final bool isArabic;
  final String? controllerUserId;
  final String? currentUserId;

  /// When true the dock collapses to zero height so the keyboard isn't covered.
  final bool keyboardOpen;

  @override
  State<RoomMiniPlayer> createState() => _RoomMiniPlayerState();
}

class _RoomMiniPlayerState extends State<RoomMiniPlayer>
    with TickerProviderStateMixin {
  // Three independent eq bar controllers — natural stagger without explicit offsets.
  late final AnimationController _eq1;
  late final AnimationController _eq2;
  late final AnimationController _eq3;

  @override
  void initState() {
    super.initState();
    _eq1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..repeat(reverse: true);
    _eq2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 590))
      ..repeat(reverse: true);
    _eq3 = AnimationController(vsync: this, duration: const Duration(milliseconds: 350))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _eq1.dispose();
    _eq2.dispose();
    _eq3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keyboardOpen) return const SizedBox.shrink();
    final dockWidth =
        (MediaQuery.sizeOf(context).width * 0.68).clamp(220.0, 292.0).toDouble();

    return ListenableBuilder(
      listenable: widget.musicService,
      builder: (context, _) {
        final svc = widget.musicService;

        return Align(
          alignment: widget.isArabic ? Alignment.centerLeft : Alignment.centerRight,
          child: SizedBox(
            width: dockWidth,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SizeTransition(
                  sizeFactor: anim,
                  axis: Axis.horizontal,
                  alignment:
                      widget.isArabic ? Alignment.centerLeft : Alignment.centerRight,
                  child: child,
                ),
              ),
              child: svc.isActive
                  ? _ActiveDock(
                      key: const ValueKey('dock-active'),
                      svc: svc,
                      canManage: widget.canManage,
                      isArabic: widget.isArabic,
                      eq1: _eq1,
                      eq2: _eq2,
                      eq3: _eq3,
                      onTap: widget.onTap,
                      onPlayPause: svc.playPause,
                    )
                  : const SizedBox.shrink(key: ValueKey('dock-hidden')),
            ),
          ),
        );
      },
    );
  }
}

// ── Active dock ───────────────────────────────────────────────────────────────

class _ActiveDock extends StatelessWidget {
  const _ActiveDock({
    super.key,
    required this.svc,
    required this.canManage,
    required this.isArabic,
    required this.eq1,
    required this.eq2,
    required this.eq3,
    this.onTap,
    this.onPlayPause,
  });

  static const _kGold = Color(0xFFFFD76B);
  static const _kPurple = Color(0xFF8B26D9);

  final RoomMusicService svc;
  final bool canManage;
  final bool isArabic;
  final AnimationController eq1;
  final AnimationController eq2;
  final AnimationController eq3;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;

  @override
  Widget build(BuildContext context) {
    final song = svc.currentSong!;
    final total = svc.duration ?? Duration.zero;
    final pos = svc.position;
    final progress = total.inMilliseconds > 0
        ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final isPlaying = svc.isPlaying;
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 38,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0D0520).withValues(alpha: 0.62),
              const Color(0xFF060210).withValues(alpha: 0.96),
            ],
          ),
          border: Border.all(
            color: isPlaying
                ? _kGold.withValues(alpha: 0.34)
                : _kPurple.withValues(alpha: 0.28),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // ── Main content row ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                textDirection: dir,
                children: [
                  // Album art / loading indicator
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3A1375), Color(0xFF8B26D9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: _kPurple.withValues(alpha: 0.45),
                        width: 0.8,
                      ),
                    ),
                    child: svc.isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(7),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          )
                        : Icon(
                            Icons.music_note_rounded,
                            color: Colors.white.withValues(alpha: 0.80),
                            size: 15,
                          ),
                  ),
                  const SizedBox(width: 8),

                  // Title + artist
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: isArabic
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox.shrink(),
                        Offstage(
                          offstage: true,
                          child: Text(
                          song.artist.isNotEmpty
                              ? song.artist
                              : (isArabic ? 'غرفة سرود' : 'Srood Room'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.none,
                            height: 1.1,
                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Animated equalizer bars
                  _EqualizerBars(
                    isPlaying: isPlaying,
                    eq1: eq1,
                    eq2: eq2,
                    eq3: eq3,
                  ),
                  const SizedBox(width: 8),

                  // Play / pause — controller only
                  if (canManage) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        onPlayPause?.call();
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.28),
                          border: Border.all(
                            color: isPlaying
                                ? _kGold.withValues(alpha: 0.38)
                                : Colors.white.withValues(alpha: 0.16),
                            width: 0.9,
                          ),
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: isPlaying
                              ? _kGold
                              : Colors.white.withValues(alpha: 0.68),
                          size: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ] else ...[
                    Icon(
                      Icons.lock_rounded,
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Open panel chevron
                  Icon(
                    isArabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ],
              ),
            ),

            // ── Progress bar (2 px at very bottom) ────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LayoutBuilder(
                builder: (_, bc) => SizedBox(
                  height: 2,
                  child: Row(
                    children: [
                      Container(
                        width: bc.maxWidth * progress,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF8B26D9), Color(0xFFFFD76B)],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ],
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

// ── Equalizer bars ────────────────────────────────────────────────────────────

class _EqualizerBars extends StatelessWidget {
  const _EqualizerBars({
    required this.isPlaying,
    required this.eq1,
    required this.eq2,
    required this.eq3,
  });

  static const _kGold = Color(0xFFFFD76B);

  final bool isPlaying;
  final AnimationController eq1;
  final AnimationController eq2;
  final AnimationController eq3;

  Widget _bar(double h, double alpha) => Container(
        width: 3,
        height: h.clamp(3.0, 16.0),
        decoration: BoxDecoration(
          color: _kGold.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!isPlaying) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _bar(5, 0.28),
          const SizedBox(width: 2),
          _bar(9, 0.28),
          const SizedBox(width: 2),
          _bar(5, 0.28),
        ],
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([eq1, eq2, eq3]),
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _bar(4 + eq1.value * 10, 0.85),
          const SizedBox(width: 2),
          _bar(7 + eq2.value * 9, 0.85),
          const SizedBox(width: 2),
          _bar(4 + eq3.value * 12, 0.85),
        ],
      ),
    );
  }
}
