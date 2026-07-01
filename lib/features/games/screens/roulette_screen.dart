import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../shared/widgets/coin_ui.dart';
import '../models/roulette_models.dart';
import '../services/roulette_service.dart';

/// Srood Roulette — server-authoritative table game. The client only shows
/// round state and forwards bets; the winning number, wallet debit/credit,
/// and every payout are decided entirely by the round-engine RPCs.
class RouletteScreen extends StatefulWidget {
  const RouletteScreen({
    required this.isArabic,
    this.roomId,
    this.service = const RouletteService(),
    super.key,
  });

  final bool isArabic;
  final String? roomId;
  final RouletteService service;

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

const List<int> kRouletteRedNumbers = [
  1,
  3,
  5,
  7,
  9,
  12,
  14,
  16,
  18,
  19,
  21,
  23,
  25,
  27,
  30,
  32,
  34,
  36,
];

bool _isRed(int n) => kRouletteRedNumbers.contains(n);

class _RouletteScreenState extends State<RouletteScreen> {
  Timer? _pollTimer;
  Timer? _clockTimer;

  bool _loading = true;
  String? _loadError;
  RouletteState? _state;
  int _betIndex = 0;
  final Set<String> _pendingZones = {};
  String? _toastMessage;
  bool _toastIsError = false;
  Timer? _toastTimer;
  DateTime _now = DateTime.now();

  bool get _isArabic => widget.isArabic;
  int get _betAmount => kRouletteBetAmounts[_betIndex];

