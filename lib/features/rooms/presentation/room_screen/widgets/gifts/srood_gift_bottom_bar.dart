/// Fixed footer: coin balance / total cost, quantity chips, send button.
/// Quantity is driven by a [ValueListenable] so changing it only rebuilds
/// this bar, not the gift grid above it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../models/room_gift.dart';
import '../../../theme/srood_room_theme.dart';
import 'srood_gift_price.dart';

class SroodGiftBottomBar extends StatelessWidget {
  const SroodGiftBottomBar({
    required this.isArabic,
    required this.quantityListenable,
    required this.selectedGift,
    required this.hasReceiver,
    required this.userCoinsBalance,
    required this.onQuantityChanged,
    required this.onSend,
    super.key,
  });

  static const quantities = [1, 7, 17, 77];

  final bool isArabic;
  final ValueListenable<int> quantityListenable;
  final RoomGift? selectedGift;
  final bool hasReceiver;
  final int userCoinsBalance;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
        decoration: BoxDecoration(
          color: const Color(0xFF06030A).withValues(alpha: 0.96),
          border: Border(
            top: BorderSide(
              color: const Color(0xFF4A3470).withValues(alpha: 0.45),
            ),
          ),
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: quantityListenable,
          builder: (context, quantity, _) {
            final gift = selectedGift;
            final total = (gift?.priceCoins ?? 0) * quantity;
            final insufficientBalance =
                gift != null && total > userCoinsBalance;
            final canSend = gift != null && hasReceiver && !insufficientBalance;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (gift != null && quantity > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Align(
                      alignment: isArabic
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        '${formatGiftCoins(gift.priceCoins)} × $quantity = '
                        '${formatGiftCoins(total)}',
                        style: TextStyle(
                          color: insufficientBalance
                              ? SroodRoomColors.danger
                              : const Color(0xFFD8CFEA),
                          fontSize: SroodRoomDims.textXs,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Flexible(
                      flex: 3,
                      child: SroodGiftPrice(
                        coins: gift == null ? userCoinsBalance : total,
                        iconSize: SroodRoomDims.iconMd,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: insufficientBalance
                            ? SroodRoomColors.danger
                            : Colors.white,
                        semanticsLabel: isArabic
                            ? '${gift == null ? 'الرصيد' : 'الإجمالي'}: '
                                  '${formatGiftCoins(gift == null ? userCoinsBalance : total)} عملة'
                            : '${gift == null ? 'Balance' : 'Total'}: '
                                  '${formatGiftCoins(gift == null ? userCoinsBalance : total)} coins',
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: quantities
                          .map(
                            (q) => Padding(
                              padding: const EdgeInsets.only(
                                right: SroodRoomDims.space6,
                              ),
                              child: _QuantityChip(
                                value: q,
                                selected: quantity == q,
                                onTap: () => onQuantityChanged(q),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(width: SroodRoomDims.space8),
                    Flexible(
                      flex: 4,
                      child: SizedBox(
                        height: SroodRoomDims.touchTarget,
                        child: Semantics(
                          button: true,
                          enabled: canSend,
                          label: isArabic ? 'إرسال' : 'Send',
                          child: FilledButton(
                            onPressed: canSend ? onSend : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB000FF),
                              disabledBackgroundColor: const Color(0xFF3A2F4A),
                              foregroundColor: Colors.white,
                              disabledForegroundColor: const Color(0xFF8C819E),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  SroodRoomDims.radiusPill,
                                ),
                              ),
                            ),
                            child: Text(
                              isArabic ? 'إرسال' : 'Send',
                              maxLines: 1,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: SroodRoomDims.textLg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuantityChip extends StatelessWidget {
  const _QuantityChip({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$value',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: SroodRoomMotion.fast,
          height: 36,
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [SroodRoomColors.violetSoft, Color(0xFFB56DFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : const Color(0xFF1D1A20),
            borderRadius: BorderRadius.circular(SroodRoomDims.radiusPill),
            border: Border.all(
              color: selected
                  ? const Color(0xFFB56DFF)
                  : const Color(0xFF3A2F4A),
              width: 1.2,
            ),
          ),
          child: Center(
            child: Text(
              value.toString(),
              style: TextStyle(
                fontSize: SroodRoomDims.textLg,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : const Color(0xFF8C819E),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
