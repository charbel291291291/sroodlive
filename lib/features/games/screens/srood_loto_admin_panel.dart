import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/srood_loto_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (same palette as other admin panels)
// ─────────────────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0C0E14);
const _kSurface = Color(0xFF141720);
const _kBorder  = Color(0xFF1E2435);
const _kGold    = Color(0xFFF0C15A);
const _kGreen   = Color(0xFF22C55E);
const _kRed     = Color(0xFFEF4444);
const _kPurple  = Color(0xFF8B26D9);
const _kTxt     = Color(0xFFF1F5F9);
const _kMuted   = Color(0xFF64748B);

// ─────────────────────────────────────────────────────────────────────────────

class SroodLotoAdminPanel extends StatefulWidget {
  const SroodLotoAdminPanel({super.key});

  @override
  State<SroodLotoAdminPanel> createState() => _SroodLotoAdminPanelState();
}

class _SroodLotoAdminPanelState extends State<SroodLotoAdminPanel> {
  final _svc = const SroodLotoService();

  bool _loading  = true;
  String? _error;
  String? _toast;

  // Settings state
  bool _isEnabled           = true;
  int  _ticketPrice         = 20000;
  int  _match3              = 20000;
  int  _match4              = 100000;
  int  _match5              = 1000000;
  int  _match6              = 10000000;
  int  _drawIntervalMinutes = 60;
  bool _progressiveJackpot  = false;
  double _jackpotPct        = 20.0;

  // Current draw info
  Map<String, dynamic>? _currentDraw;

