import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/room_music_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoomMiniPlayer — compact music bar shown when music is active in the room.
// Sits above the bottom action bar. Tapping it opens the full MusicPanel.
// ─────────────────────────────────────────────────────────────────────────────

class RoomMiniPlayer extends StatefulWidget {
  const RoomMiniPlayer({
    required this.musicService,
    required this.isArabic,
    required this.onTap,
    super.key,
  });

  final RoomMusicService musicService;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  State<RoomMiniPlayer> createState() => _RoomMiniPlayerState();
}

class _RoomMiniPlayerState extends State<RoomMiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.musicService,
      builder: (context, _) {
        final svc = widget.musicService;
        final song = svc.currentSong;
        if (song == null) return const SizedBox.shrink();

        final total = svc.duration?.inMilliseconds ?? 1;
        final pos = svc.position.inMilliseconds;
        final progress = (pos / total).clamp(0.0, 1.0);

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A1555), Color(0xFF1A0D33)],
              ),
              border: Border.all(
                color: const Color(0xFF8B26D9).withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    textDirection: widget.isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      // Animated icon
                      AnimatedBuilder(
                        animation: _wave,
                        builder: (_, _) => Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF8B26D9).withValues(
                                alpha: 0.15 + _wave.value * 0.15),
                            border: Border.all(
                              color: const Color(0xFF8B26D9)
                                  .withValues(alpha: 0.35 + _wave.value * 0.25),
                            ),
                          ),
                          child: Icon(
                            svc.isPlaying
                                ? Icons.music_note_rounded
                                : Icons.music_note_outlined,
                            color: const Color(0xFFC875FF),
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Song info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Play / Pause
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          svc.playPause();
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF8B26D9).withValues(alpha: 0.3),
                          ),
                          child: Icon(
                            svc.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Stop
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          svc.stop();
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                          child: Icon(
                            Icons.stop_rounded,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress bar
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(18)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF8B26D9)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
