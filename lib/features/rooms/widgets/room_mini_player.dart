import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/room_music_service.dart';

class RoomMiniPlayer extends StatefulWidget {
  const RoomMiniPlayer({
    super.key,
    required this.musicService,
    this.onTap,
    this.onStop,
    this.canManage = false,
    this.isArabic = false,
  });

  final RoomMusicService musicService;
  final VoidCallback? onTap;
  final VoidCallback? onStop;
  final bool canManage;
  final bool isArabic;

  @override
  State<RoomMiniPlayer> createState() => _RoomMiniPlayerState();
}

class _RoomMiniPlayerState extends State<RoomMiniPlayer>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;

  late final AnimationController _pulse;

  static const double _size = 66;

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

    final minDx = -(size.width - _size - 28);
    const maxDx = 0.0;

    final minDy = -(size.height * 0.55);
    const maxDy = 0.0;

    return Offset(
      next.dx.clamp(minDx, maxDx),
      next.dy.clamp(minDy, maxDy),
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
              width: _size + 18,
              height: _size + 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final glow = svc.isPlaying ? 0.22 + (_pulse.value * 0.16) : 0.14;

                      return Container(
                        width: _size,
                        height: _size,
                        margin: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF3A1375),
                              Color(0xFF8B26D9),
                              Color(0xFFE4B84A),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: const Color(0xFFFFD76B).withValues(alpha: 0.56),
                            width: 1.15,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B26D9).withValues(alpha: glow),
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.30),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
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
                          color: Colors.white.withValues(alpha: 0.18),
                          size: 42,
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            svc.playPause();
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Icon(
                              svc.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

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
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1D0B35).withValues(alpha: 0.94),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 14,
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 4,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFFFD76B).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        svc.isPlaying ? 'ON' : 'PAUSE',
                        style: const TextStyle(
                          color: Color(0xFFFFD76B),
                          fontSize: 8,
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
