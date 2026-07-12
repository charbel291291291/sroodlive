/// Gift selection sheet: receiver rail, category tabs, gift grid, quantity
/// chips, and the send bar. Pops a [SroodGiftSendResult]; the screen state
/// performs the actual send and wallet handling.
library;

import 'package:flutter/material.dart';

import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:srood_live/shared/widgets/vip_badge.dart';

import '../../../../../wallet/services/wallet_service.dart';
import '../../../../models/room_gift.dart';
import '../../../../models/room_member.dart';
import '../../../../utils/vip_room_features.dart';
import '../../../theme/srood_room_theme.dart';
import '../../models/srood_gift_events.dart';
import '../common/srood_gift_artwork.dart';
import '../common/srood_room_avatar.dart';

class SroodGiftSheet extends StatefulWidget {
  const SroodGiftSheet({
    required this.isArabic,
    required this.receivers,
    required this.gifts,
    required this.roleLabel,
    this.initialReceiverUserId,
    super.key,
  });

  final bool isArabic;
  final List<RoomMember> receivers;
  final List<RoomGift> gifts;
  final String Function(String role) roleLabel;
  final String? initialReceiverUserId;

  @override
  State<SroodGiftSheet> createState() => _SroodGiftSheetState();
}

class _SroodGiftSheetState extends State<SroodGiftSheet> {
  RoomMember? _selectedReceiver;
  RoomGift? _selectedGift;
  String _selectedCategoryKey = 'hot';
  int _quantity = 1;
  int _userCoinsBalance = 0;

