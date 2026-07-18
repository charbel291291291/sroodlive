/// Mirrors the `slot_type` CHECK constraint on `public.user_equipped_items`
/// (same 9 values as [BackpackV2ItemType] by construction, but modeled as a
/// distinct type: an item's `item_type` describes what it *is* in the
/// catalog, `slot_type` describes what render slot it *occupies once
/// equipped*). `unknown` is a safe client-side fallback, not a database value.
enum BackpackV2SlotType {
  avatarFrame('avatar_frame'),
  profileFrame('profile_frame'),
  entryEffect('entry_effect'),
  badge('badge'),
  nameColor('name_color'),
  roomBackground('room_background'),
  chatEffect('chat_effect'),
  micEffect('mic_effect'),
  vehicle('vehicle'),
  unknown('unknown');

  const BackpackV2SlotType(this.value);

  final String value;

  static BackpackV2SlotType fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return unknown;
  }
}
