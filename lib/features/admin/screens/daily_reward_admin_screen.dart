import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../../daily_reward/daily_reward_service.dart';

/// Admin control for the Daily Reward system. Reads via get_daily_reward_state
/// and writes via the super-admin-gated RPCs (admin_set_daily_reward_config /
/// admin_upsert_daily_reward_rule). Only 'coins' rewards are supported for now.
class DailyRewardAdminScreen extends StatefulWidget {
  const DailyRewardAdminScreen({super.key});

  @override
  State<DailyRewardAdminScreen> createState() => _DailyRewardAdminScreenState();
}

class _DailyRewardAdminScreenState extends State<DailyRewardAdminScreen> {
  static const _gold = Color(0xFFF0C15A);
  final _service = const DailyRewardService();

  bool _loading = true;
  String? _error;
  bool _enabled = true;
  bool _popupEnabled = true;
  bool _savingConfig = false;

  final Map<int, TextEditingController> _titleCtl = {};
  final Map<int, TextEditingController> _amountCtl = {};
  final Map<int, bool> _dayEnabled = {};
  final Map<int, bool> _savingDay = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _titleCtl.values) {
      c.dispose();
    }
    for (final c in _amountCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _service.getState();
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled;
        _popupEnabled = s.popupEnabled;
        for (var d = 1; d <= 7; d++) {
          final r = s.ruleForDay(d);
          _titleCtl[d] = TextEditingController(text: r?.title ?? 'Day $d');
          _amountCtl[d] =
              TextEditingController(text: (r?.amount ?? 0).toString());
          _dayEnabled[d] = r?.enabled ?? true;
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
    setState(() => _savingConfig = true);
    try {
      await _service.adminSetConfig(enabled: _enabled, popupEnabled: _popupEnabled);
      _snack('Config saved');
    } catch (e) {
      _snack('Save failed: ${_friendly(e)}', error: true);
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  Future<void> _saveDay(int day) async {
    setState(() => _savingDay[day] = true);
    try {
      final amount = int.tryParse(_amountCtl[day]!.text.trim()) ?? 0;
      await _service.adminUpsertRule(
        dayNumber: day,
        enabled: _dayEnabled[day] ?? true,
        rewardType: 'coins',
        title: _titleCtl[day]!.text.trim().isEmpty
            ? 'Day $day'
            : _titleCtl[day]!.text.trim(),
        amount: amount,
      );
      _snack('Day $day saved');
    } catch (e) {
      _snack('Day $day failed: ${_friendly(e)}', error: true);
    } finally {
      if (mounted) setState(() => _savingDay[day] = false);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('not_authorized')) return 'Not authorized (super admin only)';
    if (s.contains('unsupported_reward_type')) return 'Only coins supported';
    if (s.contains('invalid_amount')) return 'Invalid amount';
    return 'Error';
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    SroodToast.show(context, m, type: error ? SroodToastType.error : SroodToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E16),
        foregroundColor: Colors.white,
        title: const Text('Daily Reward'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: Colors.white70)),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: _enabled,
                            activeThumbColor: _gold,
                            title: const Text('System enabled',
                                style: TextStyle(color: Colors.white)),
                            onChanged: (v) => setState(() => _enabled = v),
                          ),
                          SwitchListTile(
                            value: _popupEnabled,
                            activeThumbColor: _gold,
                            title: const Text('Auto popup on home',
                                style: TextStyle(color: Colors.white)),
                            onChanged: (v) => setState(() => _popupEnabled = v),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _savingConfig ? null : _saveConfig,
                              child: Text(_savingConfig ? 'Saving…' : 'Save config',
                                  style: const TextStyle(color: _gold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var d = 1; d <= 7; d++) _dayCard(d),
                  ],
                ),
    );
  }

  Widget _dayCard(int day) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Day $day',
                  style: const TextStyle(
                      color: _gold, fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              Switch(
                value: _dayEnabled[day] ?? true,
                activeThumbColor: _gold,
                onChanged: (v) => setState(() => _dayEnabled[day] = v),
              ),
            ],
          ),
          TextField(
            controller: _titleCtl[day],
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Title',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtl[day],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Coins amount',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Reward type: coins',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: (_savingDay[day] ?? false) ? null : () => _saveDay(day),
              child: Text((_savingDay[day] ?? false) ? 'Saving…' : 'Save Day $day',
                  style: const TextStyle(color: _gold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF141720),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2435)),
        ),
        child: child,
      );
}
