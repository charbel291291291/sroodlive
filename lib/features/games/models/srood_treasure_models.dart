class TreasureSettings {
  const TreasureSettings({
    required this.isEnabled,
    required this.entryFeeCoins,
    required this.maxPrizeCoins,
    required this.prizeAmounts,
  });

  final bool isEnabled;
  final int entryFeeCoins;
  final int maxPrizeCoins;
  final List<int> prizeAmounts;

  factory TreasureSettings.fromJson(Map<String, dynamic> j) => TreasureSettings(
    isEnabled:      j['is_enabled']      as bool?  ?? true,
    entryFeeCoins:  (j['entry_fee_coins'] as num?)?.toInt() ?? 20000,
    maxPrizeCoins:  (j['max_prize_coins'] as num?)?.toInt() ?? 1000000,
    prizeAmounts:   (j['prize_amounts']   as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
  );

  static const TreasureSettings defaults = TreasureSettings(
    isEnabled:     true,
    entryFeeCoins: 20000,
    maxPrizeCoins: 1000000,
    prizeAmounts: [
      1000, 2000, 5000, 10000, 25000, 50000,
      75000, 100000, 150000, 200000, 250000, 300000,
      400000, 500000, 750000, 1000000,
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class TreasureBox {
  const TreasureBox({
    required this.boxNumber,
    required this.isPersonal,
    required this.isOpened,
    this.prizeCoins,
  });

  final int boxNumber;
  final bool isPersonal;
  final bool isOpened;
  final int? prizeCoins;

  factory TreasureBox.fromJson(Map<String, dynamic> j) => TreasureBox(
    boxNumber:  (j['box_number']  as num).toInt(),
    isPersonal: j['is_personal']  as bool? ?? false,
    isOpened:   j['is_opened']    as bool? ?? false,
    prizeCoins: (j['prize_coins'] as num?)?.toInt(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class TreasureGame {
  const TreasureGame({
    required this.id,
    required this.status,
    required this.roundNumber,
    required this.boxesOpened,
    required this.entryFeeCoins,
    required this.boxes,
    required this.createdAt,
    this.personalBoxNumber,
    this.personalBoxPrize,
    this.currentOfferCoins,
    this.finalPayoutCoins,
    this.payoutType,
  });

  final String id;
  final String status;
  final int? personalBoxNumber;
  final int? personalBoxPrize;
  final int? currentOfferCoins;
  final int roundNumber;
  final int boxesOpened;
  final int entryFeeCoins;
  final int? finalPayoutCoins;
  final String? payoutType;
  final List<TreasureBox> boxes;
  final DateTime createdAt;

  bool get isSelecting   => status == 'selecting';
  bool get isPlaying     => status == 'playing';
  bool get isDealOffered => status == 'deal_offered';
  bool get isCompleted   => status == 'completed';
  bool get isAbandoned   => status == 'abandoned';

  // True when all non-personal boxes are opened (final decision round).
  bool get isFinalRound  => boxesOpened >= 15;

  // How many more boxes to open before the next offer.
  int get boxesUntilNextOffer {
    if (boxesOpened < 6)  return 6 - boxesOpened;
    if (boxesOpened < 11) return 11 - boxesOpened;
    return 15 - boxesOpened;
  }

  factory TreasureGame.fromJson(Map<String, dynamic> j) => TreasureGame(
    id:                  j['id']                 as String,
    status:              j['status']              as String,
    personalBoxNumber:   (j['personal_box_number'] as num?)?.toInt(),
    personalBoxPrize:    (j['personal_box_prize']  as num?)?.toInt(),
    currentOfferCoins:   (j['current_offer_coins'] as num?)?.toInt(),
    roundNumber:         (j['round_number']        as num?)?.toInt() ?? 0,
    boxesOpened:         (j['boxes_opened']        as num?)?.toInt() ?? 0,
    entryFeeCoins:       (j['entry_fee_coins']     as num?)?.toInt() ?? 20000,
    finalPayoutCoins:    (j['final_payout_coins']  as num?)?.toInt(),
    payoutType:          j['payout_type']          as String?,
    boxes:               (j['boxes'] as List<dynamic>? ?? [])
        .map((b) => TreasureBox.fromJson(b as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class TreasureState {
  const TreasureState({
    required this.userBalance,
    required this.settings,
    this.currentGame,
  });

  final TreasureGame? currentGame;
  final int userBalance;
  final TreasureSettings settings;

  factory TreasureState.fromJson(Map<String, dynamic> j) => TreasureState(
    currentGame:  j['current_game'] != null
        ? TreasureGame.fromJson(j['current_game'] as Map<String, dynamic>)
        : null,
    userBalance:  (j['user_balance'] as num?)?.toInt() ?? 0,
    settings:     j['settings'] != null
        ? TreasureSettings.fromJson(j['settings'] as Map<String, dynamic>)
        : TreasureSettings.defaults,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class TreasureOpenResult {
  const TreasureOpenResult({
    required this.openedBoxNumber,
    required this.openedPrizeCoins,
    required this.roundComplete,
    required this.gameStatus,
    this.newOfferCoins,
  });

  final int openedBoxNumber;
  final int openedPrizeCoins;
  final int? newOfferCoins;
  final bool roundComplete;
  final String gameStatus;

  factory TreasureOpenResult.fromJson(Map<String, dynamic> j) =>
      TreasureOpenResult(
        openedBoxNumber:  (j['opened_box_number']  as num).toInt(),
        openedPrizeCoins: (j['opened_prize_coins'] as num).toInt(),
        newOfferCoins:    (j['new_offer_coins']    as num?)?.toInt(),
        roundComplete:    j['round_complete']      as bool? ?? false,
        gameStatus:       j['game_status']         as String,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class TreasureActionResult {
  const TreasureActionResult({
    required this.payoutCoins,
    required this.payoutType,
    required this.newBalance,
    this.personalBoxPrize,
  });

  final int payoutCoins;
  final String payoutType; // 'offer' | 'box'
  final int newBalance;
  final int? personalBoxPrize;

  factory TreasureActionResult.fromJson(Map<String, dynamic> j) =>
      TreasureActionResult(
        payoutCoins:      (j['payout_coins']       as num).toInt(),
        payoutType:       j['payout_type']          as String,
        newBalance:       (j['new_balance']         as num?)?.toInt() ?? 0,
        personalBoxPrize: (j['personal_box_prize']  as num?)?.toInt(),
      );
}
