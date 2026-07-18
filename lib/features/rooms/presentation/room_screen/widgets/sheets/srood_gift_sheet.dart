/// Gift selection sheet: receiver rail, smart-collection rail, category
/// tabs, gift grid (or VIP sub-sections), and the send bar. Pops a
/// [SroodGiftSendResult]; the screen state performs the actual send and
/// wallet handling.
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
import '../common/srood_room_avatar.dart';
import '../gifts/gift_collections.dart';
import '../gifts/srood_gift_bottom_bar.dart';
import '../gifts/srood_gift_category_tabs.dart';
import '../gifts/srood_gift_collection_rail.dart';
import '../gifts/srood_gift_section.dart';
import '../gifts/srood_gift_tile.dart';

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
  SroodGiftCollectionKey _selectedCollection = SroodGiftCollectionKey.all;
  final ValueNotifier<int> _quantity = ValueNotifier<int>(1);
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

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
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

  void _onCategorySelected(String key) {
    setState(() {
      _selectedCategoryKey = key;
      _selectedCollection = SroodGiftCollectionKey.all;
      if (_selectedGift?.categoryKey != key) {
        _selectedGift = null;
      }
    });
  }

  void _onCollectionSelected(SroodGiftCollectionKey key) {
    setState(() {
      _selectedCollection = key;
      final selected = _selectedGift;
      if (key != SroodGiftCollectionKey.all && selected != null) {
        final stillVisible = giftsForCollection(
          widget.gifts,
          key,
        ).any((gift) => gift.code == selected.code);
        if (!stillVisible) {
          _selectedGift = null;
        }
      }
    });
  }

  List<RoomGift> _resolveVisibleGifts() {
    if (_selectedCollection != SroodGiftCollectionKey.all) {
      return giftsForCollection(widget.gifts, _selectedCollection);
    }
    final byCategory = widget.gifts
        .where((gift) => gift.categoryKey == _selectedCategoryKey)
        .toList();
    return byCategory.isEmpty ? widget.gifts : byCategory;
  }

  String _vipSectionTitle(String key) {
    final isArabic = widget.isArabic;
    return switch (key) {
      'country_royals' => isArabic ? 'ملوك الدول' : 'Country Royals',
      'lebanese_icons' => isArabic ? 'رموز لبنانية' : 'Lebanese Icons',
      'royal_and_mythic' => isArabic ? 'ملكي وأسطوري' : 'Royal and Mythic',
      'classic_vip' => isArabic ? 'VIP كلاسيكي' : 'Classic VIP',
      _ => key,
    };
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

    if (gift.priceCoins * _quantity.value > _userCoinsBalance) {
      SroodToast.show(
        context,
        widget.isArabic ? 'رصيدك غير كافٍ.' : 'Insufficient balance.',
        type: SroodToastType.info,
      );
      return;
    }

    Navigator.of(context).pop(
      SroodGiftSendResult(
        gift: gift,
        receiverUserId: receiver.userId,
        receiverName: receiver.fallbackName(widget.isArabic),
        quantity: _quantity.value,
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
    final showVipSections =
        _selectedCollection == SroodGiftCollectionKey.all &&
        _selectedCategoryKey == 'vip';
    final visibleGifts = showVipSections
        ? const <RoomGift>[]
        : _resolveVisibleGifts();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            SroodRoomDims.space12,
            SroodRoomDims.space8,
            SroodRoomDims.space12,
            MediaQuery.of(context).viewInsets.bottom > 0
                ? MediaQuery.of(context).viewInsets.bottom
                : SroodRoomDims.space6,
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
              const SizedBox(height: 8),
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
              const SizedBox(height: SroodRoomDims.space8),
              SroodGiftCollectionRail(
                isArabic: widget.isArabic,
                selected: _selectedCollection,
                onSelected: _onCollectionSelected,
              ),
              const SizedBox(height: SroodRoomDims.space8),
              SroodGiftCategoryTabs(
                isArabic: widget.isArabic,
                selectedCategoryKey: _selectedCategoryKey,
                onSelected: _onCategorySelected,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth < 320 ? 3 : 4;

                    if (showVipSections) {
                      return ListView(
                        padding: const EdgeInsets.only(
                          bottom: SroodRoomDims.space8,
                        ),
                        children: [
                          for (final section in kVipGiftSections)
                            SroodGiftSection(
                              title: _vipSectionTitle(section.titleKey),
                              gifts: giftsByCodes(widget.gifts, section.codes),
                              isArabic: widget.isArabic,
                              selectedGiftCode: _selectedGift?.code,
                              onGiftTap: _chooseGift,
                              crossAxisCount: cols,
                            ),
                        ],
                      );
                    }

                    if (visibleGifts.isEmpty) {
                      return Center(
                        child: Text(
                          widget.isArabic
                              ? 'لا توجد هدايا في هذه المجموعة.'
                              : 'No gifts in this collection.',
                          style: const TextStyle(
                            color: Color(0xFF8C819E),
                            fontWeight: FontWeight.w700,
                            fontSize: SroodRoomDims.textMd,
                          ),
                        ),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.only(
                        bottom: SroodRoomDims.space8,
                      ),
                      itemCount: visibleGifts.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 6,
                        childAspectRatio: 0.78,
                      ),
                      itemBuilder: (context, index) {
                        final gift = visibleGifts[index];
                        return SroodGiftTile(
                          key: ValueKey('gift_grid_tile_${gift.code}'),
                          gift: gift,
                          isArabic: widget.isArabic,
                          selected: _selectedGift?.code == gift.code,
                          onTap: () => _chooseGift(gift),
                        );
                      },
                    );
                  },
                ),
              ),
              SroodGiftBottomBar(
                isArabic: widget.isArabic,
                quantityListenable: _quantity,
                selectedGift: _selectedGift,
                hasReceiver: _selectedReceiver != null,
                userCoinsBalance: _userCoinsBalance,
                onQuantityChanged: (q) => _quantity.value = q,
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
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusLg),
          border: Border.all(color: const Color(0xFF4A3470)),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(
              Icons.person_off_rounded,
              color: Color(0xFF8C819E),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
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
            ),
          ],
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
