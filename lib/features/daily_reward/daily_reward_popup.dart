import 'package:flutter/material.dart';

import '../../shared/widgets/premium_ui.dart';
import 'daily_reward_models.dart';
import 'daily_reward_service.dart';

/// Shows the daily reward dialog using an already-loaded [state] (no extra
/// fetch). Used by the home screen's auto-popup which already read the state.
Future<void> showDailyRewardDialog(
  BuildContext context, {
  required DailyRewardState state,
  required bool isArabic,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.74),
    builder: (_) => DailyRewardPopup(initial: state, isArabic: isArabic),
  );
}

/// Premium 3D Daily Reward modal. Call [DailyRewardPopup.show] to load live
/// state and display, or [showDailyRewardDialog] with a preloaded state.
/// UI-only: all claim/streak/eligibility logic is server-side and unchanged.
class DailyRewardPopup extends StatefulWidget {
  const DailyRewardPopup({
    required this.initial,
    required this.isArabic,
    super.key,
  });

  final DailyRewardState initial;
  final bool isArabic;

  static Future<void> show(BuildContext context, {required bool isArabic}) async {
    DailyRewardState state;
    try {
      state = await const DailyRewardService().getState();
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    if (!state.enabled) return;
    await showDailyRewardDialog(context, state: state, isArabic: isArabic);
  }

  @override
  State<DailyRewardPopup> createState() => _DailyRewardPopupState();
}

class _DailyRewardPopupState extends State<DailyRewardPopup> {
  static const _gold = Color(0xFFF0C15A);
  static const _goldDeep = Color(0xFFC8901F);

  late DailyRewardState _state;
  bool _claiming = false;
  String? _flash;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  // Days fully claimed in the current cycle.
  int get _claimedThrough =>
      _state.claimedToday ? _state.currentDay : (_state.claimDay - 1);

