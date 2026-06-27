import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/active_room_session.dart';
import '../../features/rooms/models/room.dart';
import '../../features/rooms/screens/room_details_screen.dart';
import '../../main.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Compact floating room widget shown when the user has minimized a room.
/// - Appears bottom-right above the navigation bar
/// - Draggable
/// - Tap to return to room
/// - X exits the session (disconnects LiveKit)
class FloatingRoomBar extends StatefulWidget {
  const FloatingRoomBar({super.key});

  @override
  State<FloatingRoomBar> createState() => _FloatingRoomBarState();
}

class _FloatingRoomBarState extends State<FloatingRoomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  bool _returning = false;
  bool _leaving = false;
  Offset _dragOffset = Offset.zero;

  static const double _cardWidth = 78;
  static const double _cardHeight = 108;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.35, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Offset _clampOffset(BuildContext context, Offset next) {
    final size = MediaQuery.of(context).size;
    return Offset(
      next.dx.clamp(-(size.width - _cardWidth - 18), 0.0),
      next.dy.clamp(-(size.height * 0.58), 0.0),
    );
  }

  Future<void> _returnToRoom(Room room) async {
    if (_returning || _leaving) return;
    setState(() => _returning = true);
    debugPrint('[RoomMinimize] floating bar — restore tapped roomId=${room.id}');
    try {
      HapticFeedback.lightImpact();
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) {
        debugPrint('[RoomMinimize] floating bar — root navigator is null');
        return;
      }

      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => RoomDetailsScreen(room: room, isArabic: context.isArabic),
        ),
      );
    } catch (e) {
      debugPrint('[RoomMinimize] floating bar — return failed: $e');
    } finally {
      if (mounted) setState(() => _returning = false);
    }
  }

  Future<void> _exitRoom(Room room) async {
    if (_leaving || _returning) return;
    setState(() => _leaving = true);
    debugPrint('[RoomMinimize] floating bar — leave tapped roomId=${room.id}');
    HapticFeedback.lightImpact();
    try {
      await ActiveRoomSession.instance.leave(); // disconnects LiveKit
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ActiveRoomSession.instance,
      builder: (context, _) {
        final room = ActiveRoomSession.instance.room;
        if (room == null) return const SizedBox.shrink();

        final micOn = ActiveRoomSession.instance.savedMicEnabled;
        final isArabic = context.isArabic;

        return SafeArea(
          top: false,
          left: false,
          child: Padding(
            padding: EdgeInsets.only(
              right: 10,
              bottom: MediaQuery.of(context).padding.bottom + 86,
            ),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Transform.translate(
                offset: _dragOffset,
                child: SlideTransition(
                  position: _slide,
                  child: FadeTransition(
                    opacity: _fade,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _dragOffset = _clampOffset(
                            context,
                            _dragOffset + details.delta,
                          );
                        });
                      },
                      onTap: (_returning || _leaving) ? null : () => _returnToRoom(room),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: _cardWidth,
                        height: _cardHeight,
                        padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF34156F), Color(0xFF1A0A3D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFB56DFF).withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B26D9).withValues(alpha: 0.26),
                              blurRadius: 22,
                              spreadRadius: -2,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // ── Live dot + mic indicator ─────────────
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF5AA5),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFF5AA5)
                                                .withValues(alpha: 0.65),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'LIVE',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.72),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const Spacer(),
                                    // Mic state icon
                                    Icon(
                                      micOn
                                          ? Icons.mic_rounded
                                          : Icons.headphones_rounded,
                                      size: 11,
                                      color: micOn
                                          ? const Color(0xFFF0C15A)
                                          : Colors.white.withValues(alpha: 0.45),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // ── Room icon ───────────────────────────
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF8B26D9), Color(0xFFB56DFF)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8B26D9)
                                            .withValues(alpha: 0.38),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: _returning
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.graphic_eq_rounded,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                ),
                                const SizedBox(height: 4),
                                // ── Room name ───────────────────────────
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      room.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        height: 1.1,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                // ── Return label ────────────────────────
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.09),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.14),
                                    ),
                                  ),
                                  child: Text(
                                    isArabic ? 'العودة' : 'Return',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // ── Close / leave button ─────────────────────
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _leaving ? null : () => _exitRoom(room),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: _leaving
                                      ? const Padding(
                                          padding: EdgeInsets.all(5),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: Colors.white54,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white70,
                                          size: 12,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
