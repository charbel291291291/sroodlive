abstract final class CoinConstants {
  /// 1 USD = 20,000 coins
  static const int coinsPerUsd = 20000;

  /// Minimum recharge: 1 USD
  static const int minimumRechargeCoins = 20000;

  /// Maximum recharge: 100 USD base + up to 25% bonus = 2,500,000 coins
  static const int maximumRechargeCoins = 2500000;

  /// Admin adjustment guardrail: 2,000 USD
  static const int maximumAdminAdjustment = 40000000;

  // ── Cashout (diamonds → USD) ────────────────────────────────────────────
  // Diamonds are earned 1:1 with gift coin value, so the gross rate matches
  // the coin rate. The split below is enforced SQL-side in
  // request_withdrawal(); these constants exist only for UI display.

  /// 20,000 diamonds = 1 USD gross
  static const int diamondsPerUsd = 20000;

  /// Minimum withdrawal: 5 USD gross
  static const int minimumWithdrawalDiamonds = 100000;

  /// Host share when the host belongs to an agency
  static const double hostShareWithAgency = 0.85;

  /// Agency owner share
  static const double agencyShare = 0.05;

  /// Host share when the host has no agency
  static const double hostShareNoAgency = 0.88;
}