  @override
  void initState() {
    super.initState();
    _loadState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadState(silent: true);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadState({bool silent = false}) async {
    if (SupabaseService.requiredClient.auth.currentUser == null) {
      setState(() {
        _loading = false;
        _loadError = 'not_authenticated';
      });
      return;
    }
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final state = await widget.service.fetchState(roomId: widget.roomId);
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _loadError = '$e';
      });
    }
  }

  Future<void> _onBetZone(String zone) async {
    final state = _state;
    if (state == null || !state.canBet) return;
    if (_pendingZones.contains(zone)) return;
    if (state.balance < _betAmount) {
      _showToast(
        _isArabic ? 'رصيد غير كافٍ' : 'Insufficient coins',
        isError: true,
      );
      return;
    }

    setState(() => _pendingZones.add(zone));
    try {
      final result = await widget.service.placeBet(
        roundId: state.round!.roundId,
        betZone: zone,
        betAmount: _betAmount,
      );
      if (!mounted) return;
      _showToast(
        _isArabic
            ? 'راهنت ${formatCoinAmount(result.betAmount)}'
            : 'Bet placed: ${formatCoinAmount(result.betAmount)}',
        isError: false,
      );
      await _loadState(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showToast(_isArabic ? 'تعذر الرهان' : 'Bet failed', isError: true);
    } finally {
      if (mounted) {
        setState(() => _pendingZones.remove(zone));
      }
    }
  }

  void _showToast(String message, {required bool isError}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastIsError = isError;
    });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _toastMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0620),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody()),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final balance = _state?.balance ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              _isArabic ? 'روليت سرود' : 'Srood Roulette',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: const Color(0xFF241239),
              border: Border.all(color: const Color(0xFF6D28D9)),
            ),
            child: CoinAmountText(amount: balance, fontSize: 13, iconSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _state == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFA78BFA)),
      );
    }
    if (_loadError != null && _state == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white54,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                _isArabic ? 'تعذر تحميل اللعبة' : 'Failed to load',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadState(),
                child: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final state = _state;
    final round = state?.round;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      children: [
        _buildStatusBanner(round),
        const SizedBox(height: 12),
        _buildRecentResults(state?.recentResults ?? const []),
        const SizedBox(height: 14),
        _buildBetGrid(state),
        if (_toastMessage != null) ...[
          const SizedBox(height: 12),
          _buildToast(),
        ],
        if (state != null && state.myBets.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildMyBets(state.myBets),
        ],
      ],
    );
  }

  Widget _buildToast() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:
            (_toastIsError ? const Color(0xFF7F1D1D) : const Color(0xFF14532D))
                .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _toastMessage!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildStatusBanner(RouletteRound? round) {
    String label;
    Color color;
    if (round == null) {
      label = _isArabic ? 'بانتظار جولة جديدة...' : 'Waiting for round...';
      color = Colors.white54;
    } else {
      switch (round.status) {
        case 'betting_open':
          final secs = round.bettingClosesAt.difference(_now).inSeconds;
          final remaining = secs > 0 ? secs : 0;
          label = _isArabic
              ? 'الرهان مفتوح — $remainingث'
              : 'Betting open — ${remaining}s';
          color = const Color(0xFF4ADE80);
        case 'locked':
          label = _isArabic ? 'الرهان مغلق' : 'Betting closed';
          color = const Color(0xFFF5A820);
        case 'spinning':
          label = _isArabic ? 'العجلة تدور...' : 'Spinning...';
          color = const Color(0xFFA78BFA);
        case 'settled':
          final n = round.winningNumber;
          label = n == null
              ? (_isArabic ? 'انتهت الجولة' : 'Round settled')
              : (_isArabic ? 'الرقم الفائز: $n' : 'Winning number: $n');
          color = const Color(0xFF38BDF8);
        default:
          label = round.status;
          color = Colors.white54;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B0F30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.casino_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentResults(List<int> recent) {
    if (recent.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final n = recent[i];
          final color = n == 0
              ? const Color(0xFF16A34A)
              : (_isRed(n) ? const Color(0xFFDC2626) : const Color(0xFF1F2937));
          return Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Text(
              '$n',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          );
        },
      ),
    );
  }

  int _myBetFor(RouletteState? state, String zone) {
    if (state == null) return 0;
    var total = 0;
    for (final b in state.myBets) {
      if (b.betZone == zone) total += b.betAmount;
    }
    return total;
  }

  Widget _buildBetGrid(RouletteState? state) {
    final canBet = state?.canBet ?? false;
    return Column(
      children: [
        _zoneRow(state, canBet, [
          _zoneSpec('straight_zero', '0', const Color(0xFF16A34A)),
        ]),
        const SizedBox(height: 8),
        _zoneRow(state, canBet, [
          _zoneSpec(
            'low',
            _isArabic ? '1-12 (x3)' : '1-12 (x3)',
            const Color(0xFF334155),
          ),
          _zoneSpec(
            'mid',
            _isArabic ? '13-24 (x3)' : '13-24 (x3)',
            const Color(0xFF334155),
          ),
          _zoneSpec(
            'high',
            _isArabic ? '25-36 (x3)' : '25-36 (x3)',
            const Color(0xFF334155),
          ),
        ]),
        const SizedBox(height: 8),
        _zoneRow(state, canBet, [
          _zoneSpec(
            'red',
            _isArabic ? 'أحمر (x2)' : 'Red (x2)',
            const Color(0xFFDC2626),
          ),
          _zoneSpec(
            'black',
            _isArabic ? 'أسود (x2)' : 'Black (x2)',
            const Color(0xFF1F2937),
          ),
        ]),
        const SizedBox(height: 8),
        _zoneRow(state, canBet, [
          _zoneSpec(
            'even',
            _isArabic ? 'زوجي (x2)' : 'Even (x2)',
            const Color(0xFF334155),
          ),
          _zoneSpec(
            'odd',
            _isArabic ? 'فردي (x2)' : 'Odd (x2)',
            const Color(0xFF334155),
          ),
        ]),
      ],
    );
  }

  ({String zone, String label, Color color}) _zoneSpec(
    String zone,
    String label,
    Color color,
  ) => (zone: zone, label: label, color: color);

  Widget _zoneRow(
    RouletteState? state,
    bool canBet,
    List<({String zone, String label, Color color})> specs,
  ) {
    return Row(
      children: specs
          .map(
            (s) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildZoneButton(
                  state,
                  canBet,
                  s.zone,
                  s.label,
                  s.color,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildZoneButton(
    RouletteState? state,
    bool canBet,
    String zone,
    String label,
    Color color,
  ) {
    final myBet = _myBetFor(state, zone);
    final isPending = _pendingZones.contains(zone);
    return InkWell(
      onTap: canBet && !isPending ? () => _onBetZone(zone) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: canBet ? 0.85 : 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: myBet > 0 ? const Color(0xFFFFE566) : Colors.white24,
            width: myBet > 0 ? 2 : 1,
          ),
        ),
        child: isPending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  if (myBet > 0)
                    Text(
                      formatCoinAmount(myBet),
                      style: const TextStyle(
                        color: Color(0xFFFFE566),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildMyBets(List<RouletteBet> bets) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B0F30),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isArabic ? 'رهاناتي' : 'My bets',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...bets.map(
            (b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      b.betZone,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  CoinAmountText(
                    amount: b.betAmount,
                    fontSize: 12,
                    iconSize: 13,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    b.status,
                    style: TextStyle(
                      color: switch (b.status) {
                        'won' => const Color(0xFF4ADE80),
                        'lost' => Colors.white38,
                        _ => const Color(0xFFF5A820),
                      },
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8 + (bottomInset > 8 ? bottomInset : 8),
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1B0F30),
        border: Border(top: BorderSide(color: Color(0xFF2E1A4D))),
      ),
      child: SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: kRouletteBetAmounts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final amount = kRouletteBetAmounts[i];
            final selected = i == _betIndex;
            return GestureDetector(
              onTap: () => setState(() => _betIndex = i),
              child: Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: selected
                      ? const Color(0xFFA78BFA)
                      : const Color(0xFF241239),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFEDE9FE)
                        : const Color(0xFF6D28D9),
                  ),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatCoinAmount(amount),
                    maxLines: 1,
                    style: TextStyle(
                      color: selected ? const Color(0xFF2E1065) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
