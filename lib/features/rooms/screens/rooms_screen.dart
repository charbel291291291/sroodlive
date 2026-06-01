import 'package:flutter/material.dart';

import '../models/room.dart';
import '../services/rooms_service.dart';
import 'room_details_screen.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    required this.isArabic,
    super.key,
  });

  final bool isArabic;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final RoomsService _roomsService = const RoomsService();

  List<Room> _rooms = [];
  Map<String, int> _activeCounts = {};
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rooms = await _roomsService.getRooms();
      final activeCounts = await _roomsService.getActiveMemberCounts();

      if (!mounted) return;

      setState(() {
        _rooms = rooms;
        _activeCounts = activeCounts;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
  }

  Future<void> _createRoom() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(widget.isArabic ? 'إنشاء غرفة' : 'Create room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: widget.isArabic ? 'اسم الغرفة' : 'Room name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: widget.isArabic ? 'وصف قصير' : 'Short description',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.isArabic ? 'إنشاء' : 'Create'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final description = descriptionController.text.trim();

    if (name.isEmpty) return;

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      await _roomsService.createRoom(
        name: name,
        description: description.isEmpty ? null : description,
        language: widget.isArabic ? 'ar' : 'en',
        maxSeats: 12,
      );

      await _loadRooms();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
        if (mounted) {
          setState(() {
            _creating = false;
          });
        }
      }
  }

  Future<void> _joinRoom(Room room) async {
    try {
      await _roomsService.joinRoom(room.id);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomDetailsScreen(
            room: room,
            isArabic: widget.isArabic,
          ),
        ),
      );

      await _loadRooms();
    } catch (error) {
      if (!mounted) return;

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

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadRooms,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isArabic ? 'الغرف المباشرة' : 'Live Rooms',
                    textAlign: textAlign,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: _creating ? null : _createRoom,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.isArabic
                  ? 'ادخل غرفة صوتية اسمع شارك أو افتح سهرود جديد.'
                  : 'Join a voice room, listen, talk, or start a new SrOOd.',
              textAlign: textAlign,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFB8B8C7),
              ),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _RoomsMessageCard(
                title: widget.isArabic ? 'صار خطأ' : 'Something went wrong',
                message: _error!,
                icon: Icons.error_outline_rounded,
                crossAxisAlignment: crossAxisAlignment,
                textAlign: textAlign,
              )
            else if (_rooms.isEmpty)
              _RoomsMessageCard(
                title: widget.isArabic ? 'لا توجد غرف بعد' : 'No rooms yet',
                message: widget.isArabic
                    ? 'اضغط على زر + لإنشاء أول غرفة.'
                    : 'Tap + to create the first room.',
                icon: Icons.meeting_room_outlined,
                crossAxisAlignment: crossAxisAlignment,
                textAlign: textAlign,
              )
            else
              ..._rooms.map(
                (room) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _RoomCard(
                    room: room,
                        activeCount: _activeCounts[room.id] ?? 0,
                        isArabic: widget.isArabic,
                        onJoin: () => _joinRoom(room),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.activeCount,
    required this.isArabic,
    required this.onJoin,
  });

  final Room room;
  final int activeCount;
  final bool isArabic;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment =
        isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF14141F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF2A2A38),
        ),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6A84F).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Color(0xFFD6A84F),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Text(
                      room.name,
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.description?.isNotEmpty == true
                          ? room.description!
                          : (isArabic ? 'بدون وصف' : 'No description'),
                      textAlign: textAlign,
                      style: const TextStyle(
                        color: Color(0xFFB8B8C7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              _RoomPill(
                icon: Icons.language_rounded,
                label: room.language.toUpperCase(),
              ),
              const SizedBox(width: 8),
              _RoomPill(
                icon: Icons.people_rounded,
                label: '$activeCount/${room.maxSeats}',
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onJoin,
                icon: const Icon(Icons.login_rounded),
                label: Text(isArabic ? 'دخول' : 'Join'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomPill extends StatelessWidget {
  const _RoomPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF232332),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFD6A84F)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsMessageCard extends StatelessWidget {
  const _RoomsMessageCard({
    required this.title,
    required this.message,
    required this.icon,
    required this.crossAxisAlignment,
    required this.textAlign,
  });

  final String title;
  final String message;
  final IconData icon;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF14141F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF2A2A38),
        ),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Icon(icon, color: const Color(0xFFD6A84F), size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: textAlign,
            style: const TextStyle(
              color: Color(0xFFB8B8C7),
            ),
          ),
        ],
      ),
    );
  }
}









