import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/room_music_service.dart';

class RoomMiniPlayer extends StatefulWidget {
  const RoomMiniPlayer({
    super.key,
    required this.musicService,
    this.onTap,
    this.onStop,
    this.onNonControllerAction,
    this.canManage = false,
    this.isArabic = false,
    this.controllerUserId,
    this.currentUserId,
  });

  final RoomMusicService musicService;

  /// Opens the full music panel.
  final VoidCallback? onTap;

  /// Stops music for the whole room. Only wired when [canManage] is true.
  final VoidCallback? onStop;

  /// Called when a non-controller taps a control — shows the permission snack.
  final VoidCallback? onNonControllerAction;

  /// True only when the current user is the music controller.
  final bool canManage;
  final bool isArabic;

  /// User ID of whoever started the current track (null = no track / unknown).
  final String? controllerUserId;

  /// User ID of the local user.
  final String? currentUserId;

  bool get _isController =>
      controllerUserId != null && controllerUserId == currentUserId;

  @override
  State<RoomMiniPlayer> createState() => _RoomMiniPlayerState();
}

class _RoomMiniPlayerState extends State<RoomMiniPlayer>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  late final AnimationController _pulse;

  static const double _size = 56;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Offset _clampOffset(BuildContext context, Offset next) {
    final size = MediaQuery.of(context).size;
    return Offset(
      next.dx.clamp(-(size.width - _size - 28), 0.0),
      next.dy.clamp(-(size.height * 0.55), 0.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.musicService,
      builder: (context, _) {
        final svc = widget.musicService;
        final song = svc.currentSong;
        if (song == null) return const SizedBox.shrink();

        if (!widget.canManage) {
          return _ListenerNowPlayingChip(
            song: song,
            isPlaying: svc.isPlaying,
            isController: widget._isController,
            controllerUserId: widget.controllerUserId,
            pulse: _pulse,
            dragOffset: _dragOffset,
            onTap: widget.onTap,
            onNonControllerAction: widget.onNonControllerAction,
            onPanUpdate: (details) {
              setState(() {
                _dragOffset = _clampOffset(context, _dragOffset + details.delta);
              });
            },
          );
        }

        // Controller full-control bubble (smaller + cleaner than before)
        return Transform.translate(
          offset: _dragOffset,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) {
              setState(() {
                _dragOffset = _clampOffset(context, _dragOffset + details.delta);
              });
            },
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap?.call();
            },
            child: SizedBox(
              width: _size + 16,
              height: _size + 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final glow = svc.isPlaying
                          ? 0.20 + (_pulse.value * 0.14)
                          : 0.12;
                      return Container(
                        width: _size,
                        height: _size,
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3A1375), Color(0xFF8B26D9), Color(0xFFE4B84A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: const Color(0xFFFFD76B).withValues(alpha: 0.50),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B26D9).withValues(alpha: glow),
                              blurRadius: 16,
                              spreadRadius: 0,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          color: Colors.white.withValues(alpha: 0.15),
                          size: 34,
                        ),
                        // Play / Pause inner button
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            svc.playPause();
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            child: svc.isLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  )
                                : Icon(
                                    svc.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stop / close button
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onStop?.call();
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1D0B35).withValues(alpha: 0.95),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8),
                          ],
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white70, size: 13),
                      ),
                    ),
                  ),

                  // Play/Pause state label
                  Positioned(
                    left: 4,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFFFD76B).withValues(alpha: 0.22)),
                      ),
                      child: Text(
                        svc.isPlaying ? 'ON' : 'PAUSE',
                        style: const TextStyle(
                          color: Color(0xFFFFD76B),
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.none,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Compact chip shown to listeners (and non-controller managers) ─────────────

class _ListenerNowPlayingChip extends StatelessWidget {
  const _ListenerNowPlayingChip({
    required this.song,
    required this.isPlaying,
    required this.isController,
    required this.pulse,
    required this.dragOffset,
    required this.onPanUpdate,
    this.controllerUserId,
    this.onTap,
    this.onNonControllerAction,
  });

  final dynamic song;
  final bool isPlaying;
  final bool isController;
  final String? controllerUserId;
  final AnimationController pulse;
  final Offset dragOffset;
  final void Function(DragUpdateDetails) onPanUpdate;
  final VoidCallback? onTap;
  final VoidCallback? onNonControllerAction;

  @override
  Widget build(BuildContext context) {
    debugPrint('[RoomMusic] listener chip song=${song.title} isController=$isController');
    return Transform.translate(
      offset: dragOffset,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onPanUpdate,
        onTap: onTap,
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            return Container(
              height: 34,
              constraints: const BoxConstraints(maxWidth: 190),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1D0B35).withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.32 + pulse.value * 0.18),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B26D9)
                        .withValues(alpha: isPlaying ? 0.22 + pulse.value * 0.08 : 0.08),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    size: 13,
                    color: const Color(0xFFFFD76B).withValues(alpha: isPlaying ? 0.9 : 0.45),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      song.title as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _EqualizerDots(isPlaying: isPlaying, pulse: pulse),
                  // Lock icon — tells listener they cannot control this
                  if (!isController) ...[
                    const SizedBox(width: 5),
                    Icon(
                      Icons.lock_rounded,
                      size: 10,
                      color: Colors.white.withValues(alpha: 0.30),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Three animated bars
class _EqualizerDots extends StatelessWidget {
  const _EqualizerDots({required this.isPlaying, required this.pulse});

  final bool isPlaying;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    if (!isPlaying) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (_) => _bar(height: 6, opacity: 0.35)),
      );
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = pulse.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(height: 6 + t * 6, opacity: 0.9),
            const SizedBox(width: 2),
            _bar(height: 10 + (1 - t) * 4, opacity: 0.9),
            const SizedBox(width: 2),
            _bar(height: 6 + t * 8, opacity: 0.9),
          ],
        );
      },
    );
  }

  Widget _bar({required double height, required double opacity}) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFFFD76B).withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
