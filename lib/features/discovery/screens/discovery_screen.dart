import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../rooms/models/room.dart';
import '../../rooms/screens/room_details_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryEntry {
  final String id;
  final String name;
  final String? imageUrl;
  final String? subtitle;
  final bool? isLive;
  final String type;
  final Room? room;

  const _DiscoveryEntry({
    required this.id,
    required this.name,
    this.imageUrl,
    this.subtitle,
    this.isLive,
    required this.type,
    this.room,
  });
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  bool _loading = true;
  String? _error;
  List<_DiscoveryEntry> _rooms = const [];
  List<_DiscoveryEntry> _users = const [];
  String _activeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final [roomsRaw, usersRaw] = await Future.wait([
        SupabaseService.requiredClient
            .from('rooms')
            .select('id, owner_id, name, description, language, livekit_room_name, max_seats, is_private, is_locked, is_closed, is_live, cover_url, member_count, created_at')
            .order('member_count', ascending: false)
            .limit(20),
        SupabaseService.requiredClient
            .from('profiles')
            .select('id, display_name, avatar_url, bio, follower_count')
            .order('follower_count', ascending: false)
            .limit(20),
      ]);

      if (!mounted) return;
      setState(() {
        _rooms = (roomsRaw as List).map((r) => _DiscoveryEntry(
          id: r['id'] as String,
          name: r['name'] as String? ?? '',
          imageUrl: r['cover_url'] as String?,
          subtitle: r['description'] as String?,
          isLive: r['is_live'] as bool?,
          type: 'room',
          room: Room.fromJson(r as Map<String, dynamic>),
        )).toList();

        _users = (usersRaw as List).map((u) => _DiscoveryEntry(
          id: u['id'] as String,
          name: u['display_name'] as String? ?? '',
          imageUrl: u['avatar_url'] as String?,
          subtitle: u['bio'] as String?,
          type: 'user',
        )).toList();

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(isArabic),
              _buildFilters(isArabic),
              Expanded(child: _buildBody(isArabic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'الاستكشاف' : 'Discover',
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.0),
                ),
                const SizedBox(height: 3),
                Text(
                  isArabic ? 'غرف ومستخدمون مقترحون' : 'Trending rooms and suggested people',
                  style: const TextStyle(color: Color(0xFFBCAED6), fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF0C15A)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isArabic) {
    final filters = [
      ('all',   isArabic ? 'الكل'    : 'All'),
      ('rooms', isArabic ? 'الغرف'   : 'Rooms'),
      ('users', isArabic ? 'أشخاص'   : 'People'),
      ('live',  isArabic ? 'مباشر'   : 'Live'),
    ];

    return SizedBox(
      height: 46,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        children: filters.map((f) {
          final selected = _activeFilter == f.$1;
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF3A174F) : const Color(0xFF160B24),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? const Color(0xFF8B26D9) : const Color(0xFF4A3470),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                f.$2,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF9E91B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody(bool isArabic) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF8B26D9)));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5C7A), size: 36),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: Text(isArabic ? 'إعادة' : 'Retry', style: const TextStyle(color: Color(0xFFF0C15A)))),
          ],
        ),
      );
    }

    final showRooms = _activeFilter == 'all' || _activeFilter == 'rooms';
    final showUsers = _activeFilter == 'all' || _activeFilter == 'users';
    final liveOnly  = _activeFilter == 'live';
    final rooms = liveOnly ? _rooms.where((r) => r.isLive == true).toList() : _rooms;

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (showRooms || liveOnly) ...[
            _sectionHeader(
              isArabic ? (liveOnly ? 'غرف مباشرة' : 'غرف مقترحة') : (liveOnly ? 'Live rooms' : 'Trending rooms'),
              Icons.meeting_room_rounded,
              isArabic,
            ),
            const SizedBox(height: 10),
            if (rooms.isEmpty)
              _emptySection(isArabic ? 'لا توجد غرف' : 'No rooms found', isArabic)
            else
              ...rooms.map((r) => _RoomTile(entry: r, isArabic: isArabic)),
            const SizedBox(height: 20),
          ],
          if (showUsers) ...[
            _sectionHeader(
              isArabic ? 'أشخاص مقترحون' : 'Suggested people',
              Icons.people_rounded,
              isArabic,
            ),
            const SizedBox(height: 10),
            if (_users.isEmpty)
              _emptySection(isArabic ? 'لا يوجد مستخدمون' : 'No users found', isArabic)
            else
              ...(_activeFilter == 'all' ? _users.take(8) : _users).map(
                (u) => _UserTile(entry: u, isArabic: isArabic),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, bool isArabic) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Icon(icon, color: const Color(0xFFF0C15A), size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _emptySection(String msg, bool isArabic) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Text(msg, style: const TextStyle(color: Color(0xFF6E5A8A), fontSize: 14, fontWeight: FontWeight.w700)),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.entry, required this.isArabic});

  final _DiscoveryEntry entry;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RoomDetailsScreen(room: entry.room!, isArabic: isArabic),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6E3AA8).withValues(alpha: 0.35)),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF241638),
                borderRadius: BorderRadius.circular(14),
                image: entry.imageUrl != null
                    ? DecorationImage(image: NetworkImage(entry.imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: entry.imageUrl == null
                  ? const Icon(Icons.meeting_room_rounded, color: Color(0xFF9E91B8), size: 24)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      Flexible(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (entry.isLive == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4D6D).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFF4D6D).withValues(alpha: 0.5)),
                          ),
                          child: const Text('LIVE', style: TextStyle(color: Color(0xFFFF4D6D), fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ],
                  ),
                  if (entry.subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF6E5A8A), size: 18),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.entry, required this.isArabic});

  final _DiscoveryEntry entry;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(userId: entry.id, isArabic: isArabic),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6E3AA8).withValues(alpha: 0.35)),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF241638),
              backgroundImage: entry.imageUrl != null ? NetworkImage(entry.imageUrl!) : null,
              child: entry.imageUrl == null
                  ? Text(
                      entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  if (entry.subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF6E5A8A), size: 18),
          ],
        ),
      ),
    );
  }
}
