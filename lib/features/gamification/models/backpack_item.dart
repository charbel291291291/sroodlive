import 'store_item.dart';

class BackpackItem {
  const BackpackItem({
    required this.id,
    required this.itemId,
    required this.itemType,
    required this.equipped,
    required this.acquiredAt,
    required this.item,
  });

  factory BackpackItem.fromJson(Map<String, dynamic> json) => BackpackItem(
    id: json['id']?.toString() ?? '',
    itemId: json['item_id']?.toString() ?? '',
    itemType: json['item_type']?.toString() ?? '',
    equipped: json['equipped'] == true,
    acquiredAt:
        DateTime.tryParse(json['acquired_at']?.toString() ?? '') ??
        DateTime.now(),
    item: StoreItem.fromJson((json['item'] as Map<String, dynamic>?) ?? {}),
  );

  final String id;
  final String itemId;
  final String itemType;
  final bool equipped;
  final DateTime acquiredAt;
  final StoreItem item;

  bool get isFrame => itemType == 'avatar_frame';
  bool get isBadge => itemType == 'badge';
}
