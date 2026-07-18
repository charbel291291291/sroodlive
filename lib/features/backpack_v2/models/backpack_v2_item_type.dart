/// Mirrors the `item_type` CHECK constraint on `public.backpack_catalog_items`
/// (20261120000000_backpack_v2_schema.sql). `unknown` is not a database value —
/// it is the safe fallback for a value this client build does not recognise
/// yet (e.g. a newer catalog row added after this app version shipped).
enum BackpackV2ItemType {
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

  const BackpackV2ItemType(this.value);

  final String value;

  static BackpackV2ItemType fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return unknown;
  }
}
