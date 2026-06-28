import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../services/hungry_cat_admin_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (matches admin_dashboard_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0C0E14);
const _kSurface = Color(0xFF141720);
const _kBorder  = Color(0xFF1E2435);
const _kGold    = Color(0xFFF0C15A);
const _kGreen   = Color(0xFF22C55E);
const _kAmber   = Color(0xFFF59E0B);
const _kRed     = Color(0xFFEF4444);
const _kBlue    = Color(0xFF60A5FA);
const _kPurple  = Color(0xFF8B5CF6);
const _kTxt     = Color(0xFFF1F5F9);
const _kMuted   = Color(0xFF64748B);

// Fallback food list used only when the live DB config has not loaded yet.
const _kFoodsFallback = [
  {'food_id': 'milk',        'icon': '🥛', 'name': 'Milk',        'multiplier': 1.2},
  {'food_id': 'cookie',      'icon': '🍪', 'name': 'Cookie',      'multiplier': 1.5},
  {'food_id': 'fish',        'icon': '🐟', 'name': 'Fish',        'multiplier': 2.0},
  {'food_id': 'chicken',     'icon': '🍗', 'name': 'Chicken',     'multiplier': 3.0},
  {'food_id': 'shrimp',      'icon': '🍤', 'name': 'Shrimp',      'multiplier': 4.0},
  {'food_id': 'burger',      'icon': '🍔', 'name': 'Burger',      'multiplier': 5.0},
  {'food_id': 'pizza',       'icon': '🍕', 'name': 'Pizza',       'multiplier': 8.0},
  {'food_id': 'cake',        'icon': '🍰', 'name': 'Cake',        'multiplier': 10.0},
  {'food_id': 'tuna',        'icon': '🍣', 'name': 'Tuna',        'multiplier': 12.0},
  {'food_id': 'ice_cream',   'icon': '🍨', 'name': 'Ice Cream',   'multiplier': 15.0},
  {'food_id': 'golden_fish', 'icon': '🐠', 'name': 'Golden Fish', 'multiplier': 25.0},
];

// ─────────────────────────────────────────────────────────────────────────────
// Entry point widget
// ─────────────────────────────────────────────────────────────────────────────

class HungryCatAdminPanel extends StatefulWidget {
  const HungryCatAdminPanel({super.key});

  @override
  State<HungryCatAdminPanel> createState() => _HungryCatAdminPanelState();
}

class _HungryCatAdminPanelState extends State<HungryCatAdminPanel> {
  final _svc = const HungryCatAdminService();

  bool _loading = true;
  String? _error;

