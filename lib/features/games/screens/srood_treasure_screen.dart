import 'package:flutter/material.dart';

import '../models/srood_treasure_models.dart';
import '../services/srood_treasure_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

// ── Design tokens (matches app palette) ──────────────────────────────────────
const _kBg      = Color(0xFF080510);
const _kSurface = Color(0xFF110D25);
const _kCard    = Color(0xFF160F2E);
const _kBorder  = Color(0xFF2A1E50);
const _kPurple  = Color(0xFF8B26D9);
const _kGold    = Color(0xFFF0C15A);
const _kGreen   = Color(0xFF22C55E);
const _kRed     = Color(0xFFEF4444);
const _kBlue    = Color(0xFF4FC3F7);
const _kAmber   = Color(0xFFFF9800);

// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { loading, idle, selecting, playing, dealOffered, completed, error }

class SroodTreasureScreen extends StatefulWidget {
  const SroodTreasureScreen({super.key, required this.isArabic});

  final bool isArabic;

  @override
  State<SroodTreasureScreen> createState() => _SroodTreasureScreenState();
}

class _SroodTreasureScreenState extends State<SroodTreasureScreen>
    with SingleTickerProviderStateMixin {
  static const _service = SroodTreasureService();

  _Phase _phase = _Phase.loading;
  TreasureGame? _game;
  int _userBalance = 0;
  TreasureSettings _settings = TreasureSettings.defaults;
  bool _actionLoading = false;
  int? _openingBox;

  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  bool get _isArabic => context.isArabic;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _load();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  // ── data ───────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _phase = _Phase.loading;
      });
    }
    try {
      final state = await _service.getCurrentGame();
      if (!mounted) return;
      setState(() {
        _userBalance = state.userBalance;
        _settings    = state.settings;
        _game        = state.currentGame;
        _phase       = _phaseFrom(_game?.status);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
      });
    }
  }

  _Phase _phaseFrom(String? status) => switch (status) {
    'selecting'    => _Phase.selecting,
    'playing'      => _Phase.playing,
    'deal_offered' => _Phase.dealOffered,
    'completed'    => _Phase.completed,
    _              => _Phase.idle,
  };

  // ── actions ────────────────────────────────────────────────────────────────

  Future<void> _startGame() async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await _service.startGame();
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('active_game_exists')) {
        await _load(silent: true);
        return;
      }
      _showSnack(_localizeError(msg));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _selectBox(int boxNumber) async {
    if (_actionLoading || _game == null) return;
    setState(() => _actionLoading = true);
    try {
      await _service.selectPersonalBox(_game!.id, boxNumber);
      await _load(silent: true);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _openBox(int boxNumber) async {
    if (_openingBox != null || _actionLoading || _game == null) return;
    setState(() => _openingBox = boxNumber);
    try {
      await _service.openBox(_game!.id, boxNumber);
      await _load(silent: true);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _openingBox = null);
    }
  }

  Future<void> _acceptOffer() async {
    if (_actionLoading || _game == null) return;
    setState(() => _actionLoading = true);
    try {
      await _service.acceptOffer(_game!.id);
      await _load(silent: true);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _continueGame() async {
    if (_actionLoading || _game == null) return;
    setState(() => _actionLoading = true);
    try {
      await _service.continueGame(_game!.id);
      await _load(silent: true);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _takeBox() async {
    if (_actionLoading || _game == null) return;
    setState(() => _actionLoading = true);
    try {
      await _service.takeBox(_game!.id);
      await _load(silent: true);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _confirmAbandon() async {
    if (_game == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _isArabic ? 'تخلَّ عن اللعبة' : 'Abandon Game',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          _isArabic
              ? 'ستخسر رسوم الدخول (${_fmt(_game!.entryFeeCoins)} عملة). هل أنت متأكد؟'
              : 'You will forfeit the entry fee (${_fmt(_game!.entryFeeCoins)} coins). Continue?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isArabic ? 'إلغاء' : 'Cancel',
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_isArabic ? 'تخلَّ' : 'Abandon',
                style: const TextStyle(color: _kRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await _service.abandonGame(_game!.id);
      await _load(silent: true);
    } catch (e) {
      if (mounted) _showSnack(_localizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    SroodToast.show(context, msg, type: SroodToastType.error);
  }

  String _localizeError(String msg) {
    if (msg.contains('insufficient_balance')) {
      return _isArabic ? 'رصيدك غير كافٍ' : 'Insufficient balance';
    }
    if (msg.contains('game_disabled')) {
      return _isArabic ? 'اللعبة متوقفة مؤقتاً' : 'Game temporarily disabled';
    }
    if (msg.contains('box_already_opened')) {
      return _isArabic ? 'هذا الصندوق مفتوح بالفعل' : 'Box already opened';
    }
    return msg;
  }

  static String _fmt(int coins) {
    if (coins >= 1000000) {
      final v = coins / 1000000;
      return '${v == v.truncateToDouble() ? v.toInt() : v.toStringAsFixed(1)}M';
    }
    if (coins >= 1000) {
      final v = coins / 1000;
      return '${v == v.truncateToDouble() ? v.toInt() : v.toStringAsFixed(0)}K';
    }
    return '$coins';
  }

  static Color _prizeColor(int? coins) {
    if (coins == null) return Colors.white;
    if (coins >= 500000) return const Color(0xFFCF6FFF);
    if (coins >= 200000) return _kGold;
    if (coins >= 50000)  return _kBlue;
    if (coins >= 10000)  return Colors.white70;
    return _kRed;
  }

  static IconData _prizeIcon(int? coins) {
    if (coins == null) return Icons.help_outline_rounded;
    if (coins >= 500000) return Icons.diamond_rounded;
    if (coins >= 200000) return Icons.star_rounded;
    if (coins >= 50000)  return Icons.monetization_on_rounded;
    if (coins >= 10000)  return Icons.toll_rounded;
    return Icons.remove_circle_outline_rounded;
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _phase == _Phase.loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPurple))
                  : _phase == _Phase.error
                      ? _buildError()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          child: _buildBody(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Back
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _kSurface,
                shape: BoxShape.circle,
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isArabic ? 'كنز سرود' : 'Srood Treasure',
                  style: const TextStyle(
                      color: _kGold,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  _isArabic ? '١٦ صندوق – صفقة أم لا؟' : '16 Boxes · Deal or No Deal?',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          // Balance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.toll_rounded, color: _kGold, size: 14),
                const SizedBox(width: 4),
                Text(_fmt(_userBalance),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // Refresh
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _load(),
            child: const Icon(Icons.refresh_rounded,
                color: Colors.white38, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(_isArabic ? 'حدث خطأ' : 'Something went wrong',
              style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _load,
            child: Text(_isArabic ? 'إعادة المحاولة' : 'Retry',
                style: const TextStyle(color: _kPurple)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_phase) {
      _Phase.idle        => _buildIdleContent(),
      _Phase.selecting   => _buildActiveContent(),
      _Phase.playing     => _buildActiveContent(),
      _Phase.dealOffered => _buildActiveContent(),
      _Phase.completed   => _buildActiveContent(),
      _                  => _buildIdleContent(),
    };
  }

  List<Widget> _prizePills() {
    final sorted = _settings.prizeAmounts.toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return sorted.take(8).map<Widget>((p) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _prizeColor(p).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _prizeColor(p).withValues(alpha: 0.35)),
        ),
        child: Text(
          _fmt(p),
          style: TextStyle(
              color: _prizeColor(p),
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
      );
    }).toList();
  }

  // ── Idle ───────────────────────────────────────────────────────────────────

  Widget _buildIdleContent() {
    final hasBalance = _userBalance >= _settings.entryFeeCoins;
    return Column(
      children: [
        const SizedBox(height: 24),
        // Hero chest icon
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              _kGold.withValues(alpha: 0.25),
              _kPurple.withValues(alpha: 0.15),
              Colors.transparent,
            ]),
          ),
          child: const Center(
            child: Text('🏆', style: TextStyle(fontSize: 64)),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _isArabic ? 'كنز سرود' : 'Srood Treasure',
          style: const TextStyle(
              color: _kGold, fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _isArabic
              ? 'اختر صندوقك المحظوظ من بين ١٦ صندوقًا!\nافتح الصناديق وقرر: صفقة أم لا؟'
              : 'Pick your lucky box from 16 hidden treasures!\nOpen boxes one by one — Deal or No Deal?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 28),
        // Prize range
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _InfoPill(
                label: _isArabic ? 'رسوم الدخول' : 'Entry Fee',
                value: _fmt(_settings.entryFeeCoins),
                icon: Icons.toll_rounded,
                color: _kAmber,
              ),
              Container(width: 1, height: 40, color: _kBorder),
              _InfoPill(
                label: _isArabic ? 'أقصى جائزة' : 'Top Prize',
                value: _fmt(_settings.maxPrizeCoins),
                icon: Icons.diamond_rounded,
                color: const Color(0xFFCF6FFF),
              ),
              Container(width: 1, height: 40, color: _kBorder),
              _InfoPill(
                label: _isArabic ? 'الصناديق' : 'Boxes',
                value: '16',
                icon: Icons.inventory_2_rounded,
                color: _kBlue,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Start button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: hasBalance && !_actionLoading ? _startGame : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              disabledBackgroundColor: _kBorder,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _actionLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(
                    hasBalance
                        ? (_isArabic
                            ? 'ابدأ اللعبة – ${_fmt(_settings.entryFeeCoins)} عملة'
                            : 'Start Game – ${_fmt(_settings.entryFeeCoins)} Coins')
                        : (_isArabic ? 'رصيد غير كافٍ' : 'Insufficient Balance'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Top prizes preview
        Text(
          _isArabic ? 'الجوائز المتاحة' : 'Available Prizes',
          style: const TextStyle(
              color: Colors.white54, fontSize: 12, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: _prizePills(),
        ),
      ],
    );
  }

  // ── Active game ────────────────────────────────────────────────────────────

  Widget _buildActiveContent() {
    final game = _game;
    if (game == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildStatusBar(game),
        const SizedBox(height: 14),
        _buildBoxGrid(game),
        const SizedBox(height: 16),
        if (_phase == _Phase.dealOffered) _buildDealCard(game),
        if (_phase == _Phase.completed)   _buildResultCard(game),
        if (_phase == _Phase.selecting || _phase == _Phase.playing)
          _buildHint(game),
      ],
    );
  }

  Widget _buildStatusBar(TreasureGame game) {
    final opened = game.boxesOpened;
    final total  = 15;
    final progress = opened / total;

    final roundLabel = switch (game.roundNumber) {
      0 => _isArabic ? 'الجولة ١' : 'Round 1',
      1 => _isArabic ? 'الجولة ٢' : 'Round 2',
      2 => _isArabic ? 'الجولة ٣' : 'Round 3',
      _ => _isArabic ? 'الجولة الأخيرة' : 'Final Round',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(roundLabel,
                  style: const TextStyle(
                      color: _kGold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                _isArabic
                    ? '$opened / $total صندوق مفتوح'
                    : '$opened / $total boxes opened',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: _kBorder,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(_kPurple),
              minHeight: 5,
            ),
          ),
          if (_phase == _Phase.playing) ...[
            const SizedBox(height: 6),
            Text(
              _isArabic
                  ? 'افتح ${game.boxesUntilNextOffer} صندوق للوصول للعرض التالي'
                  : 'Open ${game.boxesUntilNextOffer} more box${game.boxesUntilNextOffer == 1 ? "" : "es"} to trigger next offer',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoxGrid(TreasureGame game) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.88,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 16,
      itemBuilder: (_, i) => _buildBox(game, i + 1),
    );
  }

  Widget _buildBox(TreasureGame game, int number) {
    final box = game.boxes.where((b) => b.boxNumber == number).firstOrNull;
    final isPersonal = box?.isPersonal ?? false;
    final isOpened   = box?.isOpened   ?? false;
    final prize      = box?.prizeCoins;
    final isLoading  = _openingBox == number;

    final canSelect = _phase == _Phase.selecting && box != null && !isOpened;
    final canOpen   = _phase == _Phase.playing && !isOpened && !isPersonal &&
        _openingBox == null && !_actionLoading;

    Widget boxContent;
    if (isLoading) {
      boxContent = const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: _kGold, strokeWidth: 2),
        ),
      );
    } else if (isOpened) {
      boxContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_prizeIcon(prize), color: _prizeColor(prize), size: 20),
          const SizedBox(height: 3),
          Text(
            _fmt(prize ?? 0),
            style: TextStyle(
                color: _prizeColor(prize),
                fontSize: 12,
                fontWeight: FontWeight.w800),
          ),
        ],
      );
    } else {
      boxContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPersonal
                ? Icons.star_rounded
                : Icons.inventory_2_rounded,
            color: isPersonal ? _kGold : _kPurple.withValues(alpha: 0.8),
            size: 22,
          ),
          const SizedBox(height: 3),
          Text(
            '$number',
            style: TextStyle(
                color: isPersonal ? _kGold : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          if (isPersonal)
            Text(
              _isArabic ? 'صندوقك' : 'Yours',
              style: const TextStyle(
                  color: _kGold,
                  fontSize: 8,
                  fontWeight: FontWeight.w600),
            ),
        ],
      );
    }

    Color borderColor;
    double borderWidth;
    List<BoxShadow>? shadows;

    if (isPersonal && !isOpened) {
      borderColor = _kGold;
      borderWidth = 2;
      shadows = [BoxShadow(color: _kGold.withValues(alpha: _glowAnim.value * 0.5), blurRadius: 12, spreadRadius: 2)];
    } else if (isOpened) {
      borderColor = _prizeColor(prize).withValues(alpha: 0.5);
      borderWidth = 1;
      shadows = null;
    } else if (canSelect || canOpen) {
      borderColor = _kPurple.withValues(alpha: 0.5);
      borderWidth = 1;
      shadows = null;
    } else {
      borderColor = _kBorder;
      borderWidth = 1;
      shadows = null;
    }

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, child) => GestureDetector(
        onTap: () {
          if (canSelect) _selectBox(number);
          if (canOpen) _openBox(number);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isOpened
                ? _prizeColor(prize).withValues(alpha: 0.08)
                : (isPersonal ? _kGold.withValues(alpha: 0.08) : _kCard),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: shadows,
          ),
          child: boxContent,
        ),
      ),
    );
  }

  Widget _buildHint(TreasureGame game) {
    final text = switch (_phase) {
      _Phase.selecting => _isArabic
          ? '👆 اضغط على صندوق لاختياره كصندوقك الشخصي'
          : '👆 Tap a box to choose it as your personal box',
      _Phase.playing => _isArabic
          ? '📦 اضغط على أي صندوق لفتحه'
          : '📦 Tap any box to open it',
      _ => '',
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }

  Widget _buildDealCard(TreasureGame game) {
    final offer       = game.currentOfferCoins ?? 0;
    final isFinal     = game.isFinalRound;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0D3D), Color(0xFF2A1560)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGold, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: _kGold.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          Text(
            _isArabic ? '💼 عرض السمسار' : '💼 Banker\'s Offer',
            style: const TextStyle(
                color: _kGold, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            _fmt(offer),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1),
          ),
          Text(
            _isArabic ? 'عملة' : 'coins',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  label: _isArabic ? 'قبول ✅' : 'DEAL ✅',
                  color: _kGreen,
                  loading: _actionLoading,
                  onTap: _acceptOffer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isFinal
                    ? _ActionBtn(
                        label: _isArabic ? 'افتح صندوقي 🎁' : 'MY BOX 🎁',
                        color: _kPurple,
                        loading: _actionLoading,
                        onTap: _takeBox,
                      )
                    : _ActionBtn(
                        label: _isArabic ? 'رفض ❌' : 'NO DEAL ❌',
                        color: _kRed,
                        loading: _actionLoading,
                        onTap: _continueGame,
                      ),
              ),
            ],
          ),
          if (!isFinal) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: _actionLoading ? null : _confirmAbandon,
              child: Text(
                _isArabic ? 'التخلي عن اللعبة' : 'Abandon game',
                style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard(TreasureGame game) {
    final payout       = game.finalPayoutCoins ?? 0;
    final personalPrize = game.personalBoxPrize ?? 0;
    final isOffer      = game.payoutType == 'offer';
    final isWin        = payout > game.entryFeeCoins;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isWin
              ? [const Color(0xFF1A2D0D), const Color(0xFF0D3020)]
              : [const Color(0xFF1A0D0D), const Color(0xFF2D100D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isWin ? _kGreen : _kRed, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            isWin ? '🎉' : '😔',
            style: const TextStyle(fontSize: 40),
          ),
          const SizedBox(height: 8),
          Text(
            _isArabic
                ? (isWin ? 'مبروك! ربحت' : 'أفضل حظاً المرة القادمة')
                : (isWin ? 'Congratulations!' : 'Better luck next time!'),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.toll_rounded, color: _kGold, size: 20),
              const SizedBox(width: 6),
              Text(
                _fmt(payout),
                style: TextStyle(
                    color: isWin ? _kGreen : _kRed,
                    fontSize: 32,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 6),
              Text(
                _isArabic ? 'عملة' : 'coins',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
          if (isOffer && personalPrize > 0) ...[
            const SizedBox(height: 8),
            Text(
              _isArabic
                  ? 'كان في صندوقك: ${_fmt(personalPrize)} عملة'
                  : 'Your box had: ${_fmt(personalPrize)} coins',
              style: TextStyle(
                  color: _prizeColor(personalPrize),
                  fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _actionLoading ? null : () => _load(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                _isArabic ? 'لعبة جديدة' : 'Play Again',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        Text(label,
            style:
                const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          color: loading ? _kBorder : color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: loading ? _kBorder : color, width: 1.5),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(
                  label,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}
