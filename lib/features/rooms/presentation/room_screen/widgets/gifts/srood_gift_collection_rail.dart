/// Level-1 gift navigation: a compact horizontal rail of smart-collection
/// chips (Featured, Country Royals, Lebanese Luxury, Mythic, All Gifts)
/// shown above the existing category tabs.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';
import 'gift_collections.dart';

class SroodGiftCollectionRail extends StatelessWidget {
  const SroodGiftCollectionRail({
    required this.isArabic,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final bool isArabic;
  final SroodGiftCollectionKey selected;
  final ValueChanged<SroodGiftCollectionKey> onSelected;

  static const _order = [
    SroodGiftCollectionKey.featured,
    SroodGiftCollectionKey.countryRoyals,
    SroodGiftCollectionKey.lebaneseLuxury,
    SroodGiftCollectionKey.mythic,
    SroodGiftCollectionKey.all,
  ];

  String _label(SroodGiftCollectionKey key) {
    return switch (key) {
      SroodGiftCollectionKey.featured => isArabic ? 'مميز' : 'Featured',
      SroodGiftCollectionKey.countryRoyals =>
        isArabic ? 'ملوك الدول' : 'Country Royals',
      SroodGiftCollectionKey.lebaneseLuxury =>
        isArabic ? 'فخامة لبنانية' : 'Lebanese Luxury',
      SroodGiftCollectionKey.mythic => isArabic ? 'أسطوري' : 'Mythic',
      SroodGiftCollectionKey.all => isArabic ? 'كل الهدايا' : 'All Gifts',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: isArabic,
        itemCount: _order.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = _order[index];
          final isSelected = key == selected;

          return _CollectionChip(
            label: _label(key),
            selected: isSelected,
            onTap: () => onSelected(key),
          );
        },
      ),
    );
  }
}

class _CollectionChip extends StatelessWidget {
  const _CollectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: SroodRoomMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFF0C15A), Color(0xFFB56DFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : const Color(0xFF1A1030),
            borderRadius: BorderRadius.circular(SroodRoomDims.radiusPill),
            border: Border.all(
              color: selected
                  ? const Color(0xFFF0C15A)
                  : const Color(0xFF3A2F4A),
              width: 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF1A1030)
                  : const Color(0xFFD8CFEA),
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
