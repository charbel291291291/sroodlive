/// Gift-code-based grouping for the gift drawer's two-level navigation.
///
/// Every list here is a set of `RoomGift.code` values, not hardcoded
/// [RoomGift] instances — the sheet always filters the live/fallback gift
/// list it already has by these codes, so the grouping stays correct even if
/// prices, names, or art change server-side.
library;

import '../../../../models/room_gift.dart';

enum SroodGiftCollectionKey {
  featured,
  countryRoyals,
  lebaneseLuxury,
  mythic,
  all,
}

const List<String> kCountryRoyalGiftCodes = [
  'egypt_royal',
  'iraq_royal',
  'jordan_royal',
  'lebanon_royal',
  'palestine_royal',
  'saudi_arabia_royal',
];

const List<String> kLebaneseLuxuryGiftCodes = [
  'baalbek_temple',
  'golden_lion',
  'lebanon_royal',
  'cedar_throne',
  'byblos_royal_crown',
  'jeita_crystal_palace',
  'phoenician_ship',
  'lebanese_phoenix',
];

const List<String> kMythicGiftCodes = [
  'golden_lion',
  'cedar_throne',
  'byblos_royal_crown',
  'jeita_crystal_palace',
  'phoenician_ship',
  'lebanese_phoenix',
];

/// Featured = the ordered, de-duplicated union of the curated luxury sets
/// above: exactly the highest-priority, most-recent, currently-promoted
/// gifts the game sells, without inventing a priority field that doesn't
/// exist on [RoomGift].
List<String> get kFeaturedGiftCodes {
  final seen = <String>{};
  final ordered = <String>[
    ...kCountryRoyalGiftCodes,
    ...kLebaneseLuxuryGiftCodes,
    ...kMythicGiftCodes,
  ];
  return ordered.where((code) => seen.add(code)).toList();
}

// ── VIP category internal sections ──────────────────────────────────────────

const List<String> kVipCountryRoyalsSectionCodes = kCountryRoyalGiftCodes;

const List<String> kVipLebaneseIconsSectionCodes = [
  'baalbek_temple',
  'golden_lion',
  'lebanon_royal',
];

const List<String> kVipRoyalMythicSectionCodes = [
  'cedar_throne',
  'byblos_royal_crown',
  'jeita_crystal_palace',
  'phoenician_ship',
  'lebanese_phoenix',
];

const List<String> kVipClassicSectionCodes = [
  'tiger',
  'dragon',
  'castle',
  'odrob',
];

/// Filters [gifts] down to the ones whose `code` is in [codes], preserving
/// the order of [codes] (the curated order), and skipping codes that aren't
/// present in [gifts] (e.g. inactive or not yet loaded).
List<RoomGift> giftsByCodes(List<RoomGift> gifts, List<String> codes) {
  final byCode = {for (final gift in gifts) gift.code: gift};
  final result = <RoomGift>[];
  final seen = <String>{};
  for (final code in codes) {
    final gift = byCode[code];
    if (gift != null && seen.add(gift.code)) {
      result.add(gift);
    }
  }
  return result;
}

/// Resolves the gift list for a given [collection] selection. `all` returns
/// [gifts] unchanged (category-tab filtering happens separately upstream).
List<RoomGift> giftsForCollection(
  List<RoomGift> gifts,
  SroodGiftCollectionKey collection,
) {
  return switch (collection) {
    SroodGiftCollectionKey.all => gifts,
    SroodGiftCollectionKey.featured => giftsByCodes(gifts, kFeaturedGiftCodes),
    SroodGiftCollectionKey.countryRoyals => giftsByCodes(
      gifts,
      kCountryRoyalGiftCodes,
    ),
    SroodGiftCollectionKey.lebaneseLuxury => giftsByCodes(
      gifts,
      kLebaneseLuxuryGiftCodes,
    ),
    SroodGiftCollectionKey.mythic => giftsByCodes(gifts, kMythicGiftCodes),
  };
}

/// One VIP category sub-section: a title plus the gift codes it groups.
class VipGiftSectionSpec {
  const VipGiftSectionSpec({required this.titleKey, required this.codes});

  /// Stable key used to look up localized titles in the widget layer.
  final String titleKey;
  final List<String> codes;
}

const List<VipGiftSectionSpec> kVipGiftSections = [
  VipGiftSectionSpec(
    titleKey: 'country_royals',
    codes: kVipCountryRoyalsSectionCodes,
  ),
  VipGiftSectionSpec(
    titleKey: 'lebanese_icons',
    codes: kVipLebaneseIconsSectionCodes,
  ),
  VipGiftSectionSpec(
    titleKey: 'royal_and_mythic',
    codes: kVipRoyalMythicSectionCodes,
  ),
  VipGiftSectionSpec(titleKey: 'classic_vip', codes: kVipClassicSectionCodes),
];
