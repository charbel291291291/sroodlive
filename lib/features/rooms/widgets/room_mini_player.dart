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

        // Combine title + artist into one label to avoid a second text row.
        final label = song.artist.isNotEmpty
            ? '${song.title} · ${song.artist}'
            : song.title;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
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
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.28),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      // Animated music icon — compact 28 px
                      AnimatedBuilder(
                        animation: _wave,
                        builder: (_, child) => Container(
                          width: 28,
                          height: 28,
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
                            size: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Single-line song label (title · artist)
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection:
                              isRtl ? TextDirection.rtl : TextDirection.ltr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Play / Pause — 32 px visible, 44 px tap target
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          svc.playPause();
                        },
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF8B26D9)
                                    .withValues(alpha: 0.35),
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
                        ),
                      ),

                      // ✕ Close — only visible for host/owner (onStop != null).
                      // Calling onStop stops the local player immediately and
                      // propagates the stop to all participants via Supabase.
                      if (widget.onStop != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            widget.onStop!();
                          },
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 28,
                                height: 28,
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
                                  size: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Thin progress bar at the bottom edge
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(14)),
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
