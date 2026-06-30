import 'package:supabase_flutter/supabase_flutter.dart';

bool isMagicSroodRealtimeUnhealthy(RealtimeSubscribeStatus status) {
  return status == RealtimeSubscribeStatus.channelError ||
      status == RealtimeSubscribeStatus.closed ||
      status == RealtimeSubscribeStatus.timedOut;
}

bool shouldRollbackMagicSroodBalance({
  required int balanceVersionAtStart,
  required int currentBalanceVersion,
}) {
  return balanceVersionAtStart == currentBalanceVersion;
}

Map<String, int> reconcileMagicSroodVisibleBets({
  required String? currentRoundId,
  required String nextRoundId,
  required Map<String, int> currentBets,
  Map<String, int>? serverBets,
}) {
  if (currentRoundId == nextRoundId) {
    return Map<String, int>.of(serverBets ?? currentBets);
  }
  return Map<String, int>.of(serverBets ?? const {});
}

String? magicSroodBetRejectionMessage(String error, {required bool isArabic}) {
  final value = error.toLowerCase();
  if (value.contains('insufficient') ||
      value.contains('not enough') ||
      value.contains('balance')) {
    return isArabic ? 'رصيد غير كافٍ' : 'Insufficient coins';
  }
  if (value.contains('betting_closed') ||
      value.contains('round_not_found') ||
      value.contains('no active round')) {
    return isArabic ? 'انتهى وقت الرهان' : 'Betting window has closed';
  }
  if (value.contains('invalid_food')) {
    return isArabic
        ? 'هذا الفريق غير متاح. حدّث اللعبة وحاول مجدداً'
        : 'This team is unavailable. Please refresh the game.';
  }
  if (value.contains('invalid_bet_amount') ||
      value.contains('invalid_amount') ||
      value.contains('min_bet') ||
      value.contains('max_bet')) {
    return isArabic ? 'مبلغ الرهان غير صالح' : 'Invalid bet amount';
  }
  return null;
}
