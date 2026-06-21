// Daily reward data models (mirror get_daily_reward_state RPC output).

class DailyRewardRule {
  const DailyRewardRule({
    required this.dayNumber,
    required this.enabled,
    required this.rewardType,
    required this.title,
    this.description,
    this.amount = 0,
    this.durationDays,
    this.imageUrl,
  });

  final int dayNumber;
  final bool enabled;
  final String rewardType;
  final String title;
  final String? description;
  final int amount;
  final int? durationDays;
  final String? imageUrl;

  factory DailyRewardRule.fromJson(Map<String, dynamic> j) => DailyRewardRule(
    dayNumber: _int(j['day_number'], 1),
    enabled: j['enabled'] == true,
    rewardType: j['reward_type']?.toString() ?? 'coins',
    title: j['title']?.toString() ?? 'Day ${_int(j['day_number'], 1)}',
    description: j['description']?.toString(),
    amount: _int(j['amount']),
    durationDays: _nullInt(j['duration_days']),
    imageUrl: j['image_url']?.toString(),
  );
}

class DailyRewardState {
  const DailyRewardState({
    required this.enabled,
    required this.popupEnabled,
    required this.canClaimToday,
    required this.claimedToday,
    required this.claimDay,
    required this.currentDay,
    required this.streakCount,
    required this.rules,
    this.lastClaimDate,
    this.nextClaimDate,
  });

  final bool enabled;
  final bool popupEnabled;
  final bool canClaimToday;
  final bool claimedToday;
  final int claimDay; // day claimable today (or claimed today)
  final int currentDay; // last claimed day
  final int streakCount;
  final List<DailyRewardRule> rules;
  final String? lastClaimDate;
  final String? nextClaimDate;

  DailyRewardRule? ruleForDay(int day) {
    for (final r in rules) {
      if (r.dayNumber == day) return r;
    }
    return null;
  }

  factory DailyRewardState.fromJson(Map<String, dynamic> j) => DailyRewardState(
    enabled: j['enabled'] == true,
    popupEnabled: j['popup_enabled'] == true,
    canClaimToday: j['can_claim_today'] == true,
    claimedToday: j['claimed_today'] == true,
    claimDay: _int(j['claim_day'], 1),
    currentDay: _int(j['current_day']),
    streakCount: _int(j['streak_count']),
    rules: ((j['rules'] as List<dynamic>?) ?? const [])
        .map((e) => DailyRewardRule.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    lastClaimDate: j['last_claim_date']?.toString(),
    nextClaimDate: j['next_claim_date']?.toString(),
  );
}

class DailyRewardClaimResult {
  const DailyRewardClaimResult({
    required this.claimedDay,
    required this.rewardType,
    required this.title,
    required this.amount,
    this.durationDays,
    this.streakCount = 0,
  });

  final int claimedDay;
  final String rewardType;
  final String title;
  final int amount;
  final int? durationDays;
  final int streakCount;

  factory DailyRewardClaimResult.fromJson(Map<String, dynamic> j) =>
      DailyRewardClaimResult(
        claimedDay: _int(j['claimed_day'], 1),
        rewardType: j['reward_type']?.toString() ?? 'coins',
        title: j['title']?.toString() ?? '',
        amount: _int(j['amount']),
        durationDays: _nullInt(j['duration_days']),
        streakCount: _int(j['streak_count']),
      );
}

int _int(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? _nullInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
