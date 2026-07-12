import 'package:flutter/material.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class GiftCatalogScreen extends StatefulWidget {
  const GiftCatalogScreen({
    required this.isArabic,
    this.targetUserId,
    this.targetName,
    super.key,
  });

  final bool isArabic;
  final String? targetUserId;
  final String? targetName;

  @override
  State<GiftCatalogScreen> createState() => _GiftCatalogScreenState();
}

class _GiftItem {
  final String id;
  final String name;
  final String nameAr;
  final int coinCost;
  final String emoji;
  final String category;

  const _GiftItem({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.coinCost,
    required this.emoji,
    required this.category,
  });
}

const _gifts = [
  _GiftItem(
    id: 'rose',
    name: 'Rose',
    nameAr: 'وردة',
    coinCost: 10,
    emoji: '🌹',
    category: 'standard',
  ),
  _GiftItem(
    id: 'heart',
    name: 'Heart',
    nameAr: 'قلب',
    coinCost: 20,
    emoji: '❤️',
    category: 'standard',
  ),
  _GiftItem(
    id: 'star',
    name: 'Star',
    nameAr: 'نجمة',
    coinCost: 50,
    emoji: '⭐',
    category: 'standard',
  ),
  _GiftItem(
    id: 'cake',
    name: 'Cake',
    nameAr: 'كعكة',
    coinCost: 99,
    emoji: '🎂',
    category: 'standard',
  ),
  _GiftItem(
    id: 'crown',
    name: 'Crown',
    nameAr: 'تاج',
    coinCost: 199,
    emoji: '👑',
    category: 'popular',
  ),
  _GiftItem(
    id: 'diamond',
    name: 'Diamond',
    nameAr: 'ماسة',
    coinCost: 299,
    emoji: '💎',
    category: 'popular',
  ),
  _GiftItem(
    id: 'fireworks',
    name: 'Fireworks',
    nameAr: 'ألعاب نارية',
    coinCost: 499,
    emoji: '🎆',
    category: 'popular',
  ),
  _GiftItem(
    id: 'galaxy',
    name: 'Galaxy',
    nameAr: 'مجرة',
    coinCost: 999,
    emoji: '🌌',
    category: 'popular',
  ),
  _GiftItem(
    id: 'rocket',
    name: 'Rocket',
    nameAr: 'صاروخ',
    coinCost: 1999,
    emoji: '🚀',
    category: 'premium',
  ),
  _GiftItem(
    id: 'castle',
    name: 'Castle',
    nameAr: 'قصر',
    coinCost: 4999,
    emoji: '🏰',
    category: 'premium',
  ),
  _GiftItem(
    id: 'dragon',
    name: 'Dragon',
    nameAr: 'تنين',
    coinCost: 9999,
    emoji: '🐉',
    category: 'premium',
  ),
  _GiftItem(
    id: 'universe',
    name: 'Universe',
    nameAr: 'كون',
    coinCost: 19999,
    emoji: '🌠',
    category: 'premium',
  ),
];

