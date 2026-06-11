import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  bool _loading = true;
  bool _saving = false;

  bool _notifSound = true;
  bool _notifVibrate = true;
  bool _showOnline = true;
  bool _allowMessages = true;
  bool _allowCalls = true;
  bool _autoPlay = true;
  bool _dataWarning = true;

  String _messageFrom = 'everyone';
  String _callFrom = 'everyone';
  String _fontSize = 'medium';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) {
        setState(() => _loading = false);
        return;
      }
      final rows = await SupabaseService.requiredClient
          .from('user_preferences')
          .select()
          .eq('user_id', me)
          .maybeSingle();

      if (rows != null && mounted) {
        setState(() {
          _notifSound = rows['notif_sound'] as bool? ?? true;
          _notifVibrate = rows['notif_vibrate'] as bool? ?? true;
          _showOnline = rows['show_online'] as bool? ?? true;
          _allowMessages = rows['allow_messages'] as bool? ?? true;
          _allowCalls = rows['allow_calls'] as bool? ?? true;
          _autoPlay = rows['auto_play'] as bool? ?? true;
          _dataWarning = rows['data_warning'] as bool? ?? true;
          _messageFrom = rows['message_from'] as String? ?? 'everyone';
          _callFrom = rows['call_from'] as String? ?? 'everyone';
          _fontSize = rows['font_size'] as String? ?? 'medium';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) return;
      await SupabaseService.requiredClient.from('user_preferences').upsert({
        'user_id': me,
        'notif_sound': _notifSound,
        'notif_vibrate': _notifVibrate,
        'show_online': _showOnline,
        'allow_messages': _allowMessages,
        'allow_calls': _allowCalls,
        'auto_play': _autoPlay,
        'data_warning': _dataWarning,
        'message_from': _messageFrom,
        'call_from': _callFrom,
        'font_size': _fontSize,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isArabic ? 'تم الحفظ' : 'Preferences saved'),
          backgroundColor: const Color(0xFF1A3A28),
        ),
      );
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
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
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF8B26D9)),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    child: Directionality(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _section(isArabic ? 'الإشعارات' : 'Notifications', [
                            _toggle(
                              isArabic ? 'صوت الإشعارات' : 'Notification sound',
                              Icons.volume_up_rounded,
                              _notifSound,
                              (v) => setState(() => _notifSound = v),
                            ),
                            _toggle(
                              isArabic ? 'اهتزاز الإشعارات' : 'Vibration',
                              Icons.vibration_rounded,
                              _notifVibrate,
                              (v) => setState(() => _notifVibrate = v),
                            ),
                          ]),
                          _section(isArabic ? 'الخصوصية' : 'Privacy', [
                            _toggle(
                              isArabic
                                  ? 'إظهار حالة الاتصال'
                                  : 'Show online status',
                              Icons.circle_rounded,
                              _showOnline,
                              (v) => setState(() => _showOnline = v),
                            ),
                            _toggle(
                              isArabic ? 'السماح بالرسائل' : 'Allow messages',
                              Icons.chat_bubble_rounded,
                              _allowMessages,
                              (v) => setState(() => _allowMessages = v),
                            ),
                            _toggle(
                              isArabic ? 'السماح بالمكالمات' : 'Allow calls',
                              Icons.call_rounded,
                              _allowCalls,
                              (v) => setState(() => _allowCalls = v),
                            ),
                            _picker(
                              isArabic
                                  ? 'من يمكنه مراسلتي؟'
                                  : 'Who can message me?',
                              Icons.message_rounded,
                              _messageFrom,
                              isArabic
                                  ? {
                                      'everyone': 'الجميع',
                                      'followers': 'المتابعون',
                                      'nobody': 'لا أحد',
                                    }
                                  : {
                                      'everyone': 'Everyone',
                                      'followers': 'Followers',
                                      'nobody': 'Nobody',
                                    },
                              (v) => setState(() => _messageFrom = v),
                              isArabic,
                            ),
                            _picker(
                              isArabic
                                  ? 'من يمكنه مكالمتي؟'
                                  : 'Who can call me?',
                              Icons.phone_in_talk_rounded,
                              _callFrom,
                              isArabic
                                  ? {
                                      'everyone': 'الجميع',
                                      'followers': 'المتابعون',
                                      'nobody': 'لا أحد',
                                    }
                                  : {
                                      'everyone': 'Everyone',
                                      'followers': 'Followers',
                                      'nobody': 'Nobody',
                                    },
                              (v) => setState(() => _callFrom = v),
                              isArabic,
                            ),
                          ]),
                          _section(isArabic ? 'التطبيق' : 'App', [
                            _toggle(
                              isArabic
                                  ? 'تشغيل تلقائي للمقاطع'
                                  : 'Auto-play videos',
                              Icons.play_circle_rounded,
                              _autoPlay,
                              (v) => setState(() => _autoPlay = v),
                            ),
                            _toggle(
                              isArabic
                                  ? 'تنبيه استهلاك البيانات'
                                  : 'Data usage warning',
                              Icons.data_usage_rounded,
                              _dataWarning,
                              (v) => setState(() => _dataWarning = v),
                            ),
                            _picker(
                              isArabic ? 'حجم الخط' : 'Font size',
                              Icons.text_fields_rounded,
                              _fontSize,
                              isArabic
                                  ? {
                                      'small': 'صغير',
                                      'medium': 'متوسط',
                                      'large': 'كبير',
                                    }
                                  : {
                                      'small': 'Small',
                                      'medium': 'Medium',
                                      'large': 'Large',
                                    },
                              (v) => setState(() => _fontSize = v),
                              isArabic,
                            ),
                          ]),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF8B26D9),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _saving
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
                                isArabic ? 'حفظ التفضيلات' : 'Save preferences',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                  isArabic ? 'التفضيلات' : 'Preferences',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isArabic
                      ? 'إشعارات، خصوصية، وإعدادات التطبيق'
                      : 'Notifications, privacy, and app settings',
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF160B24),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF6E3AA8).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: children.indexed.map((entry) {
              final i = entry.$1;
              final child = entry.$2;
              final isLast = i == children.length - 1;
              return Column(
                children: [
                  child,
                  if (!isLast)
                    const Divider(
                      color: Color(0xFF1E1030),
                      height: 1,
                      indent: 52,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _toggle(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF0C15A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFF0C15A), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF8B26D9),
            activeTrackColor: const Color(0xFF3A174F),
            inactiveThumbColor: const Color(0xFF4A3470),
            inactiveTrackColor: const Color(0xFF1B102B),
          ),
        ],
      ),
    );
  }

  Widget _picker(
    String label,
    IconData icon,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
    bool isArabic,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF0C15A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFF0C15A), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () =>
                _showPicker(label, options, value, onChanged, isArabic),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1040),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    options[value] ?? value,
                    style: const TextStyle(
                      color: Color(0xFFCCA0FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF8B26D9),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPicker(
    String title,
    Map<String, String> options,
    String current,
    ValueChanged<String> onChanged,
    bool isArabic,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF160B24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF4A3470),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            ...options.entries.map(
              (e) => GestureDetector(
                onTap: () {
                  onChanged(e.key);
                  Navigator.of(context).pop();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: e.key == current
                        ? const Color(0xFF2A1040)
                        : const Color(0xFF1B102B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: e.key == current
                          ? const Color(0xFF8B26D9)
                          : const Color(0xFF4A3470),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        e.value,
                        style: TextStyle(
                          color: e.key == current
                              ? Colors.white
                              : const Color(0xFFBCAED6),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (e.key == current)
                        const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF8B26D9),
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
