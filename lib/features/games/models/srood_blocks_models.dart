class BlocksDailyStatus {
  const BlocksDailyStatus({
    required this.freePlays,
    required this.playsUsed,
    required this.xpToday,
    required this.xpCap,
    required this.coinsBalance,
    required this.extraPlayCost,
  });

  factory BlocksDailyStatus.fromJson(Map<String, dynamic> j) =>
      BlocksDailyStatus(
        freePlays:     (j['free_plays']     as num).toInt(),
        playsUsed:     (j['plays_used']     as num).toInt(),
        xpToday:       (j['xp_today']       as num).toInt(),
        xpCap:         (j['xp_cap']         as num).toInt(),
        coinsBalance:  (j['coins_balance']  as num).toInt(),
        extraPlayCost: (j['extra_play_cost'] as num).toInt(),
      );

  final int freePlays;
  final int playsUsed;
  final int xpToday;
  final int xpCap;
  final int coinsBalance;
  final int extraPlayCost;

  int get playsRemaining => freePlays - playsUsed;
  bool get hasFreePlay   => playsRemaining > 0;
  bool get canBuyPlay    => coinsBalance >= extraPlayCost;
}

class BlocksLeaderboardEntry {
  const BlocksLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.bestScore,
    required this.totalLines,
  });

  factory BlocksLeaderboardEntry.fromJson(Map<String, dynamic> j) =>
      BlocksLeaderboardEntry(
        rank:        (j['rank']        as num).toInt(),
        userId:      j['user_id']      as String,
        displayName: j['display_name'] as String? ?? 'Player',
        avatarUrl:   j['avatar_url']   as String?,
        bestScore:   (j['best_score']  as num).toInt(),
        totalLines:  (j['total_lines'] as num).toInt(),
      );

  final int     rank;
  final String  userId;
  final String  displayName;
  final String? avatarUrl;
  final int     bestScore;
  final int     totalLines;
}

class BlocksSubmitResult {
  const BlocksSubmitResult({
    required this.xpEarned,
    required this.score,
  });

  factory BlocksSubmitResult.fromJson(Map<String, dynamic> j) =>
      BlocksSubmitResult(
        xpEarned: (j['xp_earned'] as num).toInt(),
        score:    (j['score']     as num).toInt(),
      );

  final int xpEarned;
  final int score;
}
