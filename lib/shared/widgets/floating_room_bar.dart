import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/active_room_session.dart';
import '../../features/rooms/models/room.dart';
import '../../features/rooms/screens/room_details_screen.dart';
import '../../features/rooms/services/rooms_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

/// Floating mini-bar shown at the bottom of the app when the user has
/// minimized a room. Tapping it returns them to the room; the ✕ button
/// exits and leaves the room on the backend.
class FloatingRoomBar extends StatefulWidget {
  const FloatingRoomBar({super.key});

  @override
  State<FloatingRoomBar> createState() => _FloatingRoomBarState();
}

class _FloatingRoomBarState extends State<FloatingRoomBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _returnToRoom(Room room) async {
    HapticFeedback.lightImpact();
    if (!mounted) return;
    // FloatingRoomBar lives inside AppViewport (MaterialApp.builder), which is
    // outside the app's main Navigator subtree. rootNavigator: true ensures we
    // always push on the correct root navigator, not a stale or nested one.
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => RoomDetailsScreen(
          room: room,
          isArabic: context.isArabic,
        ),
      ),
    );
  }

  Future<void> _exitRoom(Room room) async {
    if (_leaving) return;

    // Show confirmation before leaving.
    final isArabic = context.isArabic;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A0840),
        title: Text(
          isArabic ? 'مغادرة الغرفة؟' : 'Exit Room?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isArabic
              ? 'ستغادر الغرفة. ستبقى مفتوحة للآخرين.'
              : 'You will leave this room. The room will stay open for others.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE63946)),
            child: Text(isArabic ? 'مغادرة' : 'Exit Room'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _leaving = true);
    try {
      await RoomsService().leaveRoom(room.id);
    } catch (_) {
      // Best-effort — remove from backend even if it fails
    }
    ActiveRoomSession.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ActiveRoomSession.instance,
      builder: (context, _) {
        final room = ActiveRoomSession.instance.room;
        if (room == null) return const SizedBox.shrink();

        return SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Container(
              margin: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                MediaQuery.of(context).padding.bottom + 8,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A1060), Color(0xFF1A0840)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _returnToRoom(room),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        // Live pulse dot
                        _PulseDot(),
                        const SizedBox(width: 10),

                        // Room name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.isArabic ? 'غرفة نشطة' : 'Active Room',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.50),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                room.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Return button
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B26D9).withValues(alpha: 0.30),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF8B26D9).withValues(alpha: 0.50),
                            ),
                          ),
                          child: Text(
                            context.isArabic ? 'عودة' : 'Return',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Exit button
                        GestureDetector(
                          onTap: () => _exitRoom(room),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.20),
                              ),
                            ),
                            child: _leaving
                                ? const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white54,
                                    ),
                                  )
                                : const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white70,
                                    size: 16,
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
        );
      },
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
            const Color(0xFF4ADE80),
            const Color(0xFF22C55E).withValues(alpha: 0.40),
            _ctrl.value,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4ADE80)
                  .withValues(alpha: 0.50 - _ctrl.value * 0.30),
              blurRadius: 6 + _ctrl.value * 4,
            ),
          ],
        ),
      ),
    );
  }
}
