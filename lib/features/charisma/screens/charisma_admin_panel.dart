import 'package:flutter/material.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../models/charisma_models.dart';
import '../services/charisma_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

const _kSurface = Color(0xFF110D25);
const _kCard    = Color(0xFF160F2E);
const _kBorder  = Color(0xFF2A1E50);
const _kPurple  = Color(0xFF8B26D9);
const _kGold    = Color(0xFFF0C15A);
const _kRed     = Color(0xFFEF4444);
const _kCrown   = Color(0xFFFFD700);

class CharismaAdminPanel extends StatefulWidget {
  const CharismaAdminPanel({super.key, this.isArabic = false});

  final bool isArabic;

  @override
  State<CharismaAdminPanel> createState() => _CharismaAdminPanelState();
}

class _CharismaAdminPanelState extends State<CharismaAdminPanel>
    with SingleTickerProviderStateMixin {
  static const _service = CharismaService();

  late TabController _tabs;

  bool _listLoading = true;
  String? _listError;
  List<CharismaActiveChallenge> _challenges = [];

  bool _creating = false;
  bool _actionLoading = false;

  // Create form state
  final _titleController = TextEditingController();
  final _titleArController = TextEditingController();
  String _scope = 'official';
  DateTime _startsAt = DateTime.now().toUtc().add(const Duration(hours: 1));
  DateTime _endsAt   = DateTime.now().toUtc().add(const Duration(hours: 25));
  int _rewardCoins   = 100000;

  bool get _ar => context.isArabic;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadList();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleController.dispose();
    _titleArController.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    setState(() { _listLoading = true; _listError = null; });
    try {
      final data = await _service.adminGetChallenges();
      if (!mounted) return;
      setState(() { _challenges = data; _listLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _listLoading = false; _listError = e.toString(); });
    }
  }

  Future<void> _createChallenge() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnack(_ar ? 'أدخل عنوان التحدي' : 'Enter challenge title');
      return;
    }
    setState(() => _creating = true);
    try {
      await _service.adminCreateChallenge(
        title:       title,
        titleAr:     _titleArController.text.trim().isEmpty
            ? null
            : _titleArController.text.trim(),
        scope:       _scope,
        startsAt:    _startsAt,
        endsAt:      _endsAt,
        rewardCoins: _rewardCoins,
      );
      _titleController.clear();
      _titleArController.clear();
      await _loadList();
      if (mounted) {
        _tabs.animateTo(0);
        _showSnack(_ar ? 'تم إنشاء التحدي' : 'Challenge created');
      }
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _crown(CharismaActiveChallenge ac) async {
    final confirm = await _confirmDialog(
      _ar ? 'تتويج الفائز' : 'Crown Winner',
      _ar ? 'سيتم تحديد الفائز وإرسال المكافأة. لا يمكن التراجع.'
          : 'The top-voted participant will be crowned and rewarded. This cannot be undone.',
    );
    if (confirm != true) return;
    setState(() => _actionLoading = true);
    try {
      final result = await _service.adminCrownWinner(ac.challenge.id);
      await _loadList();
      if (mounted) _showWinnerSnack(result);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _cancel(CharismaActiveChallenge ac) async {
    final confirm = await _confirmDialog(
      _ar ? 'إلغاء التحدي' : 'Cancel Challenge',
      _ar ? 'هل تريد إلغاء هذا التحدي؟' : 'Cancel this challenge permanently?',
    );
    if (confirm != true) return;
    setState(() => _actionLoading = true);
    try {
      await _service.adminCancelChallenge(ac.challenge.id);
      await _loadList();
      if (mounted) _showSnack(_ar ? 'تم الإلغاء' : 'Challenge cancelled');
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<bool?> _confirmDialog(String title, String body) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(body,  style: const TextStyle(color: Colors.white70, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_ar ? 'إلغاء' : 'Cancel',
                  style: const TextStyle(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_ar ? 'تأكيد' : 'Confirm',
                  style: const TextStyle(color: _kGold)),
            ),
          ],
        ),
      );

  void _showSnack(String msg) {
    if (!mounted) return;
    SroodToast.show(context, msg, type: SroodToastType.info);
  }

  void _showWinnerSnack(Map<String, dynamic> result) {
    final coins = (result['reward_coins'] as num?)?.toInt() ?? 100000;
    _showSnack(_ar
        ? '👑 تم التتويج! المكافأة: ${_fmt(coins)} عملة'
        : '👑 Winner crowned! Reward: ${_fmt(coins)} coins');
  }

  String _localizeError(String msg) {
    if (msg.contains('no_participants'))          return _ar ? 'لا يوجد مشاركون'        : 'No participants';
    if (msg.contains('challenge_not_active') ||
        msg.contains('challenge_not_ended')) {
      return _ar ? 'التحدي غير صالح للتتويج' : 'Challenge not eligible for crowning';
    }
    if (msg.contains('already_crowned'))          return _ar ? 'تم التتويج مسبقاً'       : 'Already crowned';
    if (msg.contains('insufficient_permissions')) return _ar ? 'ليس لديك صلاحية'         : 'No permission';
    if (msg.contains('starts_after_ends'))        return _ar ? 'وقت البداية بعد النهاية' : 'Start must be before end';
    return msg;
  }

  static String _fmt(int coins) {
    if (coins >= 1000000) return '${(coins / 1000000).toStringAsFixed(1)}M';
    if (coins >= 1000)    return '${(coins / 1000).toStringAsFixed(0)}K';
    return '$coins';
  }

  static String _fmtDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: TabBar(
            controller: _tabs,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: _kPurple.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _kPurple.withValues(alpha: 0.5)),
            ),
            labelColor: _kGold,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: _ar ? 'التحديات'  : 'Challenges'),
              Tab(text: _ar ? 'إنشاء تحدي' : 'Create'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildListTab(),
              _buildCreateTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── List tab ───────────────────────────────────────────────────────────────

  Widget _buildListTab() {
    if (_listLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPurple));
    }
    if (_listError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 40),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadList,
              child: Text(_ar ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(color: _kPurple)),
            ),
          ],
        ),
      );
    }
    if (_challenges.isEmpty) {
      return Center(
        child: Text(
          _ar ? 'لا توجد تحديات' : 'No challenges yet',
          style: const TextStyle(color: Colors.white38),
        ),
      );
    }
    return RefreshIndicator(
      color: _kPurple,
      backgroundColor: _kCard,
      onRefresh: _loadList,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _challenges.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildAdminCard(_challenges[i]),
      ),
    );
  }

  Widget _buildAdminCard(CharismaActiveChallenge ac) {
    final c = ac.challenge;
    final canCrown  = !c.isCrowned && !c.isCancelled && ac.participantCount > 0;
    final canCancel = !c.isFinished;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: c.isCrowned ? _kCrown.withValues(alpha: 0.5)
              : c.isCancelled ? _kRed.withValues(alpha: 0.3)
              : _kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status
          Row(
            children: [
              Expanded(
                child: Text(
                  c.localizedTitle(_ar),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: c.status, isArabic: _ar),
            ],
          ),
          const SizedBox(height: 6),
          // Scope + participants
          Row(
            children: [
              Text(
                c.scope == 'official'
                    ? (_ar ? '🏛 رسمي' : '🏛 Official')
                    : (_ar ? '🏢 وكالة'  : '🏢 Agency'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.people_rounded, color: Colors.white38, size: 12),
              const SizedBox(width: 3),
              Text('${ac.participantCount}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(width: 12),
              Text(
                '${_fmtDate(c.startsAt)} → ${_fmtDate(c.endsAt)}',
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
          if (canCrown || canCancel) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (canCrown)
                  Expanded(
                    child: _SmallBtn(
                      label: _ar ? '👑 تتويج' : '👑 Crown',
                      color: _kCrown,
                      loading: _actionLoading,
                      onTap: () => _crown(ac),
                    ),
                  ),
                if (canCrown && canCancel) const SizedBox(width: 8),
                if (canCancel)
                  _SmallBtn(
                    label: _ar ? 'إلغاء' : 'Cancel',
                    color: _kRed,
                    loading: _actionLoading,
                    onTap: () => _cancel(ac),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Create tab ─────────────────────────────────────────────────────────────

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(_ar ? 'العنوان (إنجليزي)' : 'Title (English) *'),
          const SizedBox(height: 6),
          _Field(controller: _titleController, hint: 'Charisma King'),

          const SizedBox(height: 14),
          _SectionLabel(_ar ? 'العنوان (عربي) — اختياري' : 'Title (Arabic) — optional'),
          const SizedBox(height: 6),
          _Field(controller: _titleArController, hint: 'ملك الكاريزما', textDir: TextDirection.rtl),

          const SizedBox(height: 14),
          _SectionLabel(_ar ? 'النطاق' : 'Scope'),
          const SizedBox(height: 6),
          _ScopeSelector(
            value: _scope,
            isArabic: _ar,
            onChanged: (v) => setState(() => _scope = v),
          ),

          const SizedBox(height: 14),
          _SectionLabel(_ar ? 'وقت البداية' : 'Starts At'),
          const SizedBox(height: 6),
          _DateBtn(
            value: _startsAt,
            isArabic: _ar,
            onTap: () async {
              final dt = await _pickDateTime(_startsAt);
              if (dt != null) setState(() => _startsAt = dt);
            },
          ),

          const SizedBox(height: 14),
          _SectionLabel(_ar ? 'وقت الانتهاء' : 'Ends At'),
          const SizedBox(height: 6),
          _DateBtn(
            value: _endsAt,
            isArabic: _ar,
            onTap: () async {
              final dt = await _pickDateTime(_endsAt);
              if (dt != null) setState(() => _endsAt = dt);
            },
          ),

          const SizedBox(height: 14),
          _SectionLabel(_ar ? 'مكافأة العملات' : 'Reward Coins'),
          const SizedBox(height: 6),
          _RewardSelector(
            value: _rewardCoins,
            isArabic: _ar,
            onChanged: (v) => setState(() => _rewardCoins = v),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _creating ? null : _createChallenge,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                disabledBackgroundColor: _kBorder,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _creating
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _ar ? 'إنشاء التحدي' : 'Create Challenge',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial.toLocal(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (_, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _kPurple, surface: _kCard),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial.toLocal()),
      builder: (_, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _kPurple, surface: _kCard),
        ),
        child: child!,
      ),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute)
        .toUtc();
  }
}

// ── Local helpers ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isArabic});
  final String status;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active'    => (isArabic ? 'نشط'     : 'Active',    const Color(0xFF22C55E)),
      'scheduled' => (isArabic ? 'قادم'     : 'Scheduled', Colors.white54),
      'ended'     => (isArabic ? 'انتهى'    : 'Ended',     Colors.white38),
      'crowned'   => (isArabic ? 'متوَّج'   : 'Crowned',   const Color(0xFFFFD700)),
      _           => (isArabic ? 'ملغى'     : 'Cancelled', const Color(0xFFEF4444)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.textDir});
  final TextEditingController controller;
  final String hint;
  final TextDirection? textDir;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textDirection: textDir,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
      filled: true,
      fillColor: _kSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kPurple),
      ),
    ),
  );
}

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.value, required this.isArabic, required this.onChanged});
  final String value;
  final bool isArabic;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['official', 'agency'].map((s) {
        final selected = value == s;
        final label    = s == 'official'
            ? (isArabic ? '🏛 رسمي' : '🏛 Official')
            : (isArabic ? '🏢 وكالة'  : '🏢 Agency');
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(right: s == 'official' ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? _kPurple.withValues(alpha: 0.2) : _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? _kPurple : _kBorder),
              ),
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        color: selected ? _kGold : Colors.white54,
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DateBtn extends StatelessWidget {
  const _DateBtn({required this.value, required this.isArabic, required this.onTap});
  final DateTime value;
  final bool isArabic;
  final VoidCallback onTap;

  static String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2,'0')}-${l.day.toString().padLeft(2,'0')} '
        '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Text(_fmt(value),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _RewardSelector extends StatelessWidget {
  const _RewardSelector({required this.value, required this.isArabic, required this.onChanged});
  final int value;
  final bool isArabic;
  final ValueChanged<int> onChanged;

  static const _options = [50000, 100000, 200000, 500000];

  static String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _options.map((opt) {
        final sel = value == opt;
        return GestureDetector(
          onTap: () => onChanged(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? _kGold.withValues(alpha: 0.15) : _kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? _kGold.withValues(alpha: 0.6) : _kBorder),
            ),
            child: Text(
              '${_fmt(opt)} 🪙',
              style: TextStyle(
                  color: sel ? _kGold : Colors.white54,
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: loading
              ? SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(color: color, strokeWidth: 2))
              : Text(label,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
