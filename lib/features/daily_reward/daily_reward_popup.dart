import 'package:flutter/material.dart';

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
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => DailyRewardPopup(initial: state, isArabic: isArabic),
  );
}

/// Daily Reward popup. Call [DailyRewardPopup.show] to load live state and
/// display. Returns nothing; it reads its own state from the server.
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
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => DailyRewardPopup(initial: state, isArabic: isArabic),
    );
  }

  @override
  State<DailyRewardPopup> createState() => _DailyRewardPopupState();
}

class _DailyRewardPopupState extends State<DailyRewardPopup> {
  static const _gold = Color(0xFFF0C15A);
  static const _purple = Color(0xFF8B26D9);

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
            : 'Reward claimed successfully!'
                ' (+${_fmt(res.amount)})';
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
    final rules = [for (var d = 1; d <= 7; d++) _state.ruleForDay(d)];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A0E45), Color(0xFF160A29), Color(0xFF0C0518)],
            ),
            border: Border.all(color: _gold.withValues(alpha: 0.45), width: 1.2),
            boxShadow: [
              BoxShadow(color: _purple.withValues(alpha: 0.35), blurRadius: 30),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, color: _gold, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isArabic ? 'المكافأة اليومية' : 'Daily Reward',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    splashRadius: 20,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14, top: 2),
                child: Text(
                  isArabic
                      ? 'سجّل دخولك 7 أيام متتالية لتحصل على مكافأة غامضة!'
                      : 'Sign in continuously for 7 days to receive a mysterious reward!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFCBBEE6),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              // Days 1-6 grid (3 columns)
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.92,
                children: [
                  for (var d = 1; d <= 6; d++)
                    _DayCell(
                      day: d,
                      rule: rules[d - 1],
                      claimed: d <= _claimedThrough,
                      claimable: _state.canClaimToday && d == _state.claimDay,
                      premium: false,
                      isArabic: isArabic,
                      fmt: _fmt,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Day 7 premium wide cell
              _DayCell(
                day: 7,
                rule: rules[6],
                claimed: 7 <= _claimedThrough,
                claimable: _state.canClaimToday && _state.claimDay == 7,
                premium: true,
                isArabic: isArabic,
                fmt: _fmt,
              ),
              const SizedBox(height: 14),
              if (_flash != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _flash!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              // Claim button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _state.canClaimToday ? _gold : const Color(0xFF2A1B3D),
                    foregroundColor: const Color(0xFF0A0612),
                    disabledBackgroundColor: const Color(0xFF2A1B3D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: (_state.canClaimToday && !_claiming) ? _claim : null,
                  child: _claiming
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Color(0xFF0A0612)),
                        )
                      : Text(
                          _state.canClaimToday
                              ? (isArabic ? 'استلام' : 'Claim')
                              : (isArabic
                                  ? 'تم الاستلام اليوم'
                                  : 'Claimed Today'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: _state.canClaimToday
                                ? const Color(0xFF0A0612)
                                : const Color(0xFF9C8FCB),
                          ),
                        ),
                ),
              ),
              if (!_state.canClaimToday) ...[
                const SizedBox(height: 8),
                Text(
                  isArabic ? 'عُد غداً' : 'Come Back Tomorrow',
                  style: const TextStyle(
                    color: Color(0xFF9C8FCB),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.rule,
    required this.claimed,
    required this.claimable,
    required this.premium,
    required this.isArabic,
    required this.fmt,
  });

  final int day;
  final DailyRewardRule? rule;
  final bool claimed;
  final bool claimable;
  final bool premium;
  final bool isArabic;
  final String Function(int) fmt;

  static const _gold = Color(0xFFF0C15A);

  @override
  Widget build(BuildContext context) {
    final amount = rule?.amount ?? 0;
    final border = claimable
        ? _gold
        : claimed
            ? const Color(0xFF2ECC71)
            : Colors.white.withValues(alpha: 0.10);
    final dim = !claimable && !claimed;

    final content = Container(
      padding: EdgeInsets.symmetric(
          horizontal: premium ? 14 : 6, vertical: premium ? 12 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: premium
            ? const LinearGradient(
                colors: [Color(0x33F0C15A), Color(0x22000000)])
            : null,
        color: premium ? null : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
            color: border, width: claimable ? 1.6 : 1),
        boxShadow: claimable
            ? [BoxShadow(color: _gold.withValues(alpha: 0.45), blurRadius: 12)]
            : null,
      ),
      child: premium
          ? Row(
              children: [
                _coin(38),
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
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2ECC71), size: 22),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isArabic ? 'يوم $day' : 'Day $day',
                  style: TextStyle(
                    color: claimable ? _gold : const Color(0xFFBCAED6),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                _coin(26),
                const SizedBox(height: 3),
                FittedBox(
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
              ],
            ),
    );

    return Opacity(
      opacity: dim ? 0.6 : 1.0,
      child: Stack(
        children: [
          content,
          if (claimed && !premium)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.check_circle_rounded,
                  color: Color(0xFF2ECC71), size: 16),
            ),
        ],
      ),
    );
  }

  // Programmatic coin icon (original — no external asset).
  Widget _coin(double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF1C9), Color(0xFFEFC15A), Color(0xFFC8901F)],
          ),
          border: Border.all(color: const Color(0xFFFFE9A8), width: 1),
          boxShadow: [
            BoxShadow(color: _gold.withValues(alpha: 0.4), blurRadius: 4),
          ],
        ),
        child: Text(
          '\$',
          style: TextStyle(
            color: const Color(0xFF7A4E07),
            fontWeight: FontWeight.w900,
            fontSize: size * 0.5,
          ),
        ),
      );
}