  // Controllers
  late TextEditingController _priceCtrl;
  late TextEditingController _m3Ctrl;
  late TextEditingController _m4Ctrl;
  late TextEditingController _m5Ctrl;
  late TextEditingController _m6Ctrl;
  late TextEditingController _intervalCtrl;
  late TextEditingController _jackpotPctCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _load();
  }

  void _initControllers() {
    _priceCtrl     = TextEditingController(text: _ticketPrice.toString());
    _m3Ctrl        = TextEditingController(text: _match3.toString());
    _m4Ctrl        = TextEditingController(text: _match4.toString());
    _m5Ctrl        = TextEditingController(text: _match5.toString());
    _m6Ctrl        = TextEditingController(text: _match6.toString());
    _intervalCtrl  = TextEditingController(text: _drawIntervalMinutes.toString());
    _jackpotPctCtrl= TextEditingController(text: _jackpotPct.toString());
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _m3Ctrl.dispose();
    _m4Ctrl.dispose();
    _m5Ctrl.dispose();
    _m6Ctrl.dispose();
    _intervalCtrl.dispose();
    _jackpotPctCtrl.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _svc.getCurrentDraw();
      if (!mounted) return;
      final s = data.settings;
      setState(() {
        _isEnabled            = s.isEnabled;
        _ticketPrice          = s.ticketPriceCoins;
        _match3               = s.match3Prize;
        _match4               = s.match4Prize;
        _match5               = s.match5Prize;
        _match6               = s.match6Prize;
        _progressiveJackpot   = s.progressiveJackpotEnabled;
        _jackpotPct           = s.jackpotPoolCoins.toDouble();
        _currentDraw          = data.draw != null ? {
          'id':             data.draw!.id,
          'draw_number':    data.draw!.drawNumber,
          'status':         data.draw!.status,
          'draw_at':        data.draw!.drawAt.toIso8601String(),
          'total_tickets':  data.draw!.totalTickets,
          'total_sales':    data.draw!.totalSalesCoins,
        } : null;
        _loading = false;
      });
      _priceCtrl.text    = _ticketPrice.toString();
      _m3Ctrl.text       = _match3.toString();
      _m4Ctrl.text       = _match4.toString();
      _m5Ctrl.text       = _match5.toString();
      _m6Ctrl.text       = _match6.toString();
      _intervalCtrl.text = _drawIntervalMinutes.toString();
      _jackpotPctCtrl.text = _jackpotPct.toString();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _saveSettings() async {
    try {
      await _svc.adminUpdateSettings(
        isEnabled:               _isEnabled,
        ticketPriceCoins:        int.tryParse(_priceCtrl.text) ?? _ticketPrice,
        match3Prize:             int.tryParse(_m3Ctrl.text) ?? _match3,
        match4Prize:             int.tryParse(_m4Ctrl.text) ?? _match4,
        match5Prize:             int.tryParse(_m5Ctrl.text) ?? _match5,
        match6Prize:             int.tryParse(_m6Ctrl.text) ?? _match6,
        drawIntervalMinutes:     int.tryParse(_intervalCtrl.text) ?? _drawIntervalMinutes,
        progressiveJackpotEnabled: _progressiveJackpot,
        jackpotContributionPct:  double.tryParse(_jackpotPctCtrl.text) ?? _jackpotPct,
      );
      _showToast('Settings saved ✓', isError: false);
      await _load();
    } catch (e) {
      _showToast('Error: $e', isError: true);
    }
  }

  Future<void> _forceSettle() async {
    final drawId = _currentDraw?['id'] as String?;
    if (drawId == null) return;
    final ok = await _confirm('Force settle draw #${_currentDraw!['draw_number']}?');
    if (!ok) return;
    try {
      await _svc.adminForceSettle(drawId);
      _showToast('Draw settled ✓', isError: false);
      await _load();
    } catch (e) {
      _showToast('Error: $e', isError: true);
    }
  }

  Future<void> _voidDraw() async {
    final drawId = _currentDraw?['id'] as String?;
    if (drawId == null) return;
    final ok = await _confirm(
        'Void draw #${_currentDraw!['draw_number']}? All tickets will be refunded.');
    if (!ok) return;
    try {
      await _svc.adminVoidDraw(drawId);
      _showToast('Draw voided & tickets refunded ✓', isError: false);
      await _load();
    } catch (e) {
      _showToast('Error: $e', isError: true);
    }
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _kSurface,
            title: const Text('Confirm', style: TextStyle(color: _kTxt)),
            content: Text(msg, style: const TextStyle(color: _kMuted)),
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
        ) ??
        false;
  }

  void _showToast(String msg, {required bool isError}) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kGold));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _kRed)),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: _kPurple),
                child: const Text('Retry')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildCurrentDrawCard(),
            const SizedBox(height: 16),
            _buildSettingsCard(),
            const SizedBox(height: 16),
            _buildPrizeTierCard(),
            const SizedBox(height: 16),
            _buildJackpotCard(),
            const SizedBox(height: 16),
            _buildEmergencyCard(),
            const SizedBox(height: 32),
          ],
        ),
        if (_toast != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Text(_toast!,
                  style: const TextStyle(color: _kTxt),
                  textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  // ── Status card ───────────────────────────────────────────────────────────

  Widget _buildStatusCard() => _AdminCard(
        title: 'Game Status',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isEnabled ? _kGreen : _kRed,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isEnabled ? 'Enabled' : 'Disabled',
                  style: TextStyle(
                      color: _isEnabled ? _kGreen : _kRed,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Switch(
              value: _isEnabled,
              onChanged: (v) {
                setState(() => _isEnabled = v);
              },
              activeColor: _kGold,
            ),
          ],
        ),
      );

  // ── Current draw card ─────────────────────────────────────────────────────

  Widget _buildCurrentDrawCard() {
    final d = _currentDraw;
    if (d == null) {
      return _AdminCard(
        title: 'Current Draw',
        child: const Text('No active draw', style: TextStyle(color: _kMuted)),
      );
    }
    final drawAt = DateTime.tryParse(d['draw_at'] as String? ?? '');
    return _AdminCard(
      title: 'Current Draw',
      child: Column(
        children: [
          _kv('Draw #', '#${d['draw_number']}'),
          _kv('Status', d['status'] as String? ?? '—'),
          _kv('Draw at', drawAt != null ? _fmtTime(drawAt) : '—'),
          _kv('Tickets sold', '${d['total_tickets']}'),
          _kv('Sales', '${_fmtCoins((d['total_sales'] as num?)?.toInt() ?? 0)} coins'),
        ],
      ),
    );
  }

  // ── Settings card ─────────────────────────────────────────────────────────

  Widget _buildSettingsCard() => _AdminCard(
        title: 'Draw Settings',
        child: Column(
          children: [
            _field('Ticket Price (coins)', _priceCtrl),
            const SizedBox(height: 10),
            _field('Draw Interval (minutes)', _intervalCtrl),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saveSettings,
                style: FilledButton.styleFrom(backgroundColor: _kPurple),
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      );

  // ── Prize tier card ───────────────────────────────────────────────────────

  Widget _buildPrizeTierCard() => _AdminCard(
        title: 'Prize Tiers',
        child: Column(
          children: [
            _field('Match 3 – Prize (coins)', _m3Ctrl),
            const SizedBox(height: 10),
            _field('Match 4 – Prize (coins)', _m4Ctrl),
            const SizedBox(height: 10),
            _field('Match 5 – Prize (coins)', _m5Ctrl),
            const SizedBox(height: 10),
            _field('Match 6 / Jackpot (coins, fixed)', _m6Ctrl),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saveSettings,
                style: FilledButton.styleFrom(backgroundColor: _kPurple),
                child: const Text('Save Prize Tiers'),
              ),
            ),
          ],
        ),
      );

  // ── Jackpot card ──────────────────────────────────────────────────────────

  Widget _buildJackpotCard() => _AdminCard(
        title: 'Progressive Jackpot',
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Enable progressive jackpot',
                    style: TextStyle(color: _kTxt, fontSize: 13)),
                Switch(
                  value: _progressiveJackpot,
                  onChanged: (v) => setState(() => _progressiveJackpot = v),
                  activeColor: _kGold,
                ),
              ],
            ),
            if (_progressiveJackpot) ...[
              const SizedBox(height: 10),
              _field('Contribution % per ticket', _jackpotPctCtrl),
              const SizedBox(height: 8),
              const Text(
                'When progressive jackpot is enabled, a % of each ticket price accumulates in the jackpot pool. The match-6 fixed prize is ignored.',
                style: TextStyle(color: _kMuted, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saveSettings,
                  style: FilledButton.styleFrom(backgroundColor: _kPurple),
                  child: const Text('Save Jackpot Settings'),
                ),
              ),
            ],
          ],
        ),
      );

  // ── Emergency card ────────────────────────────────────────────────────────

  Widget _buildEmergencyCard() => _AdminCard(
        title: '⚠ Emergency Controls',
        child: Column(
          children: [
            const Text(
              'These actions are irreversible. Force-settle immediately draws the current draw. Void refunds all ticket holders.',
              style: TextStyle(color: _kMuted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _currentDraw != null ? _forceSettle : null,
                    icon: const Icon(Icons.flash_on_rounded, color: _kGold, size: 16),
                    label: const Text('Force Settle',
                        style: TextStyle(color: _kGold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kGold),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _currentDraw != null ? _voidDraw : null,
                    icon: const Icon(Icons.cancel_rounded, color: _kRed, size: 16),
                    label: const Text('Void Draw',
                        style: TextStyle(color: _kRed, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kRed),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: _kMuted, fontSize: 12)),
            Text(v,
                style: const TextStyle(
                    color: _kTxt, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _field(String label, TextEditingController ctrl) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: _kMuted, fontSize: 11)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: _kTxt, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: _kBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kGold),
              ),
            ),
          ),
        ],
      );

  String _fmtCoins(int c) {
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M';
    if (c >= 1000)    return '${(c / 1000).toStringAsFixed(0)}K';
    return c.toString();
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} '
        '(${local.day}/${local.month})';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared admin card widget
// ─────────────────────────────────────────────────────────────────────────────

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              title,
              style: const TextStyle(
                  color: _kGold, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(color: _kBorder, height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}