  Future<void> _claim() async {
    if (_claiming || !_state.canClaimToday) return;
    setState(() => _claiming = true);
    try {
      final res = await const DailyRewardService().claim();
      final fresh = await const DailyRewardService().getState();
      if (!mounted) return;
      setState(() {
        _state = fresh;
        _claiming = false;
        _flash = widget.isArabic
            ? 'تم استلام المكافأة بنجاح!'
            : 'Reward claimed successfully! (+${_fmt(res.amount)})';
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _claiming = false;
        _flash = raw.contains('already_claimed')
            ? (widget.isArabic ? 'تم الاستلام اليوم' : 'Claimed today')
            : (widget.isArabic
                ? 'تعذّر استلام المكافأة'
                : 'Could not claim reward');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        // Wider-than-tall, square-ish premium modal.
        constraints: const BoxConstraints(maxWidth: 360),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              // Layered dark-purple card background.
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3A1566), Color(0xFF1C0B33), Color(0xFF0D0518)],
                stops: [0.0, 0.5, 1.0],
              ),
              // Beveled gold rim.
              border: Border.all(color: _gold.withValues(alpha: 0.65), width: 1.6),
              boxShadow: [
                // Outer purple glow.
                BoxShadow(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.40),
                  blurRadius: 34,
                  spreadRadius: 1,
                ),
                // Gold halo.
                BoxShadow(
                  color: _gold.withValues(alpha: 0.18),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Top glossy shine.
                const Positioned.fill(child: GlossSheen(opacity: 0.16)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _header(isArabic),
                      const SizedBox(height: 6),
                      Text(
                        isArabic
                            ? 'سجّل دخولك 7 أيام وافتح مكافأة غامضة!'
                            : 'Claim daily for 7 days and unlock a mystery reward!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFCBBEE6),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _grid(isArabic),
                      const SizedBox(height: 8),
                      _day7(isArabic),
                      const SizedBox(height: 12),
                      if (_flash != null) ...[
                        Text(
                          _flash!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      _claimButton(isArabic),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool isArabic) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF1C9), Color(0xFFE8C25A)],
            ),
            boxShadow: [
              BoxShadow(color: _gold.withValues(alpha: 0.5), blurRadius: 8),
            ],
          ),
          child: const Icon(Icons.card_giftcard_rounded,
              color: Color(0xFF5A3B06), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isArabic ? 'المكافأة اليومية' : 'Daily Reward',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black45, blurRadius: 3)],
            ),
          ),
        ),
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          customBorder: const CircleBorder(),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _grid(bool isArabic) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 0.86,
      children: [
        for (var d = 1; d <= 6; d++)
          DailyReward3DCell(
            day: d,
            amount: _state.ruleForDay(d)?.amount ?? 0,
            claimed: d <= _claimedThrough,
            claimable: _state.canClaimToday && d == _state.claimDay,
            isArabic: isArabic,
            fmt: _fmt,
          ),
      ],
    );
  }

  Widget _day7(bool isArabic) {
    return DailyRewardDay7Card(
      amount: _state.ruleForDay(7)?.amount ?? 0,
      claimed: 7 <= _claimedThrough,
      claimable: _state.canClaimToday && _state.claimDay == 7,
      isArabic: isArabic,
      fmt: _fmt,
    );
  }

  Widget _claimButton(bool isArabic) {
    final canClaim = _state.canClaimToday;
    return Column(
      children: [
        GlossyButton(
          label: canClaim
              ? (isArabic ? 'استلام' : 'Claim')
              : (isArabic ? 'تم الاستلام اليوم' : 'Claimed Today'),
          icon: canClaim ? Icons.bolt_rounded : Icons.check_circle_rounded,
          accent: canClaim ? _gold : _goldDeep,
          loading: _claiming,
          height: 48,
          onPressed: (canClaim && !_claiming) ? _claim : null,
        ),
        if (!canClaim) ...[
          const SizedBox(height: 6),
          Text(
            isArabic ? 'عُد غداً' : 'Come Back Tomorrow',
            style: const TextStyle(
              color: Color(0xFF9C8FCB),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Reusable 3D coin chip ─────────────────────────────────────────────────────
class _Coin extends StatelessWidget {
  const _Coin({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6D4), Color(0xFFEFC15A), Color(0xFFB67E14)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: const Color(0xFFFFE9A8), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.5),
            blurRadius: 5,
          ),
        ],
      ),
      child: Text(
        '\$',
        style: TextStyle(
          color: const Color(0xFF7A4E07),
          fontWeight: FontWeight.w900,
          fontSize: size * 0.52,
        ),
      ),
    );
  }
}

/// A square 3D reward cell (Day 1–6).
class DailyReward3DCell extends StatelessWidget {
  const DailyReward3DCell({
    required this.day,
    required this.amount,
    required this.claimed,
    required this.claimable,
    required this.isArabic,
    required this.fmt,
    super.key,
  });

  final int day;
  final int amount;
  final bool claimed;
  final bool claimable;
  final bool isArabic;
  final String Function(int) fmt;

  static const _gold = Color(0xFFF0C15A);
  static const _green = Color(0xFF2ECC71);

  @override
  Widget build(BuildContext context) {
    final rim = claimable
        ? _gold
        : claimed
            ? _green.withValues(alpha: 0.7)
            : _gold.withValues(alpha: 0.22);
    final dim = !claimable && !claimed;

    return Opacity(
      opacity: dim ? 0.55 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          // Dark purple glass, raised.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x3DFFFFFF), Color(0x14000000), Color(0x33000000)],
          ),
          border: Border.all(color: rim, width: claimable ? 1.8 : 1),
          boxShadow: [
            if (claimable)
              BoxShadow(color: _gold.withValues(alpha: 0.5), blurRadius: 12),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isArabic ? 'يوم $day' : 'Day $day',
                    style: TextStyle(
                      color: claimable ? _gold : const Color(0xFFCBBEE6),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _Coin(size: 26),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        fmt(amount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (claimed)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.black.withValues(alpha: 0.28),
                  ),
                  child: const Center(
                    child: Icon(Icons.check_circle_rounded,
                        color: _green, size: 26),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Premium wide horizontal Day 7 card (compact height).
class DailyRewardDay7Card extends StatelessWidget {
  const DailyRewardDay7Card({
    required this.amount,
    required this.claimed,
    required this.claimable,
    required this.isArabic,
    required this.fmt,
    super.key,
  });

  final int amount;
  final bool claimed;
  final bool claimable;
  final bool isArabic;
  final String Function(int) fmt;

  static const _gold = Color(0xFFF0C15A);
  static const _green = Color(0xFF2ECC71);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: (!claimable && !claimed) ? 0.7 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0x55F0C15A), Color(0x22000000)],
          ),
          border: Border.all(
            color: claimable ? _gold : _gold.withValues(alpha: 0.5),
            width: claimable ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: _gold.withValues(alpha: claimable ? 0.5 : 0.25),
              blurRadius: claimable ? 16 : 8,
            ),
          ],
        ),
        child: Row(
          children: [
            // Mystery chest / coin.
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFE9A8), Color(0xFFD9A93C)],
                ),
                boxShadow: [
                  BoxShadow(color: _gold.withValues(alpha: 0.5), blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFF5A3B06), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isArabic ? 'اليوم 7' : 'Day 7',
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${fmt(amount)} ${isArabic ? 'عملة' : 'coins'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (claimed)
              const Icon(Icons.check_circle_rounded, color: _green, size: 24),
          ],
        ),
      ),
    );
  }
}
