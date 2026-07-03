import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/srood_loto_models.dart';
import '../services/srood_loto_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import 'package:srood_live/shared/widgets/coin_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

const _kBg      = Color(0xFF080510);
const _kSurface = Color(0xFF110D25);
const _kCard    = Color(0xFF160F2E);
const _kBorder  = Color(0xFF2A1E50);
const _kPurple  = Color(0xFF8B26D9);
const _kGold    = Color(0xFFF0C15A);
const _kGoldDim = Color(0xFFB8932A);
const _kGreen   = Color(0xFF22C55E);
const _kRed     = Color(0xFFEF4444);
const _kTxt     = Color(0xFFF1F5F9);
const _kMuted   = Color(0xFF64748B);
const _kPink    = Color(0xFFE040FB);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SroodLotoScreen extends StatefulWidget {
  const SroodLotoScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<SroodLotoScreen> createState() => _SroodLotoScreenState();
}

class _SroodLotoScreenState extends State<SroodLotoScreen>
    with TickerProviderStateMixin {
  final _svc = const SroodLotoService();

  // State
  bool _loading = true;
  String? _error;
  LotoCurrentDraw? _data;
  List<LotoRecentDraw> _recent = [];

  // Ticket selection
  final Set<int> _selected = {};

  // Countdown
  Timer? _ticker;
  int _secsUntilDraw  = 0;
  int _secsUntilClose = 0;

  // Animations
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  late AnimationController _celebCtrl;

  // Buy state
  bool _buying = false;
  String? _buyError;
  Map<String, dynamic>? _lastBuyResult;

  bool get _isArabic => context.isArabic;
  String _t(String ar, String en) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _celebCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..addStatusListener((status) {
        // Once the success banner has fully faded out, drop it from the tree
        // instead of leaving an invisible box holding layout space.
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _lastBuyResult = null);
        }
      });

    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _glowCtrl.dispose();
    _celebCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _svc.getCurrentDraw(),
        _svc.getRecentDraws(),
      ]);
      if (!mounted) return;
      final data   = results[0] as LotoCurrentDraw;
      final recent = results[1] as List<LotoRecentDraw>;
      setState(() {
        _data              = data;
        _recent            = recent;
        _secsUntilDraw     = data.secondsUntilDraw;
        _secsUntilClose    = data.secondsUntilClose;
        _loading           = false;
      });
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startCountdown() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final wasCountingDown = _secsUntilDraw > 0;
      setState(() {
        if (_secsUntilDraw  > 0) _secsUntilDraw--;
        if (_secsUntilClose > 0) _secsUntilClose--;
      });
      // Reload only when the countdown actually crosses zero. If the server
      // already reported 0 (no upcoming draw yet), keep ticking quietly
      // instead of re-fetching in a loop every few seconds.
      if (wasCountingDown && _secsUntilDraw == 0) {
        _ticker?.cancel();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _load(silent: true);
        });
      }
    });
  }

  // ── Ticket actions ────────────────────────────────────────────────────────

  void _toggleNumber(int n) {
    final settings = _data?.settings;
    if (settings == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(n)) {
        _selected.remove(n);
      } else if (_selected.length < settings.numbersPerTicket) {
        _selected.add(n);
      }
    });
  }

  void _quickPick() {
    final settings = _data?.settings;
    if (settings == null) return;
    HapticFeedback.mediumImpact();
    final rng  = math.Random();
    final pool = List.generate(
        settings.numberMax - settings.numberMin + 1,
        (i) => settings.numberMin + i)
      ..shuffle(rng);
    setState(() {
      _selected
        ..clear()
        ..addAll(pool.take(settings.numbersPerTicket));
    });
  }

  void _clearSelection() {
    HapticFeedback.lightImpact();
    setState(() => _selected.clear());
  }

  Future<void> _buyTicket() async {
    final settings = _data?.settings;
    if (settings == null) return;
    if (_selected.length != settings.numbersPerTicket) {
      setState(() => _buyError = _t(
        'اختر ${settings.numbersPerTicket} أرقام أولاً',
        'Select ${settings.numbersPerTicket} numbers first',
      ));
      return;
    }
    if (_data!.userBalance < settings.ticketPriceCoins) {
      setState(() => _buyError = _t('رصيدك غير كافٍ', 'Insufficient balance'));
      return;
    }
    if (_secsUntilClose <= 0) {
      setState(() => _buyError = _t('انتهى وقت شراء التذاكر', 'Ticket sales are closed'));
      return;
    }

    setState(() { _buying = true; _buyError = null; });
    try {
      final result = await _svc.buyTicket(_selected.toList()..sort());
      if (!mounted) return;
      setState(() {
        _lastBuyResult = result;
        _buying = false;
        _selected.clear();
      });
      _celebCtrl.forward(from: 0);
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _buyError = _parseError(msg);
        _buying   = false;
      });
    }
  }

  String _parseError(String raw) {
    if (raw.contains('insufficient_balance')) {
      return _t('رصيدك غير كافٍ', 'Insufficient balance');
    }
    if (raw.contains('draw_closed')) {
      return _t('انتهى وقت الشراء', 'Draw is closed');
    }
    if (raw.contains('game_disabled')) {
      return _t('اللعبة موقوفة حالياً', 'Game is currently disabled');
    }
    if (raw.contains('duplicate_number')) {
      return _t('لا يمكن تكرار الأرقام', 'Duplicate numbers are not allowed');
    }
    if (raw.contains('invalid_count')) {
      return _t('عدد الأرقام غير صحيح', 'Invalid number count');
    }
    return _t('حدث خطأ، حاول مجدداً', 'An error occurred. Please try again.');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // Unified coin formatting (shared formatCoinAmount) for cross-game
  // consistency. Thin alias to keep call sites unchanged.
  String _formatCoins(int coins) => formatCoinAmount(coins);

  String _formatCountdown(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Directionality(
        textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kGold))
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _kRed, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: _kTxt), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: _kPurple),
              child: Text(_t('إعادة المحاولة', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final data     = _data!;
    final settings = data.settings;

    if (!settings.isEnabled) {
      return _buildDisabled();
    }

    return CustomScrollView(
      slivers: [
        _buildAppBar(data, settings),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              _buildResponsibleNotice(settings),
              const SizedBox(height: 16),
              _buildJackpotCard(settings),
              const SizedBox(height: 16),
              _buildCountdownCard(data),
              const SizedBox(height: 16),
              _buildPrizeTable(settings),
              const SizedBox(height: 20),
              _buildNumberPicker(settings),
              const SizedBox(height: 16),
              _buildSelectedRow(settings),
              const SizedBox(height: 16),
              _buildActionButtons(data, settings),
              if (_buyError != null) ...[
                const SizedBox(height: 10),
                _buildErrorBanner(_buyError!),
              ],
              if (_lastBuyResult != null) ...[
                const SizedBox(height: 10),
                _buildSuccessBanner(_lastBuyResult!),
              ],
              const SizedBox(height: 24),
              _buildMyTickets(data),
              const SizedBox(height: 24),
              _buildRecentDraws(),
            ]),
          ),
        ),
      ],
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(LotoCurrentDraw data, LotoSettings settings) {
    return SliverAppBar(
      backgroundColor: _kBg,
      expandedHeight: 140,
      pinned: true,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A0640),
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _kTxt, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A0640), _kBg],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon with pulse glow
                  AnimatedBuilder(
                    animation: _glowAnim,
                    builder: (_, _) => Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFF5A0FA0), _kPurple],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _kPurple.withValues(
                                alpha: _glowAnim.value * 0.65),
                            blurRadius: 22,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.emoji_events_rounded,
                          color: _kGold, size: 28),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Title block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _t('سحب سرود', 'Srood Draw'),
                          style: const TextStyle(
                            color: _kGold,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _t('سحب الجوائز · كل ساعة', 'Lucky Reward Draw · Hourly'),
                          style: const TextStyle(
                              color: _kMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // Balance pill + refresh
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A0640),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _kGold.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppCoinIcon(size: 13),
                            const SizedBox(width: 4),
                            Text(
                              _formatCoins(data.userBalance),
                              style: const TextStyle(
                                color: _kGold,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _load(silent: false),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                color: _kMuted, size: 13),
                            const SizedBox(width: 3),
                            Text(
                              _t('تحديث', 'Refresh'),
                              style: const TextStyle(
                                  color: _kMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        title: Text(
          _t('سحب سرود', 'Srood Draw'),
          style: const TextStyle(
              color: _kGold, fontWeight: FontWeight.w900, fontSize: 17),
        ),
        collapseMode: CollapseMode.parallax,
      ),
    );
  }

  // ── Responsible play notice ───────────────────────────────────────────────

  Widget _buildResponsibleNotice(LotoSettings settings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1005),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: _kGold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isArabic ? settings.responsibleNoticeAr : settings.responsibleNoticeEn,
              style: const TextStyle(color: _kGold, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Jackpot card ──────────────────────────────────────────────────────────

  Widget _buildJackpotCard(LotoSettings settings) {
    final jackpot = settings.progressiveJackpotEnabled
        ? settings.jackpotPoolCoins
        : settings.match6Prize;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, _) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF3D1C02), Color(0xFF7B3F00), Color(0xFF1A0D00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _kGold.withValues(alpha: _glowAnim.value * 0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: _kGold.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              _t('الجائزة الكبرى 🏆', '🏆 Jackpot Prize'),
              style: const TextStyle(
                  color: _kGold, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatCoins(jackpot)} ${_t('عملة', 'Coins')}',
              style: const TextStyle(
                color: _kGold,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            if (settings.progressiveJackpotEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _t('يتزايد مع كل تذكرة', 'Grows with every ticket'),
                  style: const TextStyle(color: _kGoldDim, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Countdown card ────────────────────────────────────────────────────────

  Widget _buildCountdownCard(LotoCurrentDraw data) {
    final drawOk  = data.draw != null;
    final closed  = _secsUntilClose <= 0;
    final borderC = closed ? _kRed : _kPurple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderC.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_rounded, color: borderC, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  drawOk
                      ? _t('السحب القادم', 'Next Draw')
                      : _t('انتظار السحب التالي...', 'Waiting for next draw...'),
                  style: const TextStyle(color: _kMuted, fontSize: 12),
                ),
                if (drawOk) ...[
                  Text(
                    _formatCountdown(_secsUntilDraw),
                    style: TextStyle(
                      color: _kTxt,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    closed
                        ? _t('🔒 أغلق شراء التذاكر', '🔒 Ticket sales closed')
                        : _t('متبقي ${_formatCountdown(_secsUntilClose)} لإغلاق الشراء',
                            'Sales close in ${_formatCountdown(_secsUntilClose)}'),
                    style: TextStyle(color: closed ? _kRed : _kMuted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (drawOk)
            Text(
              '#${data.draw!.drawNumber}',
              style: const TextStyle(
                  color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  // ── Prize table ───────────────────────────────────────────────────────────

  Widget _buildPrizeTable(LotoSettings settings) {
    final rows = [
      (match: 3, icon: '🎫', prize: settings.match3Prize, label: _t('استرداد التذكرة', 'Ticket refund')),
      (match: 4, icon: '🥉', prize: settings.match4Prize, label: _t('جائزة متوسطة', 'Medium prize')),
      (match: 5, icon: '🥈', prize: settings.match5Prize, label: _t('جائزة كبيرة', 'High prize')),
      (match: 6, icon: '🏆', prize: settings.progressiveJackpotEnabled ? settings.jackpotPoolCoins : settings.match6Prize, label: _t('الجائزة الكبرى', 'Jackpot')),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: _kGold, size: 18),
                const SizedBox(width: 8),
                Text(_t('جدول الجوائز', 'Prize Table'),
                    style: const TextStyle(
                        color: _kTxt, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Divider(color: _kBorder, height: 1),
          ...rows.map((r) {
            final isJackpot = r.match == 6;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: _kBorder.withValues(alpha: 0.5))),
                gradient: isJackpot
                    ? LinearGradient(colors: [
                        _kGold.withValues(alpha: 0.06),
                        Colors.transparent,
                      ])
                    : null,
              ),
              child: Row(
                children: [
                  Text(r.icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Text(
                    _t('تطابق ${r.match}', 'Match ${r.match}'),
                    style: TextStyle(
                      color: isJackpot ? _kGold : _kTxt,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(r.label,
                      style: const TextStyle(color: _kMuted, fontSize: 11)),
                  const Spacer(),
                  Row(
                    children: [
                      const AppCoinIcon(size: 13),
                      const SizedBox(width: 3),
                      Text(
                        _formatCoins(r.prize),
                        style: TextStyle(
                          color: isJackpot ? _kGold : _kTxt,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Number picker ─────────────────────────────────────────────────────────

  Widget _buildNumberPicker(LotoSettings settings) {
    final count  = settings.numberMax - settings.numberMin + 1;
    final needed = settings.numbersPerTicket;
    final full   = _selected.length >= needed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _t('اختر أرقامك', 'Pick your numbers'),
              style: const TextStyle(
                  color: _kTxt, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              '${_selected.length}/$needed',
              style: TextStyle(
                color: full ? _kGold : _kMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: count,
          itemBuilder: (_, i) {
            final n    = settings.numberMin + i;
            final sel  = _selected.contains(n);
            final dism = !sel && full;
            return GestureDetector(
              onTap: dism ? null : () => _toggleNumber(n),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: sel
                      ? _kGold
                      : dism
                          ? _kSurface.withValues(alpha: 0.4)
                          : _kSurface,
                  border: Border.all(
                    color: sel
                        ? _kGold
                        : dism
                            ? _kBorder.withValues(alpha: 0.3)
                            : _kBorder,
                    width: sel ? 2 : 1,
                  ),
                  boxShadow: sel
                      ? [BoxShadow(color: _kGold.withValues(alpha: 0.5), blurRadius: 10)]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: sel
                          ? Colors.black
                          : dism
                              ? _kMuted.withValues(alpha: 0.4)
                              : _kTxt,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Selected numbers row ──────────────────────────────────────────────────

  Widget _buildSelectedRow(LotoSettings settings) {
    final sorted = _selected.toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _selected.length == settings.numbersPerTicket
              ? _kGold.withValues(alpha: 0.6)
              : _kBorder,
        ),
      ),
      child: Row(
        children: [
          ...List.generate(settings.numbersPerTicket, (i) {
            final hasNum = i < sorted.length;
            final n = hasNum ? sorted[i] : null;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasNum ? _kGold : _kSurface,
                  border: Border.all(
                    color: hasNum ? _kGold : _kBorder,
                  ),
                ),
                child: Center(
                  child: Text(
                    n != null ? '$n' : '—',
                    style: TextStyle(
                      color: hasNum ? Colors.black : _kMuted,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons(LotoCurrentDraw data, LotoSettings settings) {
    final drawOpen    = data.draw != null && _secsUntilClose > 0;
    final canBuy      = drawOpen && _selected.length == settings.numbersPerTicket;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _quickPick,
                icon: const Icon(Icons.bolt_rounded, color: _kPink, size: 18),
                label: Text(_t('سريع', 'Quick Pick'),
                    style: const TextStyle(color: _kPink)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kPink, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selected.isEmpty ? null : _clearSelection,
                icon: const Icon(Icons.clear_all_rounded, color: _kMuted, size: 18),
                label: Text(_t('مسح', 'Clear'),
                    style: const TextStyle(color: _kMuted)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kBorder, width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, _) => FilledButton(
              onPressed: (canBuy && !_buying) ? _buyTicket : null,
              style: FilledButton.styleFrom(
                backgroundColor: canBuy ? _kPurple : _kBorder,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ).copyWith(
                overlayColor: WidgetStatePropertyAll(
                    _kGold.withValues(alpha: 0.1)),
              ),
              child: _buying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.confirmation_number_rounded,
                            color: _kGold, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _t(
                            'شراء تذكرة — ${_formatCoins(settings.ticketPriceCoins)} عملة',
                            'Buy Ticket — ${_formatCoins(settings.ticketPriceCoins)} Coins',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (!drawOpen && data.draw != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _t('🔒 انتهى وقت الشراء لهذا السحب', '🔒 Ticket sales are closed for this draw'),
              style: const TextStyle(color: _kRed, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildErrorBanner(String msg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kRed.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: _kRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(color: _kRed, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _buildSuccessBanner(Map<String, dynamic> result) {
    final nums = (result['numbers'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [];
    return AnimatedBuilder(
      animation: _celebCtrl,
      builder: (_, _) => Opacity(
        opacity: (1 - _celebCtrl.value).clamp(0.0, 1.0),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGreen.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: _kGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _t('تم شراء التذكرة! 🎉', 'Ticket purchased! 🎉'),
                    style: const TextStyle(
                        color: _kGreen, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: nums.map((n) => Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kGold,
                  ),
                  child: Center(
                    child: Text('$n',
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 12)),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── My Tickets ────────────────────────────────────────────────────────────

  Widget _buildMyTickets(LotoCurrentDraw data) {
    if (data.myTickets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('تذاكري لهذا السحب', 'My Tickets – This Draw'),
          style: const TextStyle(
              color: _kTxt, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...data.myTickets.map((t) => _TicketCard(
              ticket: t,
              isArabic: _isArabic,
              formatCoins: _formatCoins,
            )),
      ],
    );
  }

  // ── Recent Draws ──────────────────────────────────────────────────────────

  Widget _buildRecentDraws() {
    if (_recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('السحوبات الأخيرة', 'Recent Draws'),
          style: const TextStyle(
              color: _kTxt, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ..._recent.map((d) => _DrawResultCard(
              draw: d,
              isArabic: _isArabic,
              formatCoins: _formatCoins,
            )),
      ],
    );
  }

  // ── Disabled state ────────────────────────────────────────────────────────

  Widget _buildDisabled() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kSurface,
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.grain_rounded, color: _kMuted, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              _t('سحب سرود', 'Srood Draw'),
              style: const TextStyle(
                  color: _kGold, fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _t('اللعبة موقوفة مؤقتاً من المشرفين.',
                  'This game is temporarily disabled by administrators.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kMuted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kBorder)),
              child: Text(_t('عودة', 'Go Back'),
                  style: const TextStyle(color: _kMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ticket card widget
// ─────────────────────────────────────────────────────────────────────────────

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.isArabic,
    required this.formatCoins,
  });

  final LotoTicket ticket;
  final bool isArabic;
  final String Function(int) formatCoins;

  String _t(String ar, String en) => isArabic ? ar : en;

  Color get _statusColor {
    switch (ticket.status) {
      case 'won':      return _kGold;
      case 'lost':     return _kMuted;
      case 'refunded': return _kGreen;
      case 'voided':   return _kRed;
      default:         return _kPurple;
    }
  }

  String get _statusLabel {
    switch (ticket.status) {
      case 'won':      return _t('فائز 🏆', '🏆 Winner');
      case 'lost':     return _t('لم تفز', 'Not won');
      case 'refunded': return _t('مُسترد', 'Refunded');
      case 'voided':   return _t('ملغى', 'Voided');
      default:         return _t('انتظار السحب', 'Awaiting draw');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWon = ticket.status == 'won';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWon
              ? _kGold.withValues(alpha: 0.6)
              : _kBorder.withValues(alpha: 0.7),
        ),
        boxShadow: isWon
            ? [BoxShadow(color: _kGold.withValues(alpha: 0.18), blurRadius: 14)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _statusLabel,
                style: TextStyle(
                    color: _statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
              if (isWon)
                Row(
                  children: [
                    const AppCoinIcon(size: 14),
                    const SizedBox(width: 3),
                    Text(
                      '+${formatCoins(ticket.prizeCoins)}',
                      style: const TextStyle(
                          color: _kGold, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ],
                ),
              if (ticket.status == 'active')
                Text(
                  '#${ticket.id.substring(0, 6)}',
                  style: const TextStyle(color: _kMuted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: ticket.numbers.map((n) {
              final matched = ticket.winningNumbers?.contains(n) ?? false;
              return Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: matched ? _kGold : _kSurface,
                  border: Border.all(
                    color: matched ? _kGold : _kBorder,
                    width: matched ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: matched ? Colors.black : _kTxt,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (ticket.status != 'active' && ticket.matchedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _t('تطابق ${ticket.matchedCount} أرقام', '${ticket.matchedCount} numbers matched'),
                style: TextStyle(
                    color: _statusColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Draw result card widget
// ─────────────────────────────────────────────────────────────────────────────

class _DrawResultCard extends StatelessWidget {
  const _DrawResultCard({
    required this.draw,
    required this.isArabic,
    required this.formatCoins,
  });

  final LotoRecentDraw draw;
  final bool isArabic;
  final String Function(int) formatCoins;

  String _t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    final hasMyTicket = draw.myTicket != null;
    final iWon        = hasMyTicket && draw.myTicket!.isWon;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iWon ? _kGold.withValues(alpha: 0.5) : _kBorder.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t('سحب #${draw.drawNumber}', 'Draw #${draw.drawNumber}'),
                style: const TextStyle(
                    color: _kTxt, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Text(
                '${draw.totalTickets} ${_t('تذكرة', 'tickets')}',
                style: const TextStyle(color: _kMuted, fontSize: 11),
              ),
            ],
          ),
          if (draw.winningNumbers != null) ...[
            const SizedBox(height: 10),
            Text(_t('الأرقام الفائزة:', 'Winning numbers:'),
                style: const TextStyle(color: _kMuted, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: draw.winningNumbers!.map((n) {
                final myMatch = draw.myTicket?.numbers.contains(n) ?? false;
                return Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: myMatch ? _kGold : _kSurface,
                    border: Border.all(
                      color: myMatch ? _kGold : _kBorder,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$n',
                      style: TextStyle(
                        color: myMatch ? Colors.black : _kTxt,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (hasMyTicket) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: iWon
                    ? _kGold.withValues(alpha: 0.1)
                    : _kSurface.withValues(alpha: 0.5),
                border: Border.all(
                  color: iWon ? _kGold.withValues(alpha: 0.4) : _kBorder.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    iWon ? '🏆' : '🎫',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      iWon
                          ? _t(
                              'فزت بـ ${formatCoins(draw.myTicket!.prizeCoins)} عملة',
                              'You won ${formatCoins(draw.myTicket!.prizeCoins)} coins')
                          : _t(
                              'تطابق ${draw.myTicket!.matchedCount} أرقام',
                              '${draw.myTicket!.matchedCount} numbers matched'),
                      style: TextStyle(
                          color: iWon ? _kGold : _kMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
