// Models for Srood Loto — all data comes from server RPCs.

class LotoSettings {
  const LotoSettings({
    required this.isEnabled,
    required this.ticketPriceCoins,
    required this.numberMin,
    required this.numberMax,
    required this.numbersPerTicket,
    required this.match3Prize,
    required this.match4Prize,
    required this.match5Prize,
    required this.match6Prize,
    required this.progressiveJackpotEnabled,
    required this.jackpotPoolCoins,
    required this.responsibleNoticeAr,
    required this.responsibleNoticeEn,
  });

  final bool isEnabled;
  final int ticketPriceCoins;
  final int numberMin;
  final int numberMax;
  final int numbersPerTicket;
  final int match3Prize;
  final int match4Prize;
  final int match5Prize;
  final int match6Prize;
  final bool progressiveJackpotEnabled;
  final int jackpotPoolCoins;
  final String responsibleNoticeAr;
  final String responsibleNoticeEn;

  factory LotoSettings.fromJson(Map<String, dynamic> j) => LotoSettings(
        isEnabled:                  j['is_enabled'] as bool? ?? true,
        ticketPriceCoins:           (j['ticket_price_coins'] as num?)?.toInt() ?? 20000,
        numberMin:                  (j['number_min'] as num?)?.toInt() ?? 1,
        numberMax:                  (j['number_max'] as num?)?.toInt() ?? 42,
        numbersPerTicket:           (j['numbers_per_ticket'] as num?)?.toInt() ?? 6,
        match3Prize:                (j['match_3_prize'] as num?)?.toInt() ?? 20000,
        match4Prize:                (j['match_4_prize'] as num?)?.toInt() ?? 100000,
        match5Prize:                (j['match_5_prize'] as num?)?.toInt() ?? 1000000,
        match6Prize:                (j['match_6_prize'] as num?)?.toInt() ?? 10000000,
        progressiveJackpotEnabled:  j['progressive_jackpot_enabled'] as bool? ?? false,
        jackpotPoolCoins:           (j['jackpot_pool_coins'] as num?)?.toInt() ?? 0,
        responsibleNoticeAr:        j['responsible_notice_ar'] as String? ?? '',
        responsibleNoticeEn:        j['responsible_notice_en'] as String? ?? '',
      );

  int prizeForMatch(int matched) {
    switch (matched) {
      case 3:  return match3Prize;
      case 4:  return match4Prize;
      case 5:  return match5Prize;
      case 6:  return progressiveJackpotEnabled ? jackpotPoolCoins : match6Prize;
      default: return 0;
    }
  }
}

class LotoDraw {
  const LotoDraw({
    required this.id,
    required this.drawNumber,
    required this.status,
    required this.opensAt,
    required this.closesAt,
    required this.drawAt,
    this.winningNumbers,
    required this.totalTickets,
    required this.totalSalesCoins,
    required this.jackpotPoolBefore,
  });

  final String id;
  final int drawNumber;
  final String status; // open | locked | drawn | settled | voided
  final DateTime opensAt;
  final DateTime closesAt;
  final DateTime drawAt;
  final List<int>? winningNumbers;
  final int totalTickets;
  final int totalSalesCoins;
  final int jackpotPoolBefore;

  bool get isOpen     => status == 'open';
  bool get isSettled  => status == 'settled';
  bool get isVoided   => status == 'voided';
  bool get acceptsTickets => status == 'open' && closesAt.isAfter(DateTime.now());

  factory LotoDraw.fromJson(Map<String, dynamic> j) => LotoDraw(
        id:               j['id'] as String,
        drawNumber:       (j['draw_number'] as num).toInt(),
        status:           j['status'] as String? ?? 'open',
        opensAt:          DateTime.parse(j['opens_at'] as String),
        closesAt:         DateTime.parse(j['closes_at'] as String),
        drawAt:           DateTime.parse(j['draw_at'] as String),
        winningNumbers:   (j['winning_numbers'] as List<dynamic>?)
                            ?.map((e) => (e as num).toInt()).toList(),
        totalTickets:     (j['total_tickets'] as num?)?.toInt() ?? 0,
        totalSalesCoins:  (j['total_sales_coins'] as num?)?.toInt() ?? 0,
        jackpotPoolBefore:(j['jackpot_pool_before'] as num?)?.toInt() ?? 0,
      );
}

class LotoTicket {
  const LotoTicket({
    required this.id,
    required this.drawId,
    required this.numbers,
    required this.ticketPriceCoins,
    required this.status,
    required this.matchedCount,
    required this.prizeCoins,
    required this.createdAt,
    this.drawNumber,
    this.drawAt,
    this.winningNumbers,
  });