  HungryCatGameConfig? _config;
  List<Map<String, dynamic>> _foods = [];
  HungryCatForcedPreview? _preview;
  List<HungryCatAuditEntry> _auditLog = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _svc.fetchConfig(),
        _svc.fetchAllFoods(),
        _svc.previewForcedResult(),
        _svc.fetchAuditLog(limit: 10),
      ]);
      if (!mounted) return;
      setState(() {
        _config  = results[0] as HungryCatGameConfig;
        _foods   = (results[1] as List).cast<Map<String, dynamic>>();
        _preview = results[2] as HungryCatForcedPreview;
        _auditLog = (results[3] as List<HungryCatAuditEntry>);
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

  void _snack(String msg, {bool isError = false}) {
    SroodToast.show(context, msg, type: isError ? SroodToastType.error : SroodToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kGold),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kRed, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: _kMuted)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: _kPurple),
            ),
          ],
        ),
      );
    }

    final cfg = _config!;

    return RefreshIndicator(
      onRefresh: _load,
      color: _kGold,
      backgroundColor: _kSurface,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Header ────────────────────────────────────────────────────────
          _SectionHeader(
            icon: Icons.pets_rounded,
            label: 'Hungry Cat — Game Controls',
            accent: _kGold,
            trailing: _StatusChip(
              label: cfg.isEnabled ? 'LIVE' : 'DISABLED',
              color: cfg.isEnabled ? _kGreen : _kRed,
            ),
          ),
          const SizedBox(height: 20),

          // ── 1. Global Config ──────────────────────────────────────────────
          _GlobalConfigSection(
            config: cfg,
            svc: _svc,
            onSaved: _load,
            snack: _snack,
          ),
          const SizedBox(height: 20),

          // ── 2. Odds Control ───────────────────────────────────────────────
          _OddsControlSection(
            foods: _foods,
            svc: _svc,
            onSaved: _load,
            snack: _snack,
          ),
          const SizedBox(height: 20),

          // ── 3. Admin Preview ──────────────────────────────────────────────
          _AdminPreviewSection(preview: _preview!),
          const SizedBox(height: 20),

          // ── 4. Test Tools (force result + void round) ─────────────────────
          _TestToolsSection(
            config: cfg,
            svc: _svc,
            foods: _foods,
            onRefresh: _load,
            snack: _snack,
          ),
          const SizedBox(height: 20),

          // ── 5. Audit Log ──────────────────────────────────────────────────
          _AuditLogSection(entries: _auditLog, onRefresh: _load),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 1 — Global Config
// ─────────────────────────────────────────────────────────────────────────────

class _GlobalConfigSection extends StatefulWidget {
  const _GlobalConfigSection({
    required this.config,
    required this.svc,
    required this.onSaved,
    required this.snack,
  });

  final HungryCatGameConfig config;
  final HungryCatAdminService svc;
  final VoidCallback onSaved;
  final void Function(String, {bool isError}) snack;

  @override
  State<_GlobalConfigSection> createState() => _GlobalConfigSectionState();
}

class _GlobalConfigSectionState extends State<_GlobalConfigSection> {
  late final TextEditingController _maxBetCtrl;
  late final TextEditingController _maxPayoutCtrl;
  late final TextEditingController _dailyCapCtrl;
  late String _riskMode;
  late bool _eventMode;
  late bool _isEnabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _maxBetCtrl   = TextEditingController(text: c.maxBet.toString());
    _maxPayoutCtrl = TextEditingController(text: c.maxPayout.toString());
    _dailyCapCtrl  = TextEditingController(text: c.dailyPayoutCap.toString());
    _riskMode  = c.riskMode;
    _eventMode = c.eventMode;
    _isEnabled = c.isEnabled;
  }

  @override
  void dispose() {
    _maxBetCtrl.dispose();
    _maxPayoutCtrl.dispose();
    _dailyCapCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.svc.updateConfig(
        isEnabled:      _isEnabled,
        maxBet:         int.tryParse(_maxBetCtrl.text),
        maxPayout:      int.tryParse(_maxPayoutCtrl.text),
        dailyPayoutCap: int.tryParse(_dailyCapCtrl.text),
        riskMode:       _riskMode,
        eventMode:      _eventMode,
      );
      widget.snack('Config saved.');
      widget.onSaved();
    } catch (e) {
      widget.snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Global Config',
      icon: Icons.tune_rounded,
      children: [
        _SwitchRow(
          label: 'Game Enabled',
          value: _isEnabled,
          onChanged: (v) => setState(() => _isEnabled = v),
        ),
        _SwitchRow(
          label: 'Event Mode',
          subtitle: 'Enables bonus multiplier boost',
          value: _eventMode,
          onChanged: (v) => setState(() => _eventMode = v),
        ),
        const SizedBox(height: 12),
        _IntField(ctrl: _maxBetCtrl, label: 'Max Bet (coins)'),
        const SizedBox(height: 10),
        _IntField(ctrl: _maxPayoutCtrl, label: 'Max Payout (coins)'),
        const SizedBox(height: 10),
        _IntField(ctrl: _dailyCapCtrl, label: 'Daily Payout Cap (coins)'),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Risk Mode', style: TextStyle(color: _kTxt, fontSize: 13)),
            const Spacer(),
            DropdownButton<String>(
              value: _riskMode,
              dropdownColor: _kSurface,
              style: const TextStyle(color: _kTxt),
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'conservative', child: Text('Conservative')),
                DropdownMenuItem(value: 'normal',       child: Text('Normal')),
                DropdownMenuItem(value: 'aggressive',   child: Text('Aggressive')),
              ],
              onChanged: (v) => setState(() => _riskMode = v!),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Config'),
            style: FilledButton.styleFrom(backgroundColor: _kPurple),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 2 — Odds Control
// ─────────────────────────────────────────────────────────────────────────────

class _OddsControlSection extends StatelessWidget {
  const _OddsControlSection({
    required this.foods,
    required this.svc,
    required this.onSaved,
    required this.snack,
  });

  final List<Map<String, dynamic>> foods;
  final HungryCatAdminService svc;
  final VoidCallback onSaved;
  final void Function(String, {bool isError}) snack;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Odds Control',
      icon: Icons.bar_chart_rounded,
      children: foods.map((f) {
        return _FoodOddsRow(
          food: f,
          svc: svc,
          onSaved: onSaved,
          snack: snack,
        );
      }).toList(),
    );
  }
}

