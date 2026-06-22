import 'package:flutter/material.dart';

import '../../daily_reward/daily_reward_models.dart';
import '../../daily_reward/daily_reward_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _service = const DailyRewardService();
  DailyRewardState? _status;
  bool _loading = true;
  bool _claiming = false;
  String? _error;

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
      final status = await _service.getState();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[CheckinScreen._load] error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkin() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final res = await _service.claim();
      if (!mounted) return;
      final isDiamond = res.rewardType == 'diamonds';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isDiamond
                    ? Icons.diamond_rounded
                    : Icons.monetization_on_rounded,
                color: isDiamond
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFFF0C15A),
              ),
              const SizedBox(width: 8),
              Text(
                context.isArabic
                    ? 'تم تسجيل الحضور! +${res.amount} ${isDiamond ? 'ماسة' : 'عملة'}'
                    : 'Checked in! +${res.amount} ${isDiamond ? 'diamonds' : 'coins'}',
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1B102A),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.contains('already_claimed')
                ? (context.isArabic
                    ? 'تم تسجيل حضورك اليوم بالفعل'
                    : 'Already checked in today')
                : msg.contains('daily_reward_disabled')
                    ? (context.isArabic
                        ? 'الميزة غير متاحة حالياً'
                        : 'Feature not available')
                    : (context.isArabic
                        ? 'تعذّر تسجيل الحضور'
                        : 'Could not check in'),
          ),
          backgroundColor: const Color(0xFFFF4D6D),
        ),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
    child: Row(
      textDirection: context.isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        Text(
          context.isArabic ? 'تسجيل الحضور' : 'Daily Check-in',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF0C15A),
          strokeWidth: 2.5,
        ),
      );
    }
    if (_error != null) return _buildError();
    final s = _status!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _StreakCard(streak: s.streakCount, isArabic: context.isArabic),
          const SizedBox(height: 20),
          _RewardCalendar(status: s, isArabic: context.isArabic),
          const SizedBox(height: 28),
          _CheckinButton(
            status: s,
            claiming: _claiming,
            isArabic: context.isArabic,
            onCheckin: _checkin,
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFFF5C7A),
          size: 40,
        ),
        const SizedBox(height: 12),
        Text(
          context.isArabic
              ? 'تعذّر تحميل البيانات'
              : 'Could not load check-in data',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _load,
          child: Text(
            context.isArabic ? 'إعادة المحاولة' : 'Retry',
            style: const TextStyle(color: Color(0xFFF0C15A)),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Streak card
// ---------------------------------------------------------------------------

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak, required this.isArabic});
  final int streak;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4B168C), Color(0xFF8B26D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('\u{1F381}', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          Text(
            '$streak',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isArabic
                ? 'يوم متتالي'
                : streak == 1
                    ? 'day streak'
                    : 'days streak',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7-day reward calendar
// ---------------------------------------------------------------------------

class _RewardCalendar extends StatelessWidget {
  const _RewardCalendar({required this.status, required this.isArabic});
  final DailyRewardState status;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    // Days fully completed this cycle.
    final claimedThrough =
        status.claimedToday ? status.currentDay : (status.claimDay - 1);

    return Column(
      crossAxisAlignment:
          isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'مكافآت الأسبوع' : 'Weekly Rewards',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: status.rules.map((rule) {
            final isToday = rule.dayNumber == status.claimDay;
            final isClaimed = rule.dayNumber <= claimedThrough;
            return Expanded(
              child: _DayCell(
                rule: rule,
                isToday: isToday,
                isClaimed: isClaimed,
                isLocked: !isClaimed && !isToday,
                isArabic: isArabic,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.rule,
    required this.isToday,
    required this.isClaimed,
    required this.isLocked,
    required this.isArabic,
  });

  final DailyRewardRule rule;
  final bool isToday;
  final bool isClaimed;
  final bool isLocked;
  final bool isArabic;

  String _fmtAmt(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    Color borderColor;
    Color bg;
    if (isToday) {
      borderColor = const Color(0xFFF0C15A);
      bg = const Color(0xFFF0C15A).withValues(alpha: 0.1);
    } else if (isClaimed) {
      borderColor = const Color(0xFF2ECC71).withValues(alpha: 0.5);
      bg = const Color(0xFF2ECC71).withValues(alpha: 0.06);
    } else {
      borderColor = const Color(0xFF2D1A4A);
      bg = const Color(0xFF12091D);
    }
    final isDiamond = rule.rewardType == 'diamonds';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isToday ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text(
              isArabic ? 'ي${rule.dayNumber}' : 'D${rule.dayNumber}',
              style: TextStyle(
                color: isToday
                    ? const Color(0xFFF0C15A)
                    : const Color(0xFF7A6890),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            isClaimed
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF2ECC71),
                    size: 18,
                  )
                : Icon(
                    isDiamond
                        ? Icons.diamond_rounded
                        : Icons.monetization_on_rounded,
                    color: isToday
                        ? const Color(0xFFF0C15A)
                        : isLocked
                            ? const Color(0xFF4A3470)
                            : const Color(0xFFF0C15A).withValues(alpha: 0.5),
                    size: 16,
                  ),
            const SizedBox(height: 3),
            Text(
              _fmtAmt(rule.amount),
              style: TextStyle(
                color: isLocked && !isClaimed
                    ? const Color(0xFF4A3470)
                    : const Color(0xFFD8CFEA),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Check-in button
// ---------------------------------------------------------------------------

class _CheckinButton extends StatelessWidget {
  const _CheckinButton({
    required this.status,
    required this.claiming,
    required this.isArabic,
    required this.onCheckin,
  });

  final DailyRewardState status;
  final bool claiming;
  final bool isArabic;
  final VoidCallback onCheckin;

  String _fmtReward(DailyRewardRule? r, bool ar) {
    if (r == null) return '';
    final isDiamond = r.rewardType == 'diamonds';
    final amt = r.amount >= 1000
        ? '${(r.amount / 1000).toStringAsFixed(r.amount % 1000 == 0 ? 0 : 1)}K'
        : '${r.amount}';
    return ar
        ? '+$amt ${isDiamond ? 'ماسة' : 'عملة'}'
        : '+$amt ${isDiamond ? 'diamonds' : 'coins'}';
  }

  @override
  Widget build(BuildContext context) {
    final todayRule = status.ruleForDay(status.claimDay);

    if (status.claimedToday) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF2ECC71).withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF2ECC71),
              size: 32,
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'تم تسجيل حضورك اليوم ✓'
                  : 'Already checked in today ✓',
              style: const TextStyle(
                color: Color(0xFF2ECC71),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (todayRule != null)
              Text(
                _fmtReward(todayRule, isArabic),
                style: TextStyle(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
          ],
        ),
      );
    }

    if (!status.enabled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF2D1A4A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF4A3470)),
        ),
        child: Text(
          isArabic ? 'الميزة غير متاحة حالياً' : 'Feature not available',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF7A6890),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (todayRule != null) ...[
          Text(
            isArabic ? 'مكافأة اليوم' : "Today's reward",
            style: const TextStyle(color: Color(0xFF7A6890), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                todayRule.rewardType == 'diamonds'
                    ? Icons.diamond_rounded
                    : Icons.monetization_on_rounded,
                color: todayRule.rewardType == 'diamonds'
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFFF0C15A),
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                _fmtReward(todayRule, isArabic),
                style: const TextStyle(
                  color: Color(0xFFF0C15A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: claiming ? null : onCheckin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF0C15A),
              foregroundColor: const Color(0xFF160B26),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
              disabledBackgroundColor:
                  const Color(0xFFF0C15A).withValues(alpha: 0.4),
            ),
            child: claiming
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF160B26),
                    ),
                  )
                : Text(
                    isArabic ? 'تسجيل الحضور' : 'Check In',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
