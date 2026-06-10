import 'package:flutter/material.dart';

import '../../../features/notifications/screens/notifications_screen.dart';
import '../../../features/search/screens/search_screen.dart';
import '../../../shared/branding/branding_assets.dart';
import '../models/room.dart';
import '../services/rooms_service.dart';
import 'room_details_screen.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({required this.isArabic, super.key});

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
                textDirection: widget.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: widget.isArabic ? 'اسم الغرفة' : 'Room name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                textDirection: widget.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
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
          builder: (_) =>
              RoomDetailsScreen(room: room, isArabic: widget.isArabic),
        ),
      );

      await _loadRooms();
    } catch (error) {
      if (!mounted) return;

      final message = error is LockedRoomException
          ? (widget.isArabic
                ? '\u0627\u0644\u063a\u0631\u0641\u0629 \u0645\u0642\u0641\u0644\u0629 \u0645\u0646 \u0627\u0644\u0645\u0636\u064a\u0641.'
                : 'This room is locked by the host.')
          : error is ClosedRoomException
          ? (widget.isArabic
                ? '\u062a\u0645 \u0625\u063a\u0644\u0627\u0642 \u0647\u0630\u0647 \u0627\u0644\u063a\u0631\u0641\u0629.'
                : 'This room is closed.')
          : error.toString();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textAlign = widget.isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = widget.isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRooms,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isArabic
                          ? '\u063a\u0631\u0641 \u0645\u0628\u0627\u0634\u0631\u0629'
                          : 'Live Rooms',
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SearchScreen(isArabic: widget.isArabic),
                      ),
                    ),
                    icon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFFBCAED6),
                      size: 26,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NotificationsScreen(
                          isArabic: widget.isArabic,
                        ),
                      ),
                    ),
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: Color(0xFFBCAED6),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD978), Color(0xFFD99A2B)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFF0C15A,
                          ).withValues(alpha: 0.28),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _creating ? null : _createRoom,
                      color: const Color(0xFF12061F),
                      icon: _creating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.isArabic
                    ? '\u0627\u062f\u062e\u0644 \u063a\u0631\u0641\u0629 \u0635\u0648\u062a\u064a\u0629\u060c \u0627\u0633\u0645\u0639\u060c \u0634\u0627\u0631\u0643\u060c \u0623\u0648 \u0627\u0628\u062f\u0623 \u0633\u0647\u0631\u0629 \u062c\u062f\u064a\u062f\u0629.'
                    : 'Join a voice room, listen, talk, or start a new SrOOd.',
                textAlign: textAlign,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: Color(0xFFD8CFEA),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              _RoomsHeroBanner(isArabic: widget.isArabic),
              const SizedBox(height: 22),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                _RoomsMessageCard(
                  title: widget.isArabic
                      ? '\u0635\u0627\u0631 \u062e\u0637\u0623'
                      : 'Something went wrong',
                  message: _error!,
                  icon: Icons.error_outline_rounded,
                  crossAxisAlignment: crossAxisAlignment,
                  textAlign: textAlign,
                )
              else if (_rooms.isEmpty)
                _RoomsMessageCard(
                  title: widget.isArabic
                      ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u063a\u0631\u0641 \u0628\u0639\u062f'
                      : 'No rooms yet',
                  message: widget.isArabic
                      ? '\u0627\u0636\u063a\u0637 \u0639\u0644\u0649 \u0632\u0631 + \u0644\u0625\u0646\u0634\u0627\u0621 \u0623\u0648\u0644 \u063a\u0631\u0641\u0629.'
                      : 'Tap + to create the first room.',
                  icon: Icons.meeting_room_outlined,
                  crossAxisAlignment: crossAxisAlignment,
                  textAlign: textAlign,
                )
              else
                ..._rooms.map(
                  (room) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
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
      ),
    );
  }
}

class _RoomsHeroBanner extends StatelessWidget {
  const _RoomsHeroBanner({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final alignment = isArabic ? Alignment.centerRight : Alignment.centerLeft;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B168C), Color(0xFF8B26D9), Color(0xFFE0A83A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: isArabic ? null : -10,
            left: isArabic ? -10 : null,
            top: -12,
            child: Opacity(
              opacity: 0.28,
              child: SizedBox(
                width: 120,
                height: 120,
                child: Image.asset(
                  BrandingAssets.logoSquare,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.auto_awesome_rounded,
                    size: 92,
                    color: Colors.white.withValues(alpha: 0.44),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: alignment,
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    isArabic
                        ? '\u0633\u0647\u0631\u0648\u062f \u0644\u0627\u064a\u0641'
                        : 'SrOOd Live',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  isArabic
                      ? '\u0627\u062e\u062a\u0631 \u063a\u0631\u0641\u0629 \u0648\u0627\u0628\u062f\u0623 \u0627\u0644\u0633\u0647\u0631\u0629'
                      : 'Choose a room and start the night',
                  textAlign: textAlign,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isArabic
                      ? '\u063a\u0631\u0641 \u0635\u0648\u062a\u064a\u0629\u060c \u0645\u0636\u064a\u0641\u064a\u0646\u060c \u0645\u0633\u062a\u0645\u0639\u064a\u0646\u060c \u0648\u0623\u062c\u0648\u0627\u0621 \u0641\u062e\u0645\u0629.'
                      : 'Voice rooms, hosts, listeners, and a premium live vibe.',
                  textAlign: textAlign,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF0C15A).withValues(alpha: 0.65),
            const Color(0xFF8B26D9).withValues(alpha: 0.58),
            const Color(0xFF4A3470).withValues(alpha: 0.34),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF201033), Color(0xFF171125), Color(0xFF12091D)],
          ),
        ),
        child: Column(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A2A1D), Color(0xFF2E2238)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFF0C15A).withValues(alpha: 0.24),
                    ),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Color(0xFFF0C15A),
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: crossAxisAlignment,
                    children: [
                      Text(
                        room.name,
                        textAlign: textAlign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        room.description?.isNotEmpty == true
                            ? room.description!
                            : (isArabic
                                  ? '\u0628\u062f\u0648\u0646 \u0648\u0635\u0641'
                                  : 'No description'),
                        textAlign: textAlign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD8CFEA),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
                if (room.isLocked) ...[
                  const SizedBox(width: 8),
                  _RoomPill(
                    icon: Icons.lock_rounded,
                    label: isArabic
                        ? '\u0645\u0642\u0641\u0644\u0629'
                        : 'Locked',
                  ),
                ],
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF0C15A).withValues(alpha: 0.26),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FilledButton.icon(
                    onPressed: onJoin,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(isArabic ? '\u062f\u062e\u0648\u0644' : 'Join'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPill extends StatelessWidget {
  const _RoomPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF241638),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFF0C15A)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
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
        color: const Color(0xFF171125),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: textAlign,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: textAlign,
            style: const TextStyle(color: Color(0xFFD8CFEA)),
          ),
        ],
      ),
    );
  }
}
