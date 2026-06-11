import 'package:flutter/material.dart';

import '../models/checkin_status.dart';
import '../services/gamification_service.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _service = const GamificationService();
  CheckinStatus? _status;
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
      final status = await _service.getCheckinStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
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

  Future<void> _checkin() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final res = await _service.claimDailyCheckin();
      if (!mounted) return;
      final rewardType = res['reward_type']?.toString() ?? 'coins';
      final rewardAmount = (res['reward_amount'] as num?)?.toInt() ?? 0;
      final isDiamond = rewardType == 'diamonds';

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
                widget.isArabic
                    ? '\u062a\u0645 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062d\u0636\u0648\u0631! +$rewardAmount ${isDiamond ? '\u0645\u0627\u0633\u0629' : '\u0639\u0645\u0644\u0629'}'
                    : 'Checked in! +$rewardAmount ${isDiamond ? 'diamonds' : 'coins'}',
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1B102A),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
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
      textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        Text(
          widget.isArabic
              ? '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062d\u0636\u0648\u0631'
              : 'Daily Check-in',
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
          _StreakCard(streak: s.streak, isArabic: widget.isArabic),
          const SizedBox(height: 20),
          _RewardCalendar(status: s, isArabic: widget.isArabic),
          const SizedBox(height: 28),
          _CheckinButton(
            todayClaimed: s.todayClaimed,
            claiming: _claiming,
            isArabic: widget.isArabic,
            todayReward: s.todayReward,
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
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _load,
          child: Text(
            widget.isArabic
                ? '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'
                : 'Retry',
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
                ? '\u064a\u0648\u0645 \u0645\u062a\u062a\u0627\u0644\u064a'
                : streak == 1
                ? 'day streak'
                : 'day streak',
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
  final CheckinStatus status;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isArabic
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          isArabic
              ? '\u0645\u0643\u0627\u0641\u0622\u062a \u0627\u0644\u0623\u0633\u0628\u0648\u0639'
              : 'Weekly Rewards',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: status.rewardSchedule.map((reward) {
            final isToday = reward.day == status.streakDay;
            final isClaimed =
                reward.day < status.streakDay ||
                (isToday && status.todayClaimed);

            return Expanded(
              child: _DayCell(
                reward: reward,
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
    required this.reward,
    required this.isToday,
    required this.isClaimed,
    required this.isLocked,
    required this.isArabic,
  });

  final CheckinReward reward;
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
              isArabic ? '\u064a${reward.day}' : 'D${reward.day}',
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
                    reward.isDiamond
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
              _fmtAmt(reward.rewardAmount),
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
    required this.todayClaimed,
    required this.claiming,
    required this.isArabic,
    required this.todayReward,
    required this.onCheckin,
  });

  final bool todayClaimed;
  final bool claiming;
  final bool isArabic;
  final CheckinReward? todayReward;
  final VoidCallback onCheckin;

  String _fmtReward(CheckinReward? r, bool ar) {
    if (r == null) return '';
    final isDiamond = r.isDiamond;
    final amt = r.rewardAmount >= 1000
        ? '${(r.rewardAmount / 1000).toStringAsFixed(r.rewardAmount % 1000 == 0 ? 0 : 1)}K'
        : '${r.rewardAmount}';
    if (ar) {
      return '+$amt ${isDiamond ? '\u0645\u0627\u0633\u0629' : '\u0639\u0645\u0644\u0629'}';
    }
    return '+$amt ${isDiamond ? 'diamonds' : 'coins'}';
  }

  @override
  Widget build(BuildContext context) {
    if (todayClaimed) {
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
                  ? '\u062a\u0645 \u062a\u0633\u062c\u064a\u0644 \u062d\u0636\u0648\u0631\u0643 \u0627\u0644\u064a\u0648\u0645 \u2713'
                  : 'Already checked in today \u2713',
              style: const TextStyle(
                color: Color(0xFF2ECC71),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (todayReward != null)
              Text(
                _fmtReward(todayReward, isArabic),
                style: TextStyle(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (todayReward != null) ...[
          Text(
            isArabic
                ? '\u0645\u0643\u0627\u0641\u0623\u0629 \u0627\u0644\u064a\u0648\u0645'
                : "Today's reward",
            style: const TextStyle(color: Color(0xFF7A6890), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                todayReward!.isDiamond
                    ? Icons.diamond_rounded
                    : Icons.monetization_on_rounded,
                color: todayReward!.isDiamond
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFFF0C15A),
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                _fmtReward(todayReward, isArabic),
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
              disabledBackgroundColor: const Color(
                0xFFF0C15A,
              ).withValues(alpha: 0.4),
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
                    isArabic
                        ? '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062d\u0636\u0648\u0631'
                        : 'Check In',
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