class _FoodOddsRow extends StatefulWidget {
  const _FoodOddsRow({
    required this.food,
    required this.svc,
    required this.onSaved,
    required this.snack,
  });

  final Map<String, dynamic> food;
  final HungryCatAdminService svc;
  final VoidCallback onSaved;
  final void Function(String, {bool isError}) snack;

  @override
  State<_FoodOddsRow> createState() => _FoodOddsRowState();
}

class _FoodOddsRowState extends State<_FoodOddsRow> {
  late final TextEditingController _weightCtrl;
  late bool _active;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(
        text: (widget.food['weight'] as num).toStringAsFixed(1));
    _active = widget.food['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.svc.updateFoodOdds(
        foodId:   widget.food['food_id'] as String,
        weight:   double.tryParse(_weightCtrl.text),
        isActive: _active,
      );
      widget.snack('${widget.food['name']} updated.');
      widget.onSaved();
    } catch (e) {
      widget.snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon       = widget.food['icon'] as String? ?? '🍽️';
    final name       = widget.food['name'] as String? ?? '';
    final multiplier = widget.food['multiplier'] as num;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(
                      color: _kTxt, fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('×${multiplier.toStringAsFixed(1)}',
                      style: const TextStyle(color: _kGold, fontSize: 11)),
                ],
              ),
            ),
            // Weight field
            SizedBox(
              width: 64,
              child: TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: _kTxt, fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Weight',
                  labelStyle: TextStyle(color: _kMuted, fontSize: 11),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Active toggle
            Switch(
              value: _active,
              activeThumbColor: _kGreen,
              onChanged: (v) => setState(() => _active = v),
            ),
            // Save button
            IconButton(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kGold))
                  : const Icon(Icons.check_rounded, color: _kGold, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 3 — Admin Preview
// ─────────────────────────────────────────────────────────────────────────────

class _AdminPreviewSection extends StatelessWidget {
  const _AdminPreviewSection({required this.preview});

  final HungryCatForcedPreview preview;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Admin Preview',
      icon: Icons.visibility_rounded,
      children: [
        if (!preview.testMode)
          _InfoBanner(
            icon: Icons.info_outline_rounded,
            color: _kBlue,
            message:
                'Test mode is OFF. No forced result is active. '
                'Production rounds use normal weighted odds.',
          )
        else if (!preview.hasForced)
          _InfoBanner(
            icon: Icons.check_circle_outline_rounded,
            color: _kGreen,
            message:
                'Test mode is ON. No forced result is queued — next round will '
                'use normal weighted odds.',
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Text(preview.foodIcon ?? '🍽️',
                    style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FORCED NEXT RESULT',
                        style: TextStyle(
                          color: _kAmber,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        '${preview.foodName ?? ''} ×${preview.multiplier?.toStringAsFixed(1) ?? ''}',
                        style: const TextStyle(
                          color: _kTxt,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (preview.expiresAt != null)
                        Text(
                          'Expires ${_fmtTime(preview.expiresAt!)}',
                          style: const TextStyle(color: _kMuted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')} '
        '(${local.timeZoneName})';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 4 — Test Tools
// ─────────────────────────────────────────────────────────────────────────────

class _TestToolsSection extends StatefulWidget {
  const _TestToolsSection({
    required this.config,
    required this.svc,
    required this.foods,
    required this.onRefresh,
    required this.snack,
  });

  final HungryCatGameConfig config;
  final HungryCatAdminService svc;
  final List<Map<String, dynamic>> foods;
  final VoidCallback onRefresh;
  final void Function(String, {bool isError}) snack;

  @override
  State<_TestToolsSection> createState() => _TestToolsSectionState();
}

class _TestToolsSectionState extends State<_TestToolsSection> {
  String? _selectedOutcome;
  bool _busyTestMode = false;
  bool _busyForce    = false;
  bool _busyClear    = false;

  final _voidCtrl = TextEditingController();
  bool _busyVoid  = false;

  @override
  void dispose() {
    _voidCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleTestMode(bool value) async {
    setState(() => _busyTestMode = true);
    try {
      await widget.svc.setTestMode(value);
      widget.snack(
          value ? 'Test mode ENABLED.' : 'Test mode DISABLED. Forced results cleared.');
      widget.onRefresh();
    } catch (e) {
      widget.snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyTestMode = false);
    }
  }

  Future<void> _forceResult() async {
    final outcome = _selectedOutcome;
    if (outcome == null) {
      widget.snack('Select an outcome first.', isError: true);
      return;
    }

    // Confirmation dialog with explicit warning
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _kAmber),
            SizedBox(width: 10),
            Text('Force Test Result',
                style: TextStyle(color: _kTxt, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kRed.withValues(alpha: 0.4)),
              ),
              child: const Text(
                '⚠️  This is for TESTING ONLY.\n'
                'Do NOT use on live production rounds.\n'
                'This action will be recorded in the audit log.',
                style: TextStyle(
                    color: _kRed, fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Force next round to: $_outcome',
              style: const TextStyle(color: _kTxt, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: _kAmber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm — Test Only',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _busyForce = true);
    try {
      final result = await widget.svc.setForcedNextResult(outcome);
      widget.snack(
          'Forced: ${result['food_name']} ×${result['multiplier']}. '
          'Expires in 30 min.');
      widget.onRefresh();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('test_mode_disabled')) {
        widget.snack('Enable Test Mode first.', isError: true);
      } else if (msg.contains('active_bets_exist')) {
        widget.snack('Cannot force — active bets exist.', isError: true);
      } else if (msg.contains('invalid_outcome_key')) {
        widget.snack('Invalid outcome key.', isError: true);
      } else {
        widget.snack('Error: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busyForce = false);
    }
  }

  String get _outcome {
    if (_selectedOutcome == null) return '—';
    final foods = widget.foods.isNotEmpty ? widget.foods : _kFoodsFallback;
    final f = foods.firstWhere(
      (e) => (e['food_id'] ?? e['id']) == _selectedOutcome,
      orElse: () => {'food_id': '', 'icon': '', 'name': _selectedOutcome!, 'multiplier': 0},
    );
    return '${f['icon']}  ${f['name']} ×${f['multiplier']}';
  }

  Future<void> _clearForced() async {
    setState(() => _busyClear = true);
    try {
      await widget.svc.clearForcedResult();
      widget.snack('Forced result cleared.');
      widget.onRefresh();
    } catch (e) {
      widget.snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyClear = false);
    }
  }

  Future<void> _voidRound() async {
    final roundId = _voidCtrl.text.trim();
    if (roundId.isEmpty) {
      widget.snack('Enter a round UUID.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: _kRed),
            SizedBox(width: 10),
            Text('Void Round',
                style: TextStyle(color: _kTxt, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will refund all pending bets in this round and mark it voided. '
              'This action cannot be undone.',
              style: TextStyle(color: _kMuted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text('Round: $roundId',
                style: const TextStyle(
                    color: _kTxt, fontSize: 11, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Void & Refund'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _busyVoid = true);
    try {
      final res = await widget.svc.voidRound(roundId);
      _voidCtrl.clear();
      widget.snack('Round voided. Refunded ${res['refund_total']} coins.');
      widget.onRefresh();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('round_not_found')) {
        widget.snack('Round not found.', isError: true);
      } else if (msg.contains('already_voided')) {
        widget.snack('Round already voided.', isError: true);
      } else if (msg.contains('round_already_completed')) {
        widget.snack('Cannot void a completed round.', isError: true);
      } else {
        widget.snack('Error: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busyVoid = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg       = widget.config;
    final testOn    = cfg.testMode;
    final hasForced = cfg.forcedNextResult != null;

    return _Card(
      title: 'Test Tools',
      icon: Icons.science_rounded,
      accent: _kAmber,
      children: [
        // ── Warning banner ────────────────────────────────────────────────
        _InfoBanner(
          icon: Icons.warning_amber_rounded,
          color: _kAmber,
          message:
              'These tools are for QA / debug only. '
              'Forced results are blocked in production. '
              'All actions are audit-logged.',
        ),
        const SizedBox(height: 16),

        // ── Test mode toggle ──────────────────────────────────────────────
        _SwitchRow(
          label: 'Test Mode',
          subtitle: testOn
              ? 'ACTIVE — Forced results are allowed'
              : 'OFF — All forced result calls will be rejected',
          value: testOn,
          activeColor: _kAmber,
          loading: _busyTestMode,
          onChanged: _toggleTestMode,
        ),
        const SizedBox(height: 16),

        // ── Force Next Result ─────────────────────────────────────────────
        const Divider(color: _kBorder, height: 24),
        const Text(
          'Force Next Result',
          style: TextStyle(
              color: _kTxt, fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          testOn
              ? 'Select the food the next test round should land on.'
              : 'Enable Test Mode to unlock this section.',
          style: const TextStyle(color: _kMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),

        // Outcome dropdown
        IgnorePointer(
          ignoring: !testOn,
          child: Opacity(
            opacity: testOn ? 1.0 : 0.38,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: testOn ? _kAmber.withValues(alpha: 0.5) : _kBorder),
              ),
              child: DropdownButton<String>(
                value: _selectedOutcome,
                isExpanded: true,
                dropdownColor: _kSurface,
                style: const TextStyle(color: _kTxt),
                underline: const SizedBox.shrink(),
                hint: const Text('Select outcome...',
                    style: TextStyle(color: _kMuted)),
                items: (widget.foods.isNotEmpty ? widget.foods : _kFoodsFallback).map((f) {
                  final id   = (f['food_id'] ?? f['id'] ?? '') as String;
                  final icon = (f['icon'] ?? '') as String;
                  final name = (f['name'] ?? id) as String;
                  final mult = f['multiplier'];
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Row(
                      children: [
                        Text(icon, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Text(name, style: const TextStyle(color: _kTxt)),
                        const Spacer(),
                        Text('×$mult',
                            style: const TextStyle(
                                color: _kGold, fontSize: 12)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: testOn
                    ? (v) => setState(() => _selectedOutcome = v)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: testOn && !_busyForce ? _forceResult : null,
                icon: _busyForce
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.lock_clock_rounded, size: 16),
                label: const Text('Force next test result'),
                style: FilledButton.styleFrom(
                  backgroundColor: testOn ? _kAmber : _kMuted,
                  foregroundColor:
                      testOn ? Colors.black : Colors.white,
                ),
              ),
            ),
            if (hasForced) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _busyClear ? null : _clearForced,
                icon: _busyClear
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kRed))
                    : const Icon(Icons.clear_rounded, color: _kRed),
                tooltip: 'Clear forced result',
              ),
            ],
          ],
        ),

        if (hasForced) ...[
          const SizedBox(height: 8),
          _InfoBanner(
            icon: Icons.lock_clock_rounded,
            color: _kAmber,
            message:
                'Forced result queued: ${cfg.forcedNextResult}. '
                'It will be consumed by the next spin.',
          ),
        ],

        // ── Void Round ────────────────────────────────────────────────────
        const Divider(color: _kBorder, height: 28),
        const Text(
          'Emergency: Void Broken Round',
          style: TextStyle(
              color: _kRed, fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        const Text(
          'Refunds all pending bets in a round that failed to settle. '
          'Cannot void completed rounds. This does not alter the result '
          'in any direction.',
          style: TextStyle(color: _kMuted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _voidCtrl,
          style: const TextStyle(
              color: _kTxt, fontSize: 12, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: 'Round UUID (e.g. 5f3e4a12-...)',
            hintStyle: TextStyle(color: _kMuted, fontSize: 12),
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-f0-9\-]')),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busyVoid ? null : _voidRound,
            icon: _busyVoid
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kRed))
                : const Icon(Icons.block_rounded, color: _kRed, size: 16),
            label: const Text('Void Round & Refund Bets',
                style: TextStyle(color: _kRed)),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kRed)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 5 — Audit Log
// ─────────────────────────────────────────────────────────────────────────────

class _AuditLogSection extends StatelessWidget {
  const _AuditLogSection(
      {required this.entries, required this.onRefresh});

  final List<HungryCatAuditEntry> entries;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Audit Log',
      icon: Icons.history_rounded,
      trailing: IconButton(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded, color: _kMuted, size: 18),
        tooltip: 'Refresh',
      ),
      children: entries.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No audit entries found.',
                      style: TextStyle(color: _kMuted, fontSize: 13)),
                ),
              ),
            ]
          : entries.map((e) => _AuditRow(entry: e)).toList(),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final HungryCatAuditEntry entry;

  Color get _actionColor {
    final a = entry.action;
    if (a.contains('force') || a.contains('test_mode_enabled')) return _kAmber;
    if (a.contains('void'))   return _kRed;
    if (a.contains('clear') || a.contains('disabled')) return _kBlue;
    if (a.contains('consumed')) return _kGreen;
    return _kMuted;
  }

  @override
  Widget build(BuildContext context) {
    final dt = entry.createdAt.toLocal();
    final timeStr =
        '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _actionColor),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.action.replaceAll('hungry_cat_', '').replaceAll('_', ' '),
                    style: TextStyle(
                      color: _actionColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if (entry.metadata.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _metadataPreview(entry.metadata),
                      style: const TextStyle(
                          color: _kMuted, fontSize: 11, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Text(timeStr,
                style: const TextStyle(color: _kMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  String _metadataPreview(Map<String, dynamic> meta) {
    final parts = <String>[];
    for (final e in meta.entries.take(3)) {
      parts.add('${e.key}: ${e.value}');
    }
    return parts.join(' · ');
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.children,
    this.accent,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? _kPurple;
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(
              children: [
                Icon(icon, color: a, size: 18),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: _kTxt,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: accent, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _kTxt,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.activeColor,
    this.loading = false,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: _kTxt, fontWeight: FontWeight.w600, fontSize: 13)),
              if (subtitle != null)
                Text(subtitle!,
                    style: const TextStyle(color: _kMuted, fontSize: 11)),
            ],
          ),
        ),
        if (loading)
          const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kAmber))
        else
          Switch(
            value: value,
            activeTrackColor: (activeColor ?? _kGreen).withValues(alpha: 0.5),
                activeThumbColor: activeColor ?? _kGreen,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _IntField extends StatelessWidget {
  const _IntField({required this.ctrl, required this.label});

  final TextEditingController ctrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: _kTxt, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kMuted, fontSize: 12),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
