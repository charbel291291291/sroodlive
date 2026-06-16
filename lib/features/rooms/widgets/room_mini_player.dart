import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/room_music_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class RoomMiniPlayer extends StatefulWidget {
  const RoomMiniPlayer({
    required this.musicService,
    required this.isArabic,
    required this.onTap,
    this.onStop,
    this.canManage = false,
    super.key,
  });

  final RoomMusicService musicService;
  final bool isArabic;
  final VoidCallback onTap;
  final VoidCallback? onStop;
  final bool canManage;

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
        final isRtl = context.isArabic;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A1555), Color(0xFF1A0D33)],
              ),
              border: Border.all(
                color: const Color(0xFF8B26D9).withValues(alpha: 0.50),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.30),
                  blurRadius: 14,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Row(
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      // Animated music icon
                      AnimatedBuilder(
                        animation: _wave,
                        builder: (_, _) => Container(
                          width: 34,
                          height: 34,
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
                            size: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),

                      // Song info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isRtl
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
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
                            if (song.artist.isNotEmpty)
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.50),
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Play / Pause
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          svc.playPause();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF8B26D9).withValues(alpha: 0.35),
                          ),
                          child: Icon(
                            svc.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ✕ Close — host: stops for all; member: mutes locally
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          if (widget.onStop != null) {
                            widget.onStop!();
                          } else {
                            svc.stop();
                          }
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress bar
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16)),
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
