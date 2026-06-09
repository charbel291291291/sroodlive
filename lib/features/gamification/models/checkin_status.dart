class CheckinReward {
  const CheckinReward({
    required this.day,
    required this.rewardType,
    required this.rewardAmount,
  });

  factory CheckinReward.fromJson(Map<String, dynamic> json) => CheckinReward(
        day: (json['day'] as num?)?.toInt() ?? 1,
        rewardType: json['reward_type']?.toString() ?? 'coins',
        rewardAmount: (json['reward_amount'] as num?)?.toInt() ?? 0,
      );

  final int day;
  final String rewardType;
  final int rewardAmount;

  bool get isDiamond => rewardType == 'diamonds';
}

class CheckinStatus {
  const CheckinStatus({
    required this.todayClaimed,
    required this.streak,
    required this.streakDay,
    required this.last7Dates,
    required this.rewardSchedule,
  });

  factory CheckinStatus.fromJson(Map<String, dynamic> json) {
    final scheduleRaw = json['reward_schedule'] as List<dynamic>? ?? [];
    final datesRaw = json['last_7_dates'] as List<dynamic>? ?? [];

    return CheckinStatus(
      todayClaimed: json['today_claimed'] == true,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      streakDay: (json['streak_day'] as num?)?.toInt() ?? 1,
      last7Dates: datesRaw.map((e) => e.toString()).toList(),
      rewardSchedule: scheduleRaw
          .map((e) => CheckinReward.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final bool todayClaimed;
  final int streak;
  final int streakDay;
  final List<String> last7Dates;
  final List<CheckinReward> rewardSchedule;

  CheckinReward? get todayReward {
    final idx = rewardSchedule.indexWhere((r) => r.day == streakDay);
    return idx >= 0 ? rewardSchedule[idx] : null;
  }

  bool isDateClaimed(String dateStr) => last7Dates.contains(dateStr);
}
