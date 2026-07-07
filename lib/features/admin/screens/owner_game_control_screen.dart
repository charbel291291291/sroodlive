import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../services/owner_game_control_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — private to this file
// ─────────────────────────────────────────────────────────────────────────────

const _kBg = Color(0xFF080A10);
const _kSurface = Color(0xFF10131C);
const _kBorder = Color(0xFF1A2030);
const _kGold = Color(0xFFF0C15A);
const _kGreen = Color(0xFF22C55E);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF60A5FA);
const _kTxt = Color(0xFFF1F5F9);
const _kMuted = Color(0xFF64748B);
const _kOwner = Color(0xFFE040FB); // owner-exclusive accent

const _titleStyle = TextStyle(
  color: _kTxt,
  fontSize: 16,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.2,
);
const _mutedStyle = TextStyle(color: _kMuted, fontSize: 12);

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class OwnerGameControlScreen extends StatefulWidget {
  const OwnerGameControlScreen({super.key});

  static const routeName = '/owner-game-control';

  @override
  State<OwnerGameControlScreen> createState() => _OwnerGameControlScreenState();
}

class _OwnerGameControlScreenState extends State<OwnerGameControlScreen>
    with SingleTickerProviderStateMixin {
  final _svc = const OwnerGameControlService();

  bool _checking = true;
  bool _authorized = false;
  String? _error;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _checkOwner();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _checkOwner() async {
    try {
      final ok = await _svc.isOwner();
      if (!mounted) return;
      setState(() {
        _authorized = ok;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: _kMuted),
        title: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _kOwner,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Owner Game Control',
              style: TextStyle(
                color: _kTxt,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        bottom: _authorized
            ? TabBar(
                controller: _tabs,
                labelColor: _kOwner,
                unselectedLabelColor: _kMuted,
                indicatorColor: _kOwner,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(text: 'Hungry Cat'),
                  Tab(text: 'Gold Ladder'),
                  Tab(text: 'Audit Log'),
                ],
              )
            : null,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_checking) {
      return const Center(
        child: CircularProgressIndicator(color: _kOwner),
      );
    }
    if (!_authorized) {
      return _NotAuthorized(error: _error);
    }
    return TabBarView(
      controller: _tabs,
      children: [
        _HungryCatTab(svc: _svc),
        _GoldLadderTab(svc: _svc),
        _AuditLogTab(svc: _svc),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Not Authorized
// ─────────────────────────────────────────────────────────────────────────────

class _NotAuthorized extends StatelessWidget {
  const _NotAuthorized({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 56, color: _kRed),
            const SizedBox(height: 16),
            const Text(
              'Not Authorized',
              style: TextStyle(
                color: _kTxt,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This panel is restricted to the project owner.',
              style: _mutedStyle,
              textAlign: TextAlign.center,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: _kRed, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.color = _kGold});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _TestOnlyBanner extends StatelessWidget {
  const _TestOnlyBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: _kAmber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: _kAmber, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.activeColor = _kGreen,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _titleStyle.copyWith(fontSize: 13)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: _mutedStyle),
              ],
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: activeColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

Widget _saveBtn(String label, VoidCallback? onPressed) => SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _kOwner,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ),
    );

void _snack(BuildContext ctx, String msg, {bool error = false}) {
  if (!ctx.mounted) return;
  SroodToast.show(ctx, msg, type: error ? SroodToastType.error : SroodToastType.success);
}

Future<bool?> _confirm(BuildContext ctx, String title, String body) {
  return showDialog<bool>(
    context: ctx,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: _titleStyle),
      content: Text(body, style: _mutedStyle.copyWith(fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: _kMuted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: _kRed),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// HUNGRY CAT TAB
// ─────────────────────────────────────────────────────────────────────────────

class _HungryCatTab extends StatefulWidget {
  const _HungryCatTab({required this.svc});
  final OwnerGameControlService svc;

  @override
  State<_HungryCatTab> createState() => _HungryCatTabState();
}

class _HungryCatTabState extends State<_HungryCatTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  String? _error;
  GameSettings? _settings;
  List<HungryCatFood> _foods = const [];

  // config form controllers
  late TextEditingController _maxBetCtrl;
  late TextEditingController _maxPayoutCtrl;
  late TextEditingController _dailyCapCtrl;
  late TextEditingController _eventBoostCtrl;
  String _riskMode = 'normal';

  // food odds controllers — keyed by foodId
  final Map<String, TextEditingController> _weightCtrls = {};

  // force result
  String? _selectedForceFood;
  bool _busy = false;

  // void round
  final _roundIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _maxBetCtrl = TextEditingController();
    _maxPayoutCtrl = TextEditingController();
    _dailyCapCtrl = TextEditingController();
    _eventBoostCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _maxBetCtrl.dispose();
    _maxPayoutCtrl.dispose();
    _dailyCapCtrl.dispose();
    _eventBoostCtrl.dispose();
    for (final c in _weightCtrls.values) {
      c.dispose();
    }
    _roundIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.svc.fetchHungryCatFullConfig();
      for (final c in _weightCtrls.values) {
        c.dispose();
      }
      _weightCtrls.clear();
      for (final f in result.foods) {
        _weightCtrls[f.foodId] =
            TextEditingController(text: f.weight.toStringAsFixed(1));
      }
      if (!mounted) return;
      setState(() {
        _settings = result.settings;
        _foods = result.foods;
        _maxBetCtrl.text = result.settings.maxBet.toString();
        _maxPayoutCtrl.text = result.settings.maxPayout.toString();
        _dailyCapCtrl.text = result.settings.dailyPayoutCap.toString();
        _eventBoostCtrl.text =
            result.settings.eventMultiplierBoost.toStringAsFixed(2);
        _riskMode = result.settings.riskMode;
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

  Future<void> _saveConfig() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.svc.updateGameConfig(
        gameKey: 'hungry_cat',
        isEnabled: _settings!.isEnabled,
        testMode: _settings!.testMode,
        riskMode: _riskMode,
        eventMode: _settings!.eventMode,
        eventMultiplierBoost: double.tryParse(_eventBoostCtrl.text),
        maxBet: int.tryParse(_maxBetCtrl.text),
        maxPayout: int.tryParse(_maxPayoutCtrl.text),
        dailyPayoutCap: int.tryParse(_dailyCapCtrl.text),
      );
      if (!mounted) return;
      _snack(context, 'Config saved');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveFoodOdds(HungryCatFood food) async {
    if (_busy) return;
    final ctrl = _weightCtrls[food.foodId];
    final w = double.tryParse(ctrl?.text ?? '');
    if (w == null || w < 0.1 || w > 1000) {
      _snack(context, 'Weight must be 0.1–1000', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.svc.updateHungryCatFoodOdds(
        foodId: food.foodId,
        weight: w,
        isActive: food.isActive,
      );
      if (!mounted) return;
      _snack(context, '${food.name} odds saved');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFoodActive(HungryCatFood food) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.svc.updateHungryCatFoodOdds(
        foodId: food.foodId,
        isActive: !food.isActive,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forceResult() async {
    if (_selectedForceFood == null) return;
    final ok = await _confirm(
      context,
      'Force Result?',
      'The next Hungry Cat round will always land on $_selectedForceFood.\n\nThis clears after one round. Test mode must be ON.',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.svc.setHungryCatForcedResult(_selectedForceFood!);
      if (!mounted) return;
      _snack(context, 'Forced result set: $_selectedForceFood');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearForce() async {
    setState(() => _busy = true);
    try {
      await widget.svc.clearHungryCatForcedResult();
      if (!mounted) return;
      _snack(context, 'Forced result cleared');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _voidRound() async {
    final roundId = _roundIdCtrl.text.trim();
    if (roundId.isEmpty) {
      _snack(context, 'Enter a round UUID', error: true);
      return;
    }
    final ok = await _confirm(
      context,
      'Void Round?',
      'All pending bets in round $roundId will be refunded. This cannot be undone.',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.svc.voidHungryCatRound(roundId);
      if (!mounted) return;
      _roundIdCtrl.clear();
      _snack(context, 'Round voided and bets refunded');
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kOwner));
    }
    if (_error != null) {
      return _ErrorRetry(error: _error!, onRetry: _load);
    }
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Global config ──────────────────────────────────────────────────
        const _SectionTitle('Global Config'),
        _Card(
          child: Column(
            children: [
              _ToggleRow(
                label: 'Game Enabled',
                subtitle: s.isEnabled ? 'Running' : 'Paused',
                value: s.isEnabled,
                onChanged: (v) => setState(
                    () => _settings = _copySettings(s, isEnabled: v)),
              ),
              const Divider(color: _kBorder, height: 20),
              _ToggleRow(
                label: 'Test Mode',
                subtitle: 'Required for forced results',
                value: s.testMode,
                activeColor: _kAmber,
                onChanged: (v) =>
                    setState(() => _settings = _copySettings(s, testMode: v)),
              ),
              const Divider(color: _kBorder, height: 20),
              _ToggleRow(
                label: 'Event Mode',
                subtitle: 'Apply event multiplier boost',
                value: s.eventMode,
                activeColor: _kBlue,
                onChanged: (v) =>
                    setState(() => _settings = _copySettings(s, eventMode: v)),
              ),
              const Divider(color: _kBorder, height: 20),
              _LabeledField(
                  label: 'Risk Mode',
                  child: _RiskDropdown(
                    value: _riskMode,
                    onChanged: (v) => setState(() => _riskMode = v!),
                  )),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Event Boost (×)',
                  child: _NumField(
                      ctrl: _eventBoostCtrl, hint: '1.00', decimal: true)),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Max Bet (coins)',
                  child: _NumField(ctrl: _maxBetCtrl, hint: '100000')),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Max Payout (coins)',
                  child: _NumField(ctrl: _maxPayoutCtrl, hint: '1000000')),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Daily Payout Cap (coins)',
                  child: _NumField(ctrl: _dailyCapCtrl, hint: '10000000')),
              const SizedBox(height: 16),
              _saveBtn('Save Config', _busy ? null : _saveConfig),
            ],
          ),
        ),

        // ── Odds control ───────────────────────────────────────────────────
        const _SectionTitle('Food Odds'),
        if (_foods.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No foods configured.', style: _mutedStyle),
          )
        else
          ..._foods.map((food) => _FoodOddsCard(
                food: food,
                ctrl: _weightCtrls[food.foodId]!,
                busy: _busy,
                onSave: () => _saveFoodOdds(food),
                onToggle: () => _toggleFoodActive(food),
              )),

        // ── Force result (test only) ───────────────────────────────────────
        const _SectionTitle('Force Next Result', color: _kAmber),
        _TestOnlyBanner(
          s.testMode
              ? 'Test mode is ON — forced result is active.'
              : 'Enable test mode above to unlock forced results.',
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.forcedNextResult != null) ...[
                Row(
                  children: [
                    const Icon(Icons.lock_clock, size: 14, color: _kAmber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Active: ${s.forcedNextResult}  '
                        '(expires ${_fmt(s.forcedNextResultExpiresAt)})',
                        style: const TextStyle(color: _kAmber, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearForce,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: const BorderSide(color: _kRed),
                  ),
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Clear Forced Result'),
                ),
                const Divider(color: _kBorder, height: 24),
              ],
              DropdownButtonFormField<String>(
                initialValue: _selectedForceFood,
                dropdownColor: _kSurface,
                decoration: _inputDeco('Select food outcome'),
                items: _foods
                    .where((f) => f.isActive)
                    .map(
                      (f) => DropdownMenuItem(
                        value: f.foodId,
                        child: Text(
                          '${f.icon}  ${f.name}  (${f.multiplier}×)',
                          style: const TextStyle(color: _kTxt, fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: s.testMode
                    ? (v) => setState(() => _selectedForceFood = v)
                    : null,
              ),
              const SizedBox(height: 12),
              _saveBtn(
                'Force This Result',
                (s.testMode && _selectedForceFood != null && !_busy)
                    ? _forceResult
                    : null,
              ),
            ],
          ),
        ),

        // ── Emergency void ─────────────────────────────────────────────────
        const _SectionTitle('Emergency Void Round', color: _kRed),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voids a round and refunds all pending bets. Irreversible.',
                style: _mutedStyle,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _roundIdCtrl,
                style: const TextStyle(color: _kTxt, fontSize: 12),
                decoration: _inputDeco('Round UUID'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _voidRound,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Void Round',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  GameSettings _copySettings(
    GameSettings s, {
    bool? isEnabled,
    bool? testMode,
    bool? eventMode,
  }) =>
      GameSettings(
        gameKey: s.gameKey,
        isEnabled: isEnabled ?? s.isEnabled,
        testMode: testMode ?? s.testMode,
        maxBet: s.maxBet,
        maxPayout: s.maxPayout,
        dailyPayoutCap: s.dailyPayoutCap,
        riskMode: s.riskMode,
        eventMode: eventMode ?? s.eventMode,
        eventMultiplierBoost: s.eventMultiplierBoost,
        forcedNextResult: s.forcedNextResult,
        forcedNextResultExpiresAt: s.forcedNextResultExpiresAt,
        forcedCrashMultiplier: s.forcedCrashMultiplier,
        forcedCrashMultiplierExpiresAt: s.forcedCrashMultiplierExpiresAt,
      );
}

class _FoodOddsCard extends StatelessWidget {
  const _FoodOddsCard({
    required this.food,
    required this.ctrl,
    required this.busy,
    required this.onSave,
    required this.onToggle,
  });

  final HungryCatFood food;
  final TextEditingController ctrl;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onToggle;

  Color get _rarityColor {
    switch (food.rarity) {
      case 'legendary':
        return _kGold;
      case 'epic':
        return _kOwner;
      case 'rare':
        return _kBlue;
      case 'uncommon':
        return _kGreen;
      default:
        return _kMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Text(food.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(food.name,
                        style: _titleStyle.copyWith(fontSize: 13)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _rarityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        food.rarity,
                        style: TextStyle(
                            color: _rarityColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${food.multiplier}×  •  sort ${food.sortOrder}',
                  style: _mutedStyle,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: TextFormField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              style: const TextStyle(color: _kTxt, fontSize: 12),
              decoration: _inputDeco('weight'),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: food.isActive,
            activeThumbColor: _kGreen,
            onChanged: busy ? null : (_) => onToggle(),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: busy ? null : onSave,
            icon: const Icon(Icons.check_rounded, size: 18),
            color: _kGreen,
            tooltip: 'Save odds',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROCKET CRASH TAB
// ─────────────────────────────────────────────────────────────────────────────

class _RocketCrashTab extends StatefulWidget {
  const _RocketCrashTab({required this.svc});
  final OwnerGameControlService svc;

  @override
  State<_RocketCrashTab> createState() => _RocketCrashTabState();
}

class _RocketCrashTabState extends State<_RocketCrashTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  String? _error;
  GameSettings? _settings;

  late TextEditingController _maxBetCtrl;
  late TextEditingController _maxPayoutCtrl;
  late TextEditingController _dailyCapCtrl;
  late TextEditingController _forcedMultCtrl;
  String _riskMode = 'normal';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _maxBetCtrl = TextEditingController();
    _maxPayoutCtrl = TextEditingController();
    _dailyCapCtrl = TextEditingController();
    _forcedMultCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _maxBetCtrl.dispose();
    _maxPayoutCtrl.dispose();
    _dailyCapCtrl.dispose();
    _forcedMultCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.svc.fetchCrashConfig();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _maxBetCtrl.text = s.maxBet.toString();
        _maxPayoutCtrl.text = s.maxPayout.toString();
        _dailyCapCtrl.text = s.dailyPayoutCap.toString();
        _riskMode = s.riskMode;
        if (s.forcedCrashMultiplier != null) {
          _forcedMultCtrl.text = s.forcedCrashMultiplier!.toStringAsFixed(2);
        }
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

  Future<void> _saveConfig() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.svc.updateGameConfig(
        gameKey: 'crash_rocket',
        isEnabled: _settings!.isEnabled,
        testMode: _settings!.testMode,
        riskMode: _riskMode,
        maxBet: int.tryParse(_maxBetCtrl.text),
        maxPayout: int.tryParse(_maxPayoutCtrl.text),
        dailyPayoutCap: int.tryParse(_dailyCapCtrl.text),
      );
      if (!mounted) return;
      _snack(context, 'Crash config saved');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forceMult() async {
    final m = double.tryParse(_forcedMultCtrl.text);
    if (m == null || m < 1.01 || m > 1000) {
      _snack(context, 'Multiplier must be 1.01–1000', error: true);
      return;
    }
    final ok = await _confirm(
      context,
      'Force Crash Multiplier?',
      'The next rocket round will crash at exactly $m×.\n\nTest mode must be ON. Clears after one round.',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.svc.setCrashForcedMultiplier(m);
      if (!mounted) return;
      _snack(context, 'Forced multiplier set: $m×');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearMult() async {
    setState(() => _busy = true);
    try {
      await widget.svc.clearCrashForcedMultiplier();
      if (!mounted) return;
      _forcedMultCtrl.clear();
      _snack(context, 'Forced multiplier cleared');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kOwner));
    }
    if (_error != null) {
      return _ErrorRetry(error: _error!, onRetry: _load);
    }
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _SectionTitle('Global Config'),
        _Card(
          child: Column(
            children: [
              _ToggleRow(
                label: 'Game Enabled',
                value: s.isEnabled,
                onChanged: (v) => setState(
                    () => _settings = _copyCrash(s, isEnabled: v)),
              ),
              const Divider(color: _kBorder, height: 20),
              _ToggleRow(
                label: 'Test Mode',
                subtitle: 'Required for forced crash multiplier',
                value: s.testMode,
                activeColor: _kAmber,
                onChanged: (v) =>
                    setState(() => _settings = _copyCrash(s, testMode: v)),
              ),
              const Divider(color: _kBorder, height: 20),
              _LabeledField(
                  label: 'Risk Mode',
                  child: _RiskDropdown(
                      value: _riskMode,
                      onChanged: (v) => setState(() => _riskMode = v!))),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Max Bet (coins)',
                  child: _NumField(ctrl: _maxBetCtrl, hint: '100000')),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Max Payout (coins)',
                  child: _NumField(ctrl: _maxPayoutCtrl, hint: '1000000')),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Daily Payout Cap (coins)',
                  child: _NumField(ctrl: _dailyCapCtrl, hint: '10000000')),
              const SizedBox(height: 16),
              _saveBtn('Save Config', _busy ? null : _saveConfig),
            ],
          ),
        ),

        const _SectionTitle('Force Crash Multiplier', color: _kAmber),
        _TestOnlyBanner(
          s.testMode
              ? 'Test mode is ON.'
              : 'Enable test mode to force a crash point.',
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.forcedCrashMultiplier != null) ...[
                Row(
                  children: [
                    const Icon(Icons.lock_clock, size: 14, color: _kAmber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Active: ${s.forcedCrashMultiplier}×  '
                        '(expires ${_fmt(s.forcedCrashMultiplierExpiresAt)})',
                        style: const TextStyle(color: _kAmber, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearMult,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: const BorderSide(color: _kRed),
                  ),
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Clear'),
                ),
                const Divider(color: _kBorder, height: 24),
              ],
              TextFormField(
                controller: _forcedMultCtrl,
                enabled: s.testMode,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                style: const TextStyle(color: _kTxt, fontSize: 13),
                decoration: _inputDeco('e.g. 2.50'),
              ),
              const SizedBox(height: 12),
              _saveBtn(
                'Force This Multiplier',
                (s.testMode && !_busy) ? _forceMult : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  GameSettings _copyCrash(GameSettings s,
          {bool? isEnabled, bool? testMode}) =>
      GameSettings(
        gameKey: s.gameKey,
        isEnabled: isEnabled ?? s.isEnabled,
        testMode: testMode ?? s.testMode,
        maxBet: s.maxBet,
        maxPayout: s.maxPayout,
        dailyPayoutCap: s.dailyPayoutCap,
        riskMode: s.riskMode,
        eventMode: s.eventMode,
        eventMultiplierBoost: s.eventMultiplierBoost,
        forcedCrashMultiplier: s.forcedCrashMultiplier,
        forcedCrashMultiplierExpiresAt: s.forcedCrashMultiplierExpiresAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// GOLD LADDER TAB
// ─────────────────────────────────────────────────────────────────────────────

class _GoldLadderTab extends StatefulWidget {
  const _GoldLadderTab({required this.svc});
  final OwnerGameControlService svc;

  @override
  State<_GoldLadderTab> createState() => _GoldLadderTabState();
}

class _GoldLadderTabState extends State<_GoldLadderTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  String? _error;
  GameSettings? _settings;

  late TextEditingController _maxBetCtrl;
  late TextEditingController _maxPayoutCtrl;
  late TextEditingController _dailyCapCtrl;
  String _riskMode = 'normal';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _maxBetCtrl = TextEditingController();
    _maxPayoutCtrl = TextEditingController();
    _dailyCapCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _maxBetCtrl.dispose();
    _maxPayoutCtrl.dispose();
    _dailyCapCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.svc.fetchGoldLadderConfig();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _maxBetCtrl.text = s.maxBet.toString();
        _maxPayoutCtrl.text = s.maxPayout.toString();
        _dailyCapCtrl.text = s.dailyPayoutCap.toString();
        _riskMode = s.riskMode;
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

  Future<void> _saveConfig() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.svc.updateGameConfig(
        gameKey: 'gold_ladder',
        isEnabled: _settings!.isEnabled,
        testMode: _settings!.testMode,
        riskMode: _riskMode,
        maxBet: int.tryParse(_maxBetCtrl.text),
        maxPayout: int.tryParse(_maxPayoutCtrl.text),
        dailyPayoutCap: int.tryParse(_dailyCapCtrl.text),
      );
      if (!mounted) return;
      _snack(context, 'Gold Ladder config saved');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kOwner));
    }
    if (_error != null) {
      return _ErrorRetry(error: _error!, onRetry: _load);
    }
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _SectionTitle('Gold Ladder Config'),
        _Card(
          child: Column(
            children: [
              _ToggleRow(
                label: 'Game Enabled',
                value: s.isEnabled,
                onChanged: (v) => setState(
                    () => _settings = _copy(s, isEnabled: v)),
              ),
              const Divider(color: _kBorder, height: 20),
              _ToggleRow(
                label: 'Test Mode',
                value: s.testMode,
                activeColor: _kAmber,
                onChanged: (v) =>
                    setState(() => _settings = _copy(s, testMode: v)),
              ),
              const Divider(color: _kBorder, height: 20),
              _LabeledField(
                  label: 'Risk Mode',
                  child: _RiskDropdown(
                      value: _riskMode,
                      onChanged: (v) => setState(() => _riskMode = v!))),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Max Entry Fee (coins)',
                  child: _NumField(ctrl: _maxBetCtrl, hint: '1000')),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Max Prize (coins)',
                  child: _NumField(ctrl: _maxPayoutCtrl, hint: '1000000')),
              const SizedBox(height: 12),
              _LabeledField(
                  label: 'Daily Payout Cap (coins)',
                  child: _NumField(ctrl: _dailyCapCtrl, hint: '10000000')),
              const SizedBox(height: 16),
              _saveBtn('Save Config', _busy ? null : _saveConfig),
            ],
          ),
        ),
        const _SectionTitle('Difficulty & Rewards'),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Question difficulty mix and reward tiers are managed via the '
                'gold_ladder_questions table and Gold Ladder game logic. '
                'Use the Supabase dashboard or a future admin UI to '
                'add, edit, or disable questions.',
                style: _mutedStyle,
              ),
              const SizedBox(height: 12),
              const Text(
                'Safe points: Q5, Q10\n'
                'Max questions: 12\n'
                'Powers: remove_two, crowd_pulse, second_chance',
                style: TextStyle(color: _kBlue, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  GameSettings _copy(GameSettings s,
          {bool? isEnabled, bool? testMode}) =>
      GameSettings(
        gameKey: s.gameKey,
        isEnabled: isEnabled ?? s.isEnabled,
        testMode: testMode ?? s.testMode,
        maxBet: s.maxBet,
        maxPayout: s.maxPayout,
        dailyPayoutCap: s.dailyPayoutCap,
        riskMode: s.riskMode,
        eventMode: s.eventMode,
        eventMultiplierBoost: s.eventMultiplierBoost,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// AUDIT LOG TAB
// ─────────────────────────────────────────────────────────────────────────────

class _AuditLogTab extends StatefulWidget {
  const _AuditLogTab({required this.svc});
  final OwnerGameControlService svc;

  @override
  State<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<_AuditLogTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  String? _error;
  List<OwnerGameAuditEntry> _logs = const [];
  String? _filterGame;

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
      final logs = await widget.svc.fetchAuditLog(
        gameType: _filterGame,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _logs = logs;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _filterBar(),
        if (_loading)
          const Expanded(
            child: Center(child: CircularProgressIndicator(color: _kOwner)),
          )
        else if (_error != null)
          Expanded(child: _ErrorRetry(error: _error!, onRetry: _load))
        else if (_logs.isEmpty)
          const Expanded(
            child: Center(
              child: Text('No audit entries.', style: _mutedStyle),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: _logs.length,
              itemBuilder: (_, i) => _AuditEntryTile(entry: _logs[i]),
            ),
          ),
      ],
    );
  }

  Widget _filterBar() {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  null,
                  'hungry_cat',
                  'gold_ladder',
                ].map((g) {
                  final active = _filterGame == g;
                  final label = g == null ? 'All' : g.replaceAll('_', ' ');
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                      selected: active,
                      selectedColor: _kOwner.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: active ? _kOwner : _kMuted,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) {
                        setState(() => _filterGame = g);
                        _load();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: _kMuted,
          ),
        ],
      ),
    );
  }
}

class _AuditEntryTile extends StatelessWidget {
  const _AuditEntryTile({required this.entry});
  final OwnerGameAuditEntry entry;

  Color get _dot {
    if (entry.action.contains('void')) return _kRed;
    if (entry.action.contains('forced') || entry.action.contains('force')) {
      return _kAmber;
    }
    if (entry.action.contains('clear')) return _kBlue;
    return _kGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _dot,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.action.replaceAll('_', ' '),
                  style: _titleStyle.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.gameType}  •  ${_fmtFull(entry.createdAt)}',
                  style: _mutedStyle,
                ),
                if (entry.newValue != null && entry.newValue!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    entry.newValue
                            ?.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('  ') ??
                        '',
                    style: const TextStyle(color: _kBlue, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kRed, size: 40),
            const SizedBox(height: 12),
            Text(error,
                style: const TextStyle(color: _kMuted, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: _kOwner),
                child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _mutedStyle),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.ctrl,
    required this.hint,
    this.decimal = false,
  });

  final TextEditingController ctrl;
  final String hint;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: decimal
          ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
          : [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: _kTxt, fontSize: 13),
      decoration: _inputDeco(hint),
    );
  }
}

class _RiskDropdown extends StatelessWidget {
  const _RiskDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: _kSurface,
      decoration: _inputDeco('Risk Mode'),
      items: const [
        DropdownMenuItem(
          value: 'conservative',
          child: Text('Conservative',
              style: TextStyle(color: _kTxt, fontSize: 13)),
        ),
        DropdownMenuItem(
          value: 'normal',
          child: Text('Normal', style: TextStyle(color: _kTxt, fontSize: 13)),
        ),
        DropdownMenuItem(
          value: 'aggressive',
          child: Text('Aggressive',
              style: TextStyle(color: _kTxt, fontSize: 13)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utilities
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _inputDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: _mutedStyle,
      filled: true,
      fillColor: _kBg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kOwner),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _kBorder.withValues(alpha: 0.5)),
      ),
    );

String _fmt(DateTime? dt) {
  if (dt == null) return '—';
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _fmtFull(DateTime dt) {
  final l = dt.toLocal();
  return '${l.year}-${_p(l.month)}-${_p(l.day)} '
      '${_p(l.hour)}:${_p(l.minute)}:${_p(l.second)}';
}

String _p(int n) => n.toString().padLeft(2, '0');
