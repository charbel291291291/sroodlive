import 'package:flutter/material.dart';

class RoomGift {
  const RoomGift({
    required this.id,
    required this.code,
    required this.name,
    required this.arabicName,
    required this.priceCoins,
    required this.icon,
    required this.sortOrder,
  });

  final String id;
  final String code;
  final String name;
  final String arabicName;
  final int priceCoins;
  final String icon;
  final int sortOrder;

  factory RoomGift.fromJson(Map<String, dynamic> json) {
    return RoomGift(
      id: json['id'].toString(),
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Gift',
      arabicName: json['arabic_name']?.toString() ?? 'هدية',
      priceCoins: (json['price_coins'] as num?)?.toInt() ?? 0,
      icon: json['icon']?.toString() ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  // Returns a local asset path for gifts that have bespoke PNG icons,
  // or null for gifts that use the network Twemoji image.
  String? get localAssetPath {
    return switch (code.toLowerCase()) {
      'baalbek_temple' => 'assets/gifts/baalbek.png',
      'golden_lion'    => 'assets/gifts/lion.png',
      'odrob'          => 'assets/gifts/odrob.png',
      _                => null,
    };
  }

  String get artwork {
    final trimmedIcon = icon.trim();

    if (trimmedIcon.isNotEmpty &&
        !trimmedIcon.startsWith('Icons.') &&
        !imageUrl.startsWith('http')) {
      return trimmedIcon;
    }

    return switch (code.toLowerCase()) {
      'rose'   => '🌹',
      'star'   => '⭐',
      'crown'  => '👑',
      'rocket' => '🚀',
      _        => '🎁',
    };
  }

  String get imageUrl {
    final trimmedIcon = icon.trim();

    if (trimmedIcon.startsWith('http://') ||
        trimmedIcon.startsWith('https://')) {
      return trimmedIcon;
    }

    return switch (code.toLowerCase()) {
      'rose' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f339.png',
      'star' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2b50.png',
      'crown' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f451.png',
      'rocket' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f680.png',
      'diamond' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f48e.png',
      'tiger' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f981.png',
      'treasure' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3c6.png',
      'lucky_bag' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f381.png',
      'slingshot' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3af.png',
      'motorcycle' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3cd.png',
      'dragon' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f409.png',
      'castle' =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3f0.png',
      _ =>
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f381.png',
    };
  }

  String get categoryKey {
    return switch (code.toLowerCase()) {
      'treasure' || 'football' || 'country'           => 'event',
      'lucky_bag' || 'slingshot'                      => 'lucky',
      'tiger' || 'dragon' || 'castle' ||
      'golden_lion' || 'baalbek_temple' || 'odrob'    => 'vip',
      _                                               => 'hot',
    };
  }

  IconData get materialIcon {
    return switch (code.toLowerCase()) {
      'rose'           => Icons.local_florist_rounded,
      'star'           => Icons.star_rounded,
      'crown'          => Icons.workspace_premium_rounded,
      'rocket'         => Icons.rocket_launch_rounded,
      'golden_lion'    => Icons.emoji_nature_rounded,
      'baalbek_temple' => Icons.account_balance_rounded,
      'odrob'          => Icons.bolt_rounded,
      _                => Icons.card_giftcard_rounded,
    };
  }
}
