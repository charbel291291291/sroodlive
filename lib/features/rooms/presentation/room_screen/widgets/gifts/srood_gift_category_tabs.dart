/// Level-2 gift navigation: the existing Event/Hot/Lucky/VIP categories,
/// kept as-is but with a clearer filled/underline selected state.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

class SroodGiftCategoryTabs extends StatelessWidget {
  const SroodGiftCategoryTabs({
    required this.isArabic,
    required this.selectedCategoryKey,
    required this.onSelected,
    super.key,
  });

  final bool isArabic;
  final String selectedCategoryKey;
  final ValueChanged<String> onSelected;

  static const _categories = [
    (key: 'event', labelEn: 'Event', labelAr: 'حدث'),
    (key: 'hot', labelEn: 'Hot', labelAr: 'رائج'),
    (key: 'lucky', labelEn: 'Lucky', labelAr: 'حظ'),
    (key: 'vip', labelEn: 'VIP', labelAr: 'VIP'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: _categories.map((category) {
        final selected = category.key == selectedCategoryKey;
        final label = isArabic ? category.labelAr : category.labelEn;

        return Expanded(
          child: Semantics(
            button: true,
            selected: selected,
            label: label,
            child: InkWell(
              borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
              onTap: () => onSelected(category.key),
              child: AnimatedContainer(
                duration: SroodRoomMotion.fast,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF2A1640)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFF8C819E),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: selected ? 22 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: SroodRoomColors.gold,
                        borderRadius: BorderRadius.circular(
                          SroodRoomDims.radiusPill,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
