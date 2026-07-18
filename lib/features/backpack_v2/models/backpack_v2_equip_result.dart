import 'backpack_v2_slot_type.dart';

/// Parsed result of `equip_backpack_item_v2`, e.g.
/// `{"equipped": true, "slot_type": "avatar_frame", "code": "gold_frame"}`.
class BackpackV2EquipResult {
  const BackpackV2EquipResult({required this.slotType, required this.code});

  final BackpackV2SlotType slotType;
  final String code;

  factory BackpackV2EquipResult.fromJson(Map<String, dynamic> json) {
    if (json['equipped'] != true) {
      throw const FormatException('backpack_v2_equip_result_not_confirmed');
    }
    return BackpackV2EquipResult(
      slotType: BackpackV2SlotType.fromValue(json['slot_type']?.toString()),
      code: json['code']?.toString() ?? '',
    );
  }
}