  final String id;
  final String drawId;
  final List<int> numbers;
  final int ticketPriceCoins;
  final String status; // active | won | lost | refunded | voided
  final int matchedCount;
  final int prizeCoins;
  final DateTime createdAt;
  // Present in recent-draws response
  final int? drawNumber;
  final DateTime? drawAt;
  final List<int>? winningNumbers;

  bool get isWon      => status == 'won';
  bool get isActive   => status == 'active';

  factory LotoTicket.fromJson(Map<String, dynamic> j) => LotoTicket(
        id:               j['id'] as String,
        drawId:           j['draw_id'] as String? ?? '',
        numbers:          (j['numbers'] as List<dynamic>)
                            .map((e) => (e as num).toInt()).toList(),
        ticketPriceCoins: (j['ticket_price_coins'] as num?)?.toInt() ?? 20000,
        status:           j['status'] as String? ?? 'active',
        matchedCount:     (j['matched_count'] as num?)?.toInt() ?? 0,
        prizeCoins:       (j['prize_coins'] as num?)?.toInt() ?? 0,
        createdAt:        DateTime.parse(j['created_at'] as String),
        drawNumber:       (j['draw_number'] as num?)?.toInt(),
        drawAt:           j['draw_at'] != null ? DateTime.parse(j['draw_at'] as String) : null,
        winningNumbers:   (j['winning_numbers'] as List<dynamic>?)
                            ?.map((e) => (e as num).toInt()).toList(),
      );
}

class LotoCurrentDraw {
  const LotoCurrentDraw({
    this.draw,
    required this.settings,
    required this.myTickets,
    required this.userBalance,
    required this.secondsUntilDraw,
    required this.secondsUntilClose,
  });

  final LotoDraw? draw;
  final LotoSettings settings;
  final List<LotoTicket> myTickets;
  final int userBalance;
  final int secondsUntilDraw;
  final int secondsUntilClose;

  factory LotoCurrentDraw.fromJson(Map<String, dynamic> j) => LotoCurrentDraw(
        draw:              j['draw'] != null
                           ? LotoDraw.fromJson(j['draw'] as Map<String, dynamic>)
                           : null,
        settings:          LotoSettings.fromJson(j['settings'] as Map<String, dynamic>),
        myTickets:         (j['my_tickets'] as List<dynamic>? ?? [])
                             .map((e) => LotoTicket.fromJson(e as Map<String, dynamic>))
                             .toList(),
        userBalance:       (j['user_balance'] as num?)?.toInt() ?? 0,
        secondsUntilDraw:  (j['seconds_until_draw'] as num?)?.toInt() ?? 0,
        secondsUntilClose: (j['seconds_until_close'] as num?)?.toInt() ?? 0,
      );
}

class LotoRecentDraw {
  const LotoRecentDraw({
    required this.id,
    required this.drawNumber,
    required this.status,
    required this.drawAt,
    this.winningNumbers,
    required this.totalTickets,
    required this.totalSalesCoins,
    required this.totalPayoutCoins,
    this.settledAt,
    this.myTicket,
  });

  final String id;
  final int drawNumber;
  final String status;
  final DateTime drawAt;
  final List<int>? winningNumbers;
  final int totalTickets;
  final int totalSalesCoins;
  final int totalPayoutCoins;
  final DateTime? settledAt;
  final LotoTicket? myTicket;

  factory LotoRecentDraw.fromJson(Map<String, dynamic> j) => LotoRecentDraw(
        id:               j['id'] as String,
        drawNumber:       (j['draw_number'] as num).toInt(),
        status:           j['status'] as String? ?? 'settled',
        drawAt:           DateTime.parse(j['draw_at'] as String),
        winningNumbers:   (j['winning_numbers'] as List<dynamic>?)
                            ?.map((e) => (e as num).toInt()).toList(),
        totalTickets:     (j['total_tickets'] as num?)?.toInt() ?? 0,
        totalSalesCoins:  (j['total_sales_coins'] as num?)?.toInt() ?? 0,
        totalPayoutCoins: (j['total_payout_coins'] as num?)?.toInt() ?? 0,
        settledAt:        j['settled_at'] != null
                            ? DateTime.parse(j['settled_at'] as String) : null,
        myTicket:         j['my_ticket'] != null
                            ? LotoTicket.fromJson({
                                ...(j['my_ticket'] as Map<String, dynamic>),
                                'draw_id': j['id'],
                                'ticket_price_coins': 20000,
                                'created_at': j['draw_at'],
                              })
                            : null,
      );
}
