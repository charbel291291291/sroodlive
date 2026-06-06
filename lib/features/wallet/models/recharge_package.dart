class RechargePackage {
  const RechargePackage({
    required this.id,
    required this.title,
    required this.priceUsd,
    required this.coinsAmount,
    required this.bonusCoins,
    required this.totalCoins,
    required this.isActive,
    required this.isFeatured,
    required this.sortOrder,
  });

  final String id;
  final String title;
  final double priceUsd;
  final int coinsAmount;
  final int bonusCoins;
  final int totalCoins;
  final bool isActive;
  final bool isFeatured;
  final int sortOrder;

  factory RechargePackage.fromJson(Map<String, dynamic> json) {
    return RechargePackage(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Recharge',
      priceUsd: _doubleValue(json['price_usd']),
      coinsAmount: _intValue(json['coins_amount']),
      bonusCoins: _intValue(json['bonus_coins']),
      totalCoins: _intValue(json['total_coins']),
      isActive: json['is_active'] != false,
      isFeatured: json['is_featured'] == true,
      sortOrder: _intValue(json['sort_order']),
    );
  }

  static List<RechargePackage> fallbackPackages() {
    const rate = 10000;
    const prices = [1, 2, 5, 10, 20, 50, 100];

    return [
      for (final price in prices)
        RechargePackage(
          id: 'fallback_$price',
          title: '\$$price',
          priceUsd: price.toDouble(),
          coinsAmount: price * rate,
          bonusCoins: 0,
          totalCoins: price * rate,
          isActive: true,
          isFeatured: price == 5,
          sortOrder: price,
        ),
    ];
  }

  static int _intValue(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _doubleValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