  @override
  void initState() {
    super.initState();

    final initialReceiverUserId = widget.initialReceiverUserId;
    if (initialReceiverUserId != null) {
      for (final receiver in widget.receivers) {
        if (receiver.userId == initialReceiverUserId) {
          _selectedReceiver = receiver;
          break;
        }
      }
    }

    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final wallet = await const WalletService().fetchWallet();
      if (mounted) setState(() => _userCoinsBalance = wallet.coinsBalance);
    } catch (e, st) {
      debugError('SroodGiftSheet._loadBalance', e, st);
    }
  }

  void _chooseGift(RoomGift gift) {
    setState(() {
      _selectedGift = gift;
    });

    if (_selectedReceiver == null) {
      _showReceiverRequiredMessage();
      return;
    }
  }

  void _sendGift() {
    final receiver = _selectedReceiver;
    final gift = _selectedGift;

    if (receiver == null) {
      _showReceiverRequiredMessage();
      return;
    }

    if (gift == null) {
      SroodToast.show(
        context,
        widget.isArabic ? 'اختر هدية أولاً.' : 'Choose a gift first.',
        type: SroodToastType.info,
      );
      return;
    }

    Navigator.of(context).pop(
      SroodGiftSendResult(
        gift: gift,
        receiverUserId: receiver.userId,
        receiverName: receiver.fallbackName(widget.isArabic),
        quantity: _quantity,
      ),
    );
  }

  void _showReceiverRequiredMessage() {
    SroodToast.show(
      context,
      widget.isArabic
          ? 'اختر شخصاً لإرسال الهدية.'
          : 'Choose someone to receive the gift.',
      type: SroodToastType.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    final visibleGifts = widget.gifts
        .where((gift) => gift.categoryKey == _selectedCategoryKey)
        .toList();
    final gifts = visibleGifts.isEmpty ? widget.gifts : visibleGifts;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            SroodRoomDims.space12,
            SroodRoomDims.space12,
            SroodRoomDims.space12,
            MediaQuery.of(context).viewInsets.bottom > 0
                ? MediaQuery.of(context).viewInsets.bottom
                : SroodRoomDims.space8,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF06030A),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(SroodRoomDims.radiusSheet + 4),
            ),
          ),
          child: Column(
            children: [
              _GiftSheetGrabber(isArabic: widget.isArabic),
              const SizedBox(height: 10),
              _GiftReceiverRail(
                isArabic: widget.isArabic,
                receivers: widget.receivers,
                selectedReceiver: _selectedReceiver,
                roleLabel: widget.roleLabel,
                onSelected: (receiver) {
                  setState(() {
                    _selectedReceiver = receiver;
                  });
                },
              ),
              const SizedBox(height: SroodRoomDims.space12),
              _GiftCategoryTabs(
                isArabic: widget.isArabic,
                selectedCategoryKey: _selectedCategoryKey,
                onSelected: (key) {
                  setState(() {
                    _selectedCategoryKey = key;
                    if (_selectedGift?.categoryKey != key) {
                      _selectedGift = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth < 320 ? 3 : 4;
                    return GridView.builder(
                      padding: const EdgeInsets.only(
                        bottom: SroodRoomDims.space8,
                      ),
                      itemCount: gifts.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 6,
                        childAspectRatio: 0.78,
                      ),
                      itemBuilder: (context, index) {
                        final gift = gifts[index];
                        return _GiftCard(
                          gift: gift,
                          isArabic: widget.isArabic,
                          selected: _selectedGift?.name == gift.name,
                          onTap: () => _chooseGift(gift),
                        );
                      },
                    );
                  },
                ),
              ),
              _GiftSendBar(
                isArabic: widget.isArabic,
                quantity: _quantity,
                selectedGift: _selectedGift,
                userCoinsBalance: _userCoinsBalance,
                onQuantityChanged: (q) => setState(() => _quantity = q),
                onSend: _sendGift,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftSheetGrabber extends StatelessWidget {
  const _GiftSheetGrabber({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Text(
          isArabic ? 'الهدايا' : 'Gifts',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        Container(
          width: 54,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFF332344),
            borderRadius: BorderRadius.circular(SroodRoomDims.radiusPill),
          ),
        ),
      ],
    );
  }
}

class _GiftReceiverRail extends StatelessWidget {
  const _GiftReceiverRail({
    required this.isArabic,
    required this.receivers,
    required this.selectedReceiver,
    required this.roleLabel,
    required this.onSelected,
  });

  final bool isArabic;
  final List<RoomMember> receivers;
  final RoomMember? selectedReceiver;
  final String Function(String role) roleLabel;
  final ValueChanged<RoomMember> onSelected;

  @override
  Widget build(BuildContext context) {
    if (receivers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusLg),
          border: Border.all(color: const Color(0xFF4A3470)),
        ),
        child: Text(
          isArabic ? 'لا يوجد مستلمون آخرون.' : 'No other active users.',
          textAlign: isArabic ? TextAlign.right : TextAlign.left,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFD8CFEA),
            fontWeight: FontWeight.w800,
            fontSize: SroodRoomDims.textMd,
          ),
        ),
      );
    }

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: isArabic,
        itemCount: receivers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final receiver = receivers[index];
          final selected = selectedReceiver?.userId == receiver.userId;

          return _GiftReceiverBubble(
            receiver: receiver,
            selected: selected,
            isArabic: isArabic,
            publicUserId: receiver.displayCode,
            avatarUrl: receiver.avatarUrl,
            onTap: () => onSelected(receiver),
          );
        },
      ),
    );
  }
}

class _GiftReceiverBubble extends StatelessWidget {
  const _GiftReceiverBubble({
    required this.receiver,
    required this.selected,
    required this.isArabic,
    required this.publicUserId,
    required this.avatarUrl,
    required this.onTap,
  });

  final RoomMember receiver;
  final bool selected;
  final bool isArabic;
  final String publicUserId;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = receiver.fallbackName(isArabic);
    final vipLevel = receiver.effectiveVipLevel;

