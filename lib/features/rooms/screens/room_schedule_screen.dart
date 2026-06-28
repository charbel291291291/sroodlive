import 'package:flutter/material.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class RoomScheduleScreen extends StatefulWidget {
  const RoomScheduleScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<RoomScheduleScreen> createState() => _RoomScheduleScreenState();
}

class _ScheduledRoom {
  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final String hostId;
  final String hostName;
  final String? hostAvatar;
  final DateTime scheduledAt;
  final int rsvpCount;
  final bool isMyRoom;

  const _ScheduledRoom({
    required this.id,
    required this.title,
    this.description,
    this.coverUrl,
    required this.hostId,
    required this.hostName,
    this.hostAvatar,
    required this.scheduledAt,
    required this.rsvpCount,
    required this.isMyRoom,
  });
}

class _RoomScheduleScreenState extends State<RoomScheduleScreen> {
  bool _loading = true;
  String? _error;
  List<_ScheduledRoom> _upcoming = const [];
  List<_ScheduledRoom> _mine = const [];
  bool _showCreateForm = false;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) throw Exception('Not logged in');

      final now = DateTime.now().toUtc().toIso8601String();
      final data = await SupabaseService.requiredClient
          .from('room_schedules')
          .select(
            'id, title, description, cover_url, host_id, scheduled_at, rsvp_count, profiles!room_schedules_host_id_fkey(display_name, avatar_url)',
          )
          .gte('scheduled_at', now)
          .order('scheduled_at', ascending: true)
          .limit(50);

      final rooms = (data as List).map((r) {
        final p = r['profiles'] is Map<String, dynamic>
            ? r['profiles'] as Map<String, dynamic>
            : <String, dynamic>{};
        final hostId = r['host_id'] as String;
        return _ScheduledRoom(
          id: r['id'] as String,
          title: r['title'] as String? ?? '',
          description: r['description'] as String?,
          coverUrl: r['cover_url'] as String?,
          hostId: hostId,
          hostName: p['display_name'] as String? ?? '',
          hostAvatar: p['avatar_url'] as String?,
          scheduledAt:
              DateTime.tryParse(r['scheduled_at'].toString())?.toLocal() ??
              DateTime.now(),
          rsvpCount: r['rsvp_count'] as int? ?? 0,
          isMyRoom: hostId == me,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _upcoming = rooms.where((r) => !r.isMyRoom).toList();
        _mine = rooms.where((r) => r.isMyRoom).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _selectedDate == null ||
        _selectedTime == null) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) throw Exception('Not logged in');

      final scheduledAt = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      ).toUtc();

      await SupabaseService.requiredClient.from('room_schedules').insert({
        'host_id': me,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'scheduled_at': scheduledAt.toIso8601String(),
        'rsvp_count': 0,
      });

      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _selectedDate = null;
        _selectedTime = null;
        _showCreateForm = false;
        _submitting = false;
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      SroodToast.show(context, e.toString(), type: SroodToastType.error);
    }
  }

  Future<void> _rsvp(String scheduleId) async {
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) return;
      await SupabaseService.requiredClient.from('room_schedule_rsvps').upsert({
        'schedule_id': scheduleId,
        'user_id': me,
      });
      if (!mounted) return;
      SroodToast.show(context, context.isArabic ? 'تم تسجيل التذكير' : 'Reminder set!', type: SroodToastType.success);
      _load();
    } catch (_) {}
  }

  Future<void> _delete(String scheduleId) async {
    try {
      await SupabaseService.requiredClient
          .from('room_schedules')
          .delete()
          .eq('id', scheduleId);
      _load();
    } catch (_) {}
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
          child: Column(
            children: [
              _buildHeader(isArabic),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B26D9),
                        ),
                      )
                    : _error != null
                    ? _buildError(isArabic)
                    : _showCreateForm
                    ? _buildCreateForm(isArabic)
                    : _buildList(isArabic),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: _showCreateForm
                ? () => setState(() => _showCreateForm = false)
                : () => Navigator.of(context).pop(),
            icon: Icon(
              isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              _showCreateForm
                  ? (isArabic ? 'جدولة غرفة' : 'Schedule a Room')
                  : (isArabic ? 'الغرف المجدولة' : 'Scheduled Rooms'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (!_showCreateForm)
            TextButton.icon(
              onPressed: () => setState(() => _showCreateForm = true),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(isArabic ? 'جديد' : 'New'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF0C15A),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError(bool isArabic) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF5C7A),
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _load,
            child: Text(
              isArabic ? 'إعادة' : 'Retry',
              style: const TextStyle(color: Color(0xFFF0C15A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isArabic) {
    final all = [..._mine, ..._upcoming];
    if (all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFF2A1840),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isArabic ? 'لا توجد غرف مجدولة' : 'No scheduled rooms',
              style: const TextStyle(
                color: Color(0xFF9E91B8),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'كن أول من يجدول غرفة!'
                  : 'Be the first to schedule one!',
              style: const TextStyle(color: Color(0xFF6E5A8A), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_mine.isNotEmpty) ...[
            _sectionLabel(
              isArabic ? 'غرفي المجدولة' : 'My Scheduled Rooms',
              isArabic,
            ),
            ..._mine.map(
              (r) => _ScheduleTile(
                room: r,
                isArabic: isArabic,
                onRsvp: () => _rsvp(r.id),
                onDelete: () => _delete(r.id),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_upcoming.isNotEmpty) ...[
            _sectionLabel(isArabic ? 'قادمة' : 'Upcoming', isArabic),
            ..._upcoming.map(
              (r) => _ScheduleTile(
                room: r,
                isArabic: isArabic,
                onRsvp: () => _rsvp(r.id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, bool isArabic) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF9E91B8),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCreateForm(bool isArabic) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormField(
            label: isArabic ? 'عنوان الغرفة *' : 'Room title *',
            controller: _titleCtrl,
            isArabic: isArabic,
          ),
          const SizedBox(height: 14),
          _FormField(
            label: isArabic ? 'وصف (اختياري)' : 'Description (optional)',
            controller: _descCtrl,
            isArabic: isArabic,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          // Date picker
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(hours: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 90)),
                builder: (context, child) => Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF8B26D9),
                      surface: Color(0xFF1B102A),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (d != null) setState(() => _selectedDate = d);
            },
            child: _DateTimeChip(
              label: isArabic ? 'التاريخ' : 'Date',
              value: _selectedDate == null
                  ? null
                  : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
              icon: Icons.calendar_today_rounded,
              isArabic: isArabic,
            ),
          ),
          const SizedBox(height: 10),
          // Time picker
          GestureDetector(
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (context, child) => Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF8B26D9),
                      surface: Color(0xFF1B102A),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (t != null) setState(() => _selectedTime = t);
            },
            child: _DateTimeChip(
              label: isArabic ? 'الوقت' : 'Time',
              value: _selectedTime?.format(context),
              icon: Icons.schedule_rounded,
              isArabic: isArabic,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed:
                  (_submitting ||
                      _titleCtrl.text.trim().isEmpty ||
                      _selectedDate == null ||
                      _selectedTime == null)
                  ? null
                  : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B26D9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(
                isArabic ? 'جدولة الغرفة' : 'Schedule Room',
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

// ---------------------------------------------------------------------------
// Schedule tile
// ---------------------------------------------------------------------------

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.room,
    required this.isArabic,
    required this.onRsvp,
    this.onDelete,
  });

  final _ScheduledRoom room;
  final bool isArabic;
  final VoidCallback onRsvp;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = room.scheduledAt.difference(now);
    final timeLabel = _countdown(diff, isArabic);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: room.isMyRoom
              ? const Color(0xFF8B26D9).withValues(alpha: 0.5)
              : const Color(0xFF6E3AA8).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Host avatar
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF241638),
                backgroundImage: room.hostAvatar != null
                    ? NetworkImage(room.hostAvatar!)
                    : null,
                child: room.hostAvatar == null
                    ? Text(
                        room.hostName.isNotEmpty
                            ? room.hostName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
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
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      room.hostName,
                      style: const TextStyle(
                        color: Color(0xFF9E91B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFFF5C7A),
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Date/time row
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: Color(0xFFF0C15A),
                size: 14,
              ),
              const SizedBox(width: 5),
              Text(
                '${room.scheduledAt.day}/${room.scheduledAt.month}  ${room.scheduledAt.hour.toString().padLeft(2, '0')}:${room.scheduledAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Color(0xFFF0C15A),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  timeLabel,
                  style: const TextStyle(
                    color: Color(0xFFCCA0FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.people_rounded,
                color: Color(0xFF9E91B8),
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '${room.rsvpCount}',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (room.description?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              room.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFBCAED6),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (!room.isMyRoom) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onRsvp,
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF3ECC8C).withValues(alpha: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFF3ECC8C),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isArabic ? 'تذكيري' : 'Remind me',
                      style: const TextStyle(
                        color: Color(0xFF3ECC8C),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _countdown(Duration diff, bool isArabic) {
    if (diff.inDays > 0) {
      return isArabic ? 'بعد ${diff.inDays} يوم' : 'in ${diff.inDays}d';
    }
    if (diff.inHours > 0) {
      return isArabic ? 'بعد ${diff.inHours} ساعة' : 'in ${diff.inHours}h';
    }
    if (diff.inMinutes > 0) {
      return isArabic ? 'بعد ${diff.inMinutes} دقيقة' : 'in ${diff.inMinutes}m';
    }
    return isArabic ? 'الآن' : 'Now';
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.controller,
    required this.isArabic,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final bool isArabic;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isArabic
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9E91B8),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF160B24),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF4A3470)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF4A3470)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF8B26D9)),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }
}

class _DateTimeChip extends StatelessWidget {
  const _DateTimeChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.isArabic,
  });
  final String label;
  final String? value;
  final IconData icon;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value != null
              ? const Color(0xFF8B26D9)
              : const Color(0xFF4A3470),
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Icon(
            icon,
            color: value != null
                ? const Color(0xFF8B26D9)
                : const Color(0xFF9E91B8),
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 13),
          ),
          const Spacer(),
          Text(
            value ?? (isArabic ? 'اختر' : 'Select'),
            style: TextStyle(
              color: value != null ? Colors.white : const Color(0xFF6E5A8A),
              fontSize: 13,
              fontWeight: value != null ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF6E5A8A),
            size: 16,
          ),
        ],
      ),
    );
  }
}
