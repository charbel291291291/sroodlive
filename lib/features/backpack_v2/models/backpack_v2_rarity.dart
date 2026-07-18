/// Mirrors the `rarity` CHECK constraint on `public.backpack_catalog_items`
/// (20261120000000_backpack_v2_schema.sql).
enum BackpackV2Rarity {
  common('common'),
  rare('rare'),
  epic('epic'),
  legendary('legendary'),
  mythic('mythic'),
  unknown('unknown');

  const BackpackV2Rarity(this.value);

  final String value;

  static BackpackV2Rarity fromValue(String? value) {
    for (final rarity in values) {
      if (rarity.value == value) return rarity;
    }
    return unknown;
  }
}
