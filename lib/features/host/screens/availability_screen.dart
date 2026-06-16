import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _DaySlot {
  bool enabled;
  TimeOfDay start;
  TimeOfDay end;

  _DaySlot({required this.enabled, required this.start, required this.end});

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'start':
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
    'end':
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
  };
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  static const List<String> _dayKeysEn = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _dayKeysAr = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  late final List<_DaySlot> _slots;

  @override
  void initState() {
    super.initState();
    _slots = List.generate(
      7,
      (i) => _DaySlot(
        enabled: i < 5,
        start: const TimeOfDay(hour: 18, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
      ),
    );
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await SupabaseService.requiredClient
          .from('host_availability')
          .select('schedule')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null && data['schedule'] is List) {
        final schedule = data['schedule'] as List;
        for (var i = 0; i < schedule.length && i < _slots.length; i++) {
          final row = schedule[i] as Map?;
          if (row == null) continue;
          final startStr = row['start'] as String? ?? '18:00';
          final endStr = row['end'] as String? ?? '22:00';
          _slots[i] = _DaySlot(
            enabled: row['enabled'] as bool? ?? false,
            start: _parseTime(startStr),
            end: _parseTime(endStr),
          );
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 18,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      await SupabaseService.requiredClient.from('host_availability').upsert({
        'user_id': user.id,
        'schedule': _slots.map((s) => s.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.isArabic ? 'تم حفظ الجدول' : 'Schedule saved'),
          backgroundColor: const Color(0xFF123A2A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickTime(int dayIndex, bool isStart) async {
    final current = isStart ? _slots[dayIndex].start : _slots[dayIndex].end;
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF8B26D9),
            onPrimary: Colors.white,
            surface: Color(0xFF1B102B),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _slots[dayIndex].start = picked;
      } else {
        _slots[dayIndex].end = picked;
      }
    });
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
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B26D9),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: 7,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _buildDayCard(i, isArabic),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 52,
          child: FloatingActionButton.extended(
            onPressed: _isSaving ? null : _save,
            backgroundColor: const Color(0xFF8B26D9),
            foregroundColor: Colors.white,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              isArabic ? 'حفظ الجدول' : 'Save schedule',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
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
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'جدول الإتاحة' : 'Availability schedule',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  isArabic
                      ? 'حدد أوقات بثك المباشر'
                      : 'Set your live streaming hours',
                  style: const TextStyle(
                    color: Color(0xFF9E91B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(int i, bool isArabic) {
    final slot = _slots[i];
    final dayName = isArabic ? _dayKeysAr[i] : _dayKeysEn[i];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: slot.enabled ? const Color(0xFF1A0B2E) : const Color(0xFF0E0818),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: slot.enabled
              ? const Color(0xFF8B26D9).withValues(alpha: 0.6)
              : const Color(0xFF2A1840),
          width: slot.enabled ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Switch(
                value: slot.enabled,
                onChanged: (v) => setState(() => slot.enabled = v),
                activeThumbColor: const Color(0xFF8B26D9),
                activeTrackColor: const Color(0xFF3A174F),
                inactiveThumbColor: const Color(0xFF4A3470),
                inactiveTrackColor: const Color(0xFF1B102B),
              ),
              const SizedBox(width: 8),
              Text(
                dayName,
                style: TextStyle(
                  color: slot.enabled ? Colors.white : const Color(0xFF6E5A8A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (slot.enabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A174F),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'ON',
                    style: TextStyle(
                      color: Color(0xFF8B26D9),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          if (slot.enabled) ...[
            const SizedBox(height: 12),
            Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Expanded(
                  child: _TimeButton(
                    label: isArabic ? 'من' : 'From',
                    time: slot.start,
                    onTap: () => _pickTime(i, true),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF9E91B8),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeButton(
                    label: isArabic ? 'إلى' : 'To',
                    time: slot.end,
                    onTap: () => _pickTime(i, false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF4A3470)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9E91B8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time.format(context),
              style: const TextStyle(
                color: Color(0xFFF0C15A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