class _GiftCatalogScreenState extends State<GiftCatalogScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _sending;
  bool _sending2 = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<_GiftItem> _filtered(String category) => category == 'all'
      ? _gifts
      : _gifts.where((g) => g.category == category).toList();

  void _onGiftTap(_GiftItem gift) {
    if (widget.targetUserId == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => _SendGiftDialog(
        gift: gift,
        targetName: widget.targetName ?? '',
        isArabic: context.isArabic,
        isSending: _sending2,
        onSend: (qty) => _sendGift(gift, qty),
      ),
    );
  }

  Future<void> _sendGift(_GiftItem gift, int qty) async {
    if (_sending2) return;
    setState(() {
      _sending = gift.id;
      _sending2 = true;
    });
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null || widget.targetUserId == null) return;
      await SupabaseService.requiredClient.rpc(
        'send_gift',
        params: {
          'p_sender_id': me,
          'p_receiver_id': widget.targetUserId,
          'p_gift_id': gift.id,
          'p_quantity': qty,
          'p_coin_cost': gift.coinCost * qty,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      SroodToast.show(
        context,
        context.isArabic ? 'تم إرسال الهدية!' : 'Gift sent!',
        type: SroodToastType.success,
      );
    } catch (e, st) {
      if (!mounted) return;
      debugError('GiftCatalogScreen._sendGift', e, st);
      Navigator.of(context).pop();
      SroodToast.show(
        context,
        friendlyMessage(e, isArabic: context.isArabic),
        type: SroodToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = null;
          _sending2 = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(isArabic),
              _buildTabBar(isArabic),
              Expanded(child: _buildGrid(isArabic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'متجر الهدايا' : 'Gift Catalog',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                if (widget.targetName != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    isArabic
                        ? 'أرسل هدية لـ ${widget.targetName}'
                        : 'Send a gift to ${widget.targetName}',
                    style: const TextStyle(
                      color: Color(0xFFBCAED6),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.card_giftcard_rounded,
            color: Color(0xFFF0C15A),
            size: 28,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isArabic) {
    final labels = isArabic
        ? ['الكل', 'عادي', 'شائع', 'مميز']
        : ['All', 'Standard', 'Popular', 'Premium'];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: TabBar(
        controller: _tabs,
        indicator: BoxDecoration(
          color: const Color(0xFF3A174F),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFF8B26D9)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF9E91B8),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        tabs: labels.map((l) => Tab(text: l)).toList(),
      ),
    );
  }

  Widget _buildGrid(bool isArabic) {
    final categories = ['all', 'standard', 'popular', 'premium'];
    return TabBarView(
      controller: _tabs,
      children: categories.map((cat) {
        final items = _filtered(cat);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _GiftCard(
            gift: items[i],
            isArabic: isArabic,
            isSending: _sending == items[i].id,
            canSend: widget.targetUserId != null,
            onTap: () => _onGiftTap(items[i]),
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
    required this.isSending,
    required this.canSend,
    required this.onTap,
  });

  final _GiftItem gift;
  final bool isArabic;
  final bool isSending;
  final bool canSend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGold = gift.category == 'premium';
    return GestureDetector(
      onTap: canSend ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF160B24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isGold
                ? const Color(0xFFF0C15A).withValues(alpha: 0.5)
                : const Color(0xFF6E3AA8).withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(gift.emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 6),
            Text(
              isArabic ? gift.nameAr : gift.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFFF0C15A),
                  size: 11,
                ),
                const SizedBox(width: 2),
                Text(
                  _fmt(gift.coinCost),
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    }
    return '$v';
  }
}

class _SendGiftDialog extends StatefulWidget {
  const _SendGiftDialog({
    required this.gift,
    required this.targetName,
    required this.isArabic,
    required this.isSending,
    required this.onSend,
  });

  final _GiftItem gift;
  final String targetName;
  final bool isArabic;
  final bool isSending;
  final void Function(int qty) onSend;

  @override
  State<_SendGiftDialog> createState() => _SendGiftDialogState();
}

class _SendGiftDialogState extends State<_SendGiftDialog> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final totalCost = widget.gift.coinCost * _qty;

    return Dialog(
      backgroundColor: const Color(0xFF160B24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF6E3AA8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.gift.emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 8),
            Text(
              isArabic ? widget.gift.nameAr : widget.gift.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'إرسال إلى ${widget.targetName}'
                  : 'Send to ${widget.targetName}',
              style: const TextStyle(color: Color(0xFFBCAED6), fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _QtyButton(
                  icon: Icons.remove_rounded,
                  onTap: _qty > 1 ? () => setState(() => _qty--) : null,
                ),
                const SizedBox(width: 20),
                Column(
                  children: [
                    Text(
                      '$_qty',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      isArabic ? 'الكمية' : 'Qty',
                      style: const TextStyle(
                        color: Color(0xFF9E91B8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                _QtyButton(
                  icon: Icons.add_rounded,
                  onTap: _qty < 99 ? () => setState(() => _qty++) : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B102B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF4A3470)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    color: Color(0xFFF0C15A),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$totalCost ${isArabic ? "عملة" : "coins"}',
                    style: const TextStyle(
                      color: Color(0xFFF0C15A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9E91B8),
                      side: const BorderSide(color: Color(0xFF4A3470)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(isArabic ? 'إلغاء' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.isSending
                        ? null
                        : () => widget.onSend(_qty),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF0C15A),
                      foregroundColor: const Color(0xFF140820),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: widget.isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF140820),
                            ),
                          )
                        : Text(
                            isArabic ? 'أرسل' : 'Send',
                            style: const TextStyle(fontWeight: FontWeight.w900),
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

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null
              ? const Color(0xFF3A174F)
              : const Color(0xFF1B102B),
          shape: BoxShape.circle,
          border: Border.all(
            color: onTap != null
                ? const Color(0xFF8B26D9)
                : const Color(0xFF4A3470),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? Colors.white : const Color(0xFF4A3470),
        ),
      ),
    );
  }
}
