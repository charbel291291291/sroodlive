class StoreItem {
  const StoreItem({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.description,
    required this.descriptionAr,
    required this.itemType,
    required this.priceCoins,
    required this.priceDiamonds,
    required this.metadata,
    required this.isActive,
    required this.sortOrder,
    required this.owned,
  });

  factory StoreItem.fromJson(Map<String, dynamic> json) => StoreItem(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    nameAr: json['name_ar']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    descriptionAr: json['description_ar']?.toString() ?? '',
    itemType: json['item_type']?.toString() ?? '',
    priceCoins: (json['price_coins'] as num?)?.toInt() ?? 0,
    priceDiamonds: (json['price_diamonds'] as num?)?.toInt() ?? 0,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    isActive: json['is_active'] == true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    owned: json['owned'] == true,
  );

  final String id;
  final String name;
  final String nameAr;
  final String description;
  final String descriptionAr;
  final String itemType;
  final int priceCoins;
  final int priceDiamonds;
  final Map<String, dynamic> metadata;
  final bool isActive;
  final int sortOrder;
  final bool owned;

  bool get isFrame => itemType == 'avatar_frame';
  bool get isBadge => itemType == 'badge';
  String? get frameKey => metadata['frame_key'] as String?;
  String? get badgeKey => metadata['badge_key'] as String?;

  String localName(bool isArabic) =>
      isArabic && nameAr.isNotEmpty ? nameAr : name;
  String localDescription(bool isArabic) =>
      isArabic && descriptionAr.isNotEmpty ? descriptionAr : description;
}
