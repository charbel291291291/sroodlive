import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class HostControlsScreen extends StatefulWidget {
  const HostControlsScreen({
    required this.roomId,
    required this.roomName,
    required this.isArabic,
    super.key,
  });

  final String roomId;
  final String roomName;
  final bool isArabic;

  @override
  State<HostControlsScreen> createState() => _HostControlsScreenState();
}

class _Seat {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isMuted;
  final int seatIndex;

  const _Seat({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.isMuted,
    required this.seatIndex,
  });
}

class _HostControlsScreenState extends State<HostControlsScreen> {
  bool _isHostMuted = false;
  bool _allMuted = false;
  bool _isLocked = false;
  bool _loading = true;
  List<_Seat> _seats = const [];
  int _viewerCount = 0;
  final int _giftCount = 0;
  Duration _sessionDuration = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _sessionDuration += const Duration(seconds: 1));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await SupabaseService.requiredClient
          .from('room_members')
          .select(
            'user_id, profiles(display_name, avatar_url), is_muted, seat_index',
          )
          .eq('room_id', widget.roomId)
          .eq('status', 'active')
          .order('seat_index');

      final countRow = await SupabaseService.requiredClient
          .from('room_members')
          .select('user_id')
          .eq('room_id', widget.roomId)
          .eq('status', 'listener');

      if (!mounted) return;
      setState(() {
        _seats = (rows as List).map((r) {
          final profile = r['profiles'] as Map<String, dynamic>? ?? {};
          return _Seat(
            userId: r['user_id'] as String,
            displayName: profile['display_name'] as String? ?? 'User',
            avatarUrl: profile['avatar_url'] as String?,
            isMuted: r['is_muted'] as bool? ?? false,
            seatIndex: r['seat_index'] as int? ?? 0,
          );
        }).toList();
        _viewerCount = (countRow as List).length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _muteAll() async {
    setState(() => _allMuted = !_allMuted);
    try {
      await SupabaseService.requiredClient
          .from('room_members')
          .update({'is_muted': _allMuted})
          .eq('room_id', widget.roomId)
          .eq('status', 'active');
    } catch (_) {}
  }

  Future<void> _toggleSeatMute(_Seat seat) async {
    final newMuted = !seat.isMuted;
    try {
      await SupabaseService.requiredClient
          .from('room_members')
          .update({'is_muted': newMuted})
          .eq('room_id', widget.roomId)
          .eq('user_id', seat.userId);
      await _load();
    } catch (_) {}
  }

  Future<void> _kickUser(_Seat seat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF160B24),
        title: Text(
          context.isArabic ? 'طرد المستخدم' : 'Kick user',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          context.isArabic
              ? 'هل تريد طرد ${seat.displayName}؟'
              : 'Remove ${seat.displayName} from the room?',
          style: const TextStyle(color: Color(0xFFBCAED6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.isArabic ? 'طرد' : 'Kick',
              style: const TextStyle(color: Color(0xFFFF4D6D)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseService.requiredClient
          .from('room_members')
          .update({'status': 'kicked'})
          .eq('room_id', widget.roomId)
          .eq('user_id', seat.userId);
      await _load();
    } catch (_) {}
  }

  Future<void> _endSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF160B24),
        title: Text(
          context.isArabic ? 'إنهاء الجلسة' : 'End session',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          context.isArabic
              ? 'هل تريد إنهاء الجلسة؟'
              : 'Are you sure you want to end the session?',
          style: const TextStyle(color: Color(0xFFBCAED6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.isArabic ? 'إنهاء' : 'End',
              style: const TextStyle(color: Color(0xFFFF4D6D)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await SupabaseService.requiredClient
          .from('rooms')
          .update({
            'is_live': false,
            'ended_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.roomId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            child: Directionality(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(isArabic),
                  const SizedBox(height: 16),
                  _buildStatsRow(isArabic),
                  const SizedBox(height: 20),
                  _buildQuickActions(isArabic),
                  const SizedBox(height: 20),
                  _buildSeatsSection(isArabic),
                  const SizedBox(height: 20),
                  _buildDangerZone(isArabic),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Row(
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
                isArabic ? 'لوحة تحكم المضيف' : 'Host controls',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFBCAED6),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF63E6A1).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, color: Color(0xFF63E6A1), size: 8),
              const SizedBox(width: 5),
              Text(
                _formatDuration(_sessionDuration),
                style: const TextStyle(
                  color: Color(0xFF63E6A1),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildStatsRow(bool isArabic) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.visibility_rounded,
            value: '$_viewerCount',
            label: isArabic ? 'مشاهد' : 'Viewers',
            color: const Color(0xFF8B26D9),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.card_giftcard_rounded,
            value: '$_giftCount',
            label: isArabic ? 'هدايا' : 'Gifts',
            color: const Color(0xFFF0C15A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.mic_rounded,
            value: '${_seats.length}',
            label: isArabic ? 'مقاعد' : 'Seats',
            color: const Color(0xFF63E6A1),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(bool isArabic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'إجراءات سريعة' : 'Quick actions',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ActionChip(
              icon: _isHostMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: _isHostMuted
                  ? (isArabic ? 'إلغاء الكتم' : 'Unmute')
                  : (isArabic ? 'كتم نفسي' : 'Mute self'),
              active: _isHostMuted,
              onTap: () => setState(() => _isHostMuted = !_isHostMuted),
            ),
            _ActionChip(
              icon: Icons.volume_off_rounded,
              label: _allMuted
                  ? (isArabic ? 'إلغاء كتم الكل' : 'Unmute all')
                  : (isArabic ? 'كتم الكل' : 'Mute all'),
              active: _allMuted,
              onTap: _muteAll,
            ),
            _ActionChip(
              icon: _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              label: _isLocked
                  ? (isArabic ? 'فتح الغرفة' : 'Unlock room')
                  : (isArabic ? 'قفل الغرفة' : 'Lock room'),
              active: _isLocked,
              onTap: () => setState(() => _isLocked = !_isLocked),
            ),
            _ActionChip(
              icon: Icons.refresh_rounded,
              label: isArabic ? 'تحديث' : 'Refresh',
              active: false,
              onTap: _load,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSeatsSection(bool isArabic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'المقاعد النشطة' : 'Active seats',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF8B26D9)),
            ),
          )
        else if (_seats.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF160B24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF4A3470)),
            ),
            child: Center(
              child: Text(
                isArabic
                    ? 'لا يوجد أحد في المقاعد حالياً'
                    : 'No active seats yet',
                style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 13),
              ),
            ),
          )
        else
          ...(_seats.map(
            (s) => _SeatTile(
              seat: s,
              isArabic: isArabic,
              onMute: () => _toggleSeatMute(s),
              onKick: () => _kickUser(s),
            ),
          )),
      ],
    );
  }

  Widget _buildDangerZone(bool isArabic) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF4D6D).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'منطقة الخطر' : 'Danger zone',
            style: const TextStyle(
              color: Color(0xFFFF4D6D),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _endSession,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF4D6D),
                side: const BorderSide(color: Color(0xFFFF4D6D)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.stop_circle_rounded, size: 20),
              label: Text(
                isArabic ? 'إنهاء الجلسة' : 'End session',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2A1040) : const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? const Color(0xFF8B26D9) : const Color(0xFF4A3470),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? const Color(0xFFCCA0FF) : const Color(0xFF9E91B8),
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? const Color(0xFFCCA0FF)
                    : const Color(0xFFBCAED6),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.seat,
    required this.isArabic,
    required this.onMute,
    required this.onKick,
  });

  final _Seat seat;
  final bool isArabic;
  final VoidCallback onMute;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF241638),
            backgroundImage: seat.avatarUrl != null
                ? NetworkImage(seat.avatarUrl!)
                : null,
            child: seat.avatarUrl == null
                ? Text(
                    seat.displayName.isNotEmpty
                        ? seat.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  seat.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  isArabic
                      ? 'المقعد ${seat.seatIndex + 1}'
                      : 'Seat ${seat.seatIndex + 1}',
                  style: const TextStyle(
                    color: Color(0xFF9E91B8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onMute,
            icon: Icon(
              seat.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: seat.isMuted
                  ? const Color(0xFFFF6B8A)
                  : const Color(0xFF63E6A1),
              size: 20,
            ),
          ),
          IconButton(
            onPressed: onKick,
            icon: const Icon(
              Icons.person_remove_rounded,
              color: Color(0xFFFF4D6D),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
