import 'package:flutter/material.dart';

import '../models/room.dart';
import '../services/rooms_service.dart';

class RoomDetailsScreen extends StatefulWidget {
  const RoomDetailsScreen({
    required this.room,
    required this.isArabic,
    super.key,
  });

  final Room room;
  final bool isArabic;

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  final RoomsService _roomsService = const RoomsService();

  bool _leaving = false;

  Future<void> _leaveRoom() async {
    setState(() {
      _leaving = true;
    });

    try {
      await _roomsService.leaveRoom(widget.room.id);

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic
                ? 'خرجت من الغرفة: ${widget.room.name}'
                : 'Left room: ${widget.room.name}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _leaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textAlign = widget.isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment =
        widget.isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isArabic ? 'الغرفة' : 'Room'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF14141F),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFF2A2A38),
                ),
              ),
              child: Column(
                crossAxisAlignment: crossAxisAlignment,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6A84F).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: Color(0xFFD6A84F),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.room.name,
                    textAlign: textAlign,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.room.description?.isNotEmpty == true
                        ? widget.room.description!
                        : (widget.isArabic ? 'بدون وصف' : 'No description'),
                    textAlign: textAlign,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFFB8B8C7),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    textDirection:
                        widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      _RoomDetailPill(
                        icon: Icons.language_rounded,
                        label: widget.room.language.toUpperCase(),
                      ),
                      const SizedBox(width: 8),
                      _RoomDetailPill(
                        icon: Icons.event_seat_rounded,
                        label: '${widget.room.maxSeats}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF14141F),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFF2A2A38),
                ),
              ),
              child: Column(
                crossAxisAlignment: crossAxisAlignment,
                children: [
                  Text(
                    widget.isArabic ? 'الصوت المباشر' : 'Live audio',
                    textAlign: textAlign,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isArabic
                        ? 'هون رح نربط LiveKit بالمرحلة الجاية.'
                        : 'LiveKit connection will be added in the next phase.',
                    textAlign: textAlign,
                    style: const TextStyle(
                      color: Color(0xFFB8B8C7),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFFD6A84F),
                    size: 52,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _leaving ? null : _leaveRoom,
              icon: _leaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: Text(widget.isArabic ? 'الخروج من الغرفة' : 'Leave room'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomDetailPill extends StatelessWidget {
  const _RoomDetailPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF232332),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFD6A84F)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
