import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/rocket_crash_admin_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (shared with hungry_cat_admin_panel.dart)
// ─────────────────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0C0E14);
const _kSurface = Color(0xFF141720);
const _kBorder  = Color(0xFF1E2435);
const _kGold    = Color(0xFFF0C15A);
const _kGreen   = Color(0xFF22C55E);
const _kAmber   = Color(0xFFF59E0B);
const _kRed     = Color(0xFFEF4444);
const _kBlue    = Color(0xFF60A5FA);
const _kTxt     = Color(0xFFF1F5F9);
const _kMuted   = Color(0xFF64748B);

// Quick-pick crash multiplier presets
const _kPresets = [1.10, 1.25, 2.00, 5.00, 10.00];

// ─────────────────────────────────────────────────────────────────────────────
// Entry point widget
// ─────────────────────────────────────────────────────────────────────────────

class RocketCrashAdminPanel extends StatefulWidget {
  const RocketCrashAdminPanel({super.key});

  @override
  State<RocketCrashAdminPanel> createState() => _RocketCrashAdminPanelState();
}

class _RocketCrashAdminPanelState extends State<RocketCrashAdminPanel> {
  final _svc = const RocketCrashAdminService();

  bool _loading = true;
  String? _error;

  RocketCrashGameConfig? _config;
  RocketCrashForcedPreview? _preview;
  List<RocketCrashAuditEntry> _auditLog = [];

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
        _svc.previewForcedResult(),
        _svc.fetchAuditLog(),
      ]);
      if (!mounted) return;
      setState(() {
        _config   = results[0] as RocketCrashGameConfig;
        _preview  = results[1] as RocketCrashForcedPreview;
        _auditLog = results[2] as List<RocketCrashAuditEntry>;
        _loading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _kRed : _kGreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kAmber),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _kRed)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _kSurface,
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(
              children: [
                const Text('🚀',
                    style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Rocket Crash Controls',
                    style: TextStyle(
                      color: _kTxt,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: _kMuted, size: 20),
                  onPressed: _load,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            color: _kSurface,
            child: const TabBar(
              labelColor: _kAmber,
              unselectedLabelColor: _kMuted,
              indicatorColor: _kAmber,
              tabs: [
                Tab(text: 'Test Mode'),
                Tab(text: 'Void Round'),
                Tab(text: 'Audit Log'),
              ],
            ),
          ),

          // Body
          Expanded(
            child: TabBarView(
              children: [
                _TestModeTab(
                  config: _config!,
                  preview: _preview!,
                  svc: _svc,
                  onChanged: _load,
                  snack: _snack,
                ),
                _VoidRoundTab(svc: _svc, snack: _snack, onDone: _load),
                _AuditLogTab(entries: _auditLog, onRefresh: _load),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Test Mode + Forced Multiplier
// ─────────────────────────────────────────────────────────────────────────────

class _TestModeTab extends StatefulWidget {
  const _TestModeTab({
    required this.config,
    required this.preview,
    required this.svc,
    required this.onChanged,
    required this.snack,
  });

  final RocketCrashGameConfig config;
  final RocketCrashForcedPreview preview;
  final RocketCrashAdminService svc;
  final VoidCallback onChanged;
  final void Function(String, {bool isError}) snack;

  @override
  State<_TestModeTab> createState() => _TestModeTabState();
}

class _TestModeTabState extends State<_TestModeTab> {
  final _multiplierCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _multiplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleTestMode(bool value) async {
    setState(() => _busy = true);
    try {
      await widget.svc.setTestMode(value);
      widget.snack(
        value ? 'Test mode ENABLED' : 'Test mode disabled',
      );
      widget.onChanged();
    } catch (e) {
      widget.snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forceMultiplier() async {
    final raw = _multiplierCtrl.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || value < 1.01 || value > 100.00) {
      widget.snack('Enter a value between 1.01 and 100.00', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.svc.setForcedNextMultiplier(value);
      if (!mounted) return;
      _multiplierCtrl.clear();
      widget.snack(res['warning']?.toString() ??
          'Forced crash set to ${value.toStringAsFixed(2)}×');
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      widget.snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearForced() async {
    setState(() => _busy = true);
    try {
      await widget.svc.clearForcedMultiplier();
      if (!mounted) return;
      widget.snack('Forced multiplier cleared');
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      widget.snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final preview = widget.preview;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Test mode switch
          _Card(
            child: _SwitchRow(
              label: 'Test Mode',
              subtitle: cfg.testMode
                  ? 'Active — forced crash multipliers are accepted'
                  : 'OFF — production rounds use normal crash distribution',
              value: cfg.testMode,
              activeColor: _kAmber,
              onChanged: _busy ? null : _toggleTestMode,
            ),
          ),
          const SizedBox(height: 16),

          // Preview banner
          _PreviewBanner(config: cfg, preview: preview),
          const SizedBox(height: 16),

          // Force next multiplier
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Force Next Crash Multiplier'),
                const SizedBox(height: 4),
                if (!cfg.testMode)
                  const _WarningChip(
                      'Enable test mode first to force a crash multiplier.')
                else ...[
                  // Quick-pick presets
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _kPresets
                        .map((p) => _PresetChip(
                              label: '${p.toStringAsFixed(2)}×',
                              onTap: _busy
                                  ? null
                                  : () => _multiplierCtrl.text =
                                      p.toStringAsFixed(2),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  // Manual input
                  TextFormField(
                    controller: _multiplierCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,]')),
                    ],
                    style: const TextStyle(color: _kTxt),
                    decoration: InputDecoration(
                      labelText: 'Crash multiplier (1.01 – 100.00)',
                      labelStyle: const TextStyle(color: _kMuted),
                      hintText: 'e.g. 2.50',
                      hintStyle: const TextStyle(color: _kMuted),
                      filled: true,
                      fillColor: _kBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      suffixText: '×',
                      suffixStyle: const TextStyle(color: _kAmber),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAmber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _busy ? null : _forceMultiplier,
                      icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                      label: const Text('Force Next Crash',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (preview.hasForced) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kRed,
                          side: const BorderSide(color: _kRed),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _busy ? null : _clearForced,
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        label: const Text('Clear Forced Multiplier'),
                      ),
                    ),
                  ],
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
// Preview banner
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.config, required this.preview});

  final RocketCrashGameConfig config;
  final RocketCrashForcedPreview preview;

  @override
  Widget build(BuildContext context) {
    final String msg;
    final Color accent;
    final IconData icon;

    if (!config.testMode) {
      msg = 'Production mode — rounds use normal crash distribution.';
      accent = _kBlue;
      icon = Icons.info_outline_rounded;
    } else if (!preview.hasForced) {
      msg = 'Test mode ON — next round uses normal distribution (no forced crash queued).';
      accent = _kAmber;
      icon = Icons.science_rounded;
    } else {
      msg = '🚀 Test mode ON — next round will crash at '
          '${preview.forcedMultiplier!.toStringAsFixed(2)}×';
      accent = _kGold;
      icon = Icons.flash_on_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: TextStyle(color: accent, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Void Round
// ─────────────────────────────────────────────────────────────────────────────

class _VoidRoundTab extends StatefulWidget {
  const _VoidRoundTab({
    required this.svc,
    required this.snack,
    required this.onDone,
  });

  final RocketCrashAdminService svc;
  final void Function(String, {bool isError}) snack;
  final VoidCallback onDone;

  @override
  State<_VoidRoundTab> createState() => _VoidRoundTabState();
}

class _VoidRoundTabState extends State<_VoidRoundTab> {
  final _roundCtrl = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _lastResult;

  @override
  void dispose() {
    _roundCtrl.dispose();
    super.dispose();
  }

  Future<void> _void() async {
    final id = _roundCtrl.text.trim();
    if (id.isEmpty) {
      widget.snack('Enter a round UUID', isError: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text('Void Round?',
            style: TextStyle(color: _kTxt)),
        content: Text(
          'This will refund all pending/running bets for round:\n$id\n\n'
          'This cannot be undone.',
          style: const TextStyle(color: _kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void & Refund',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final res = await widget.svc.voidRound(id);
      if (!mounted) return;
      setState(() => _lastResult = res);
      widget.snack(
          'Round voided. Refunded ${res['refund_total']} coins.');
      _roundCtrl.clear();
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      widget.snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Emergency Void Broken Round'),
                const SizedBox(height: 4),
                const Text(
                  'Refunds all pending/running bets and marks the round as voided. '
                  'Completed (crashed) rounds cannot be voided.',
                  style: TextStyle(color: _kMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _roundCtrl,
                  style: const TextStyle(
                      color: _kTxt, fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Round UUID',
                    labelStyle: const TextStyle(color: _kMuted),
                    hintText:
                        'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    hintStyle: const TextStyle(
                        color: _kMuted, fontSize: 12),
                    filled: true,
                    fillColor: _kBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _busy ? null : _void,
                    icon: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('Void Round & Refund Bets',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Void Result'),
                  const SizedBox(height: 8),
                  _KV('Round ID',
                      _lastResult!['round_id']?.toString() ?? '-'),
                  _KV('Refunded',
                      '${_lastResult!['refund_total']} coins'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3 — Audit Log
// ─────────────────────────────────────────────────────────────────────────────

class _AuditLogTab extends StatelessWidget {
  const _AuditLogTab(
      {required this.entries, required this.onRefresh});

  final List<RocketCrashAuditEntry> entries;
  final VoidCallback onRefresh;

  Color _dotColor(String action) {
    if (action.contains('test_mode_enabled')) return _kAmber;
    if (action.contains('test_mode_disabled')) return _kMuted;
    if (action.contains('forced_multiplier_set')) return _kGold;
    if (action.contains('forced_multiplier_cleared')) return _kBlue;
    if (action.contains('consumed')) return _kGreen;
    if (action.contains('voided')) return _kRed;
    return _kMuted;
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('No audit entries yet.',
            style: TextStyle(color: _kMuted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (context, index) =>
          const Divider(color: _kBorder, height: 1),
      itemBuilder: (_, i) {
        final e = entries[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5, right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dotColor(e.action),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.action,
                      style: const TextStyle(
                          color: _kTxt,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.createdAt.toLocal().toString().substring(0, 19),
                      style: const TextStyle(
                          color: _kMuted, fontSize: 11),
                    ),
                    if (e.metadata.isNotEmpty)
                      Text(
                        e.metadata.entries
                            .map((kv) => '${kv.key}: ${kv.value}')
                            .join(' · '),
                        style: const TextStyle(
                            color: _kMuted, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: child,
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: _kTxt, fontSize: 14, fontWeight: FontWeight.w700),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: _kTxt,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: _kMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
          ),
        ],
      );
}

class _WarningChip extends StatelessWidget {
  const _WarningChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _kAmber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: _kAmber, size: 15),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: _kAmber, fontSize: 12))),
          ],
        ),
      );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: _kAmber.withValues(alpha: 0.5)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: _kAmber,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      );
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.val);
  final String label;
  final String val;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(color: _kMuted, fontSize: 12)),
            Expanded(
              child: Text(val,
                  style: const TextStyle(
                      color: _kTxt,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}
