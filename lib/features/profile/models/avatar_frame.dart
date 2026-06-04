class AvatarFrame {
  const AvatarFrame({
    required this.frameKey,
    required this.name,
    required this.category,
    required this.sortOrder,
    this.vipLevel,
    this.assetUrl,
  });

  final String frameKey;
  final String name;
  final String category;
  final int sortOrder;
  final int? vipLevel;
  final String? assetUrl;

  factory AvatarFrame.fromJson(Map<String, dynamic> json) {
    return AvatarFrame(
      frameKey: json['frame_key'].toString(),
      name: json['name']?.toString() ?? 'Frame',
      category: json['category']?.toString() ?? 'normal',
      vipLevel: (json['vip_level'] as num?)?.toInt(),
      assetUrl: json['asset_url']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  bool isUnlockedFor(int userVipLevel) {
    if (category != 'vip') {
      return true;
    }

    return userVipLevel >= (vipLevel ?? 1);
  }
}
