/// Mirrors the `source_type` CHECK constraint on `public.user_backpack_items`
/// (20261120000000_backpack_v2_schema.sql).
enum BackpackV2OwnershipSource {
  purchase('purchase'),
  adminGrant('admin_grant'),
  eventReward('event_reward'),
  vipReward('vip_reward'),
  legacyMigration('legacy_migration'),
  unknown('unknown');

  const BackpackV2OwnershipSource(this.value);

  final String value;

  static BackpackV2OwnershipSource fromValue(String? value) {
    for (final source in values) {
      if (source.value == value) return source;
    }
    return unknown;
  }
}