    return InkWell(
      borderRadius: BorderRadius.circular(SroodRoomDims.radiusXl),
      onTap: onTap,
      child: SizedBox(
        width: 82,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SroodRoomAvatar(
              avatarUrl: avatarUrl,
              frameKey: receiver.selectedAvatarFrameKey,
              vipLevel: receiver.effectiveVipLevel,
              size: 52,
              selected: selected,
              fallbackIcon: receiver.role == 'listener'
                  ? Icons.person_rounded
                  : Icons.mic_rounded,
              isOfficialAgent: receiver.isOfficialAgent,
            ),
            const SizedBox(height: 3),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: vipLevel > 0
                    ? VipVisualStyle.nameColor(vipLevel, context)
                    : selected
                    ? Colors.white
                    : const Color(0xFFD8CFEA),
                fontSize: SroodRoomDims.textSm,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (vipLevel > 0)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: VipBadge(vipLevel: vipLevel, compact: true),
              ),
            Text(
              publicUserId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9E91B8),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftCategoryTabs extends StatelessWidget {
  const _GiftCategoryTabs({
    required this.isArabic,
    required this.selectedCategoryKey,
    required this.onSelected,
  });

  final bool isArabic;
  final String selectedCategoryKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final categories = [
      (key: 'event', label: isArabic ? 'حدث' : 'Event'),
      (key: 'hot', label: isArabic ? 'رائج' : 'Hot'),
      (key: 'lucky', label: isArabic ? 'حظ' : 'Lucky'),
      (key: 'vip', label: 'VIP'),
    ];

    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: categories.map((category) {
        final selected = category.key == selectedCategoryKey;

        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
            onTap: () => onSelected(category.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF8C819E),
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
        );
      }).toList(),
    );
  }
}

class _GiftCard extends StatelessWidget {
  const _GiftCard({
    required this.gift,
    required this.isArabic,
    required this.selected,
    required this.onTap,
  });

  final RoomGift gift;
  final bool isArabic;
  final bool selected;
  final VoidCallback onTap;

  String _fmtPrice(int p) {
    if (p >= 1000000) return 'M';
    if (p >= 1000) {
      return 'K';
    }
    return p.toString();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd + 2),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 7, 5, 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF42105C) : Colors.transparent,
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd + 2),
          border: Border.all(
            color: selected ? const Color(0xFFD10DFF) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFD10DFF).withValues(alpha: 0.28),
                    blurRadius: 14,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sz = (constraints.maxWidth * 0.82).clamp(32.0, 56.0);
                    return SroodGiftArtwork(gift: gift, size: sz);
                  },
                ),
              ),
            ),
            const SizedBox(height: SroodRoomDims.space4),
            Text(
              isArabic ? gift.arabicName : gift.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: SroodRoomDims.textSm,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: SroodRoomColors.gold,
                  size: 11,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    _fmtPrice(gift.priceCoins),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontWeight: FontWeight.w700,
                      fontSize: SroodRoomDims.textXs,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftSendBar extends StatelessWidget {
  const _GiftSendBar({
    required this.isArabic,
    required this.quantity,
    required this.selectedGift,
    required this.userCoinsBalance,
    required this.onQuantityChanged,
    required this.onSend,
  });

  static const _quantities = [1, 7, 17, 77];

  final bool isArabic;
  final int quantity;
  final RoomGift? selectedGift;
  final int userCoinsBalance;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onSend;

  String _formatCoins(int c) {
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M';
    if (c >= 1000) return '${(c / 1000).toStringAsFixed(1)}K';
    return c.toString();
  }

  @override
  Widget build(BuildContext context) {
    final total = (selectedGift?.priceCoins ?? 0) * quantity;
    final displayValue = selectedGift == null
        ? _formatCoins(userCoinsBalance)
        : _formatCoins(total);

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
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            // ── coin balance / total ─────────────────────────────────────────
            const Icon(
              Icons.monetization_on_rounded,
              color: SroodRoomColors.gold,
              size: SroodRoomDims.iconMd,
            ),
            const SizedBox(width: SroodRoomDims.space4),
            Flexible(
              flex: 3,
              child: Text(
                displayValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8C819E),
              size: 18,
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: _quantities
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
            // ── send button ─────────────────────────────────────────────────
            Flexible(
              flex: 4,
              child: SizedBox(
                height: SroodRoomDims.touchTarget,
                child: FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB000FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
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
          ],
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
    return GestureDetector(
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
            color: selected ? const Color(0xFFB56DFF) : const Color(0xFF3A2F4A),
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
    );
  }
}
