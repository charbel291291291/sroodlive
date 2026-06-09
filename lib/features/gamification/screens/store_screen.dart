import 'package:flutter/material.dart';

import '../../../shared/widgets/avatar_with_frame.dart';
import '../models/store_item.dart';
import '../services/gamification_service.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final _service = const GamificationService();
  List<StoreItem> _all = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | avatar_frame | badge

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _service.getStoreItems();
      if (!mounted) return;
      setState(() { _all = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<StoreItem> get _filtered {
    if (_filter == 'all') return _all;
    return _all.where((i) => i.itemType == _filter).toList();
  }

  Future<void> _buy(StoreItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmBuyDialog(item: item, isArabic: widget.isArabic),
    );
    if (confirm != true || !mounted) return;

    try {
      await _service.purchaseStoreItem(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.isArabic ? 'تم الشراء بنجاح!' : 'Purchased!'),
        backgroundColor: const Color(0xFF2ECC71),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: const Color(0xFFFF4D6D),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
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
              _buildHeader(),
              _buildFilters(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
        child: Row(
          textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            ),
            Text(
              widget.isArabic ? 'المتجر' : 'Store',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );

  Widget _buildFilters() {
    final chips = [
      ('all', widget.isArabic ? 'الكل' : 'All'),
      ('avatar_frame', widget.isArabic ? 'الإطارات' : 'Frames'),
      ('badge', widget.isArabic ? 'الشارات' : 'Badges'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: chips.map((c) {
          final selected = _filter == c.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = c.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFF0C15A) : const Color(0xFF1B102A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? const Color(0xFFF0C15A) : const Color(0xFF4A3470),
                  ),
                ),
                child: Text(
                  c.$2,
                  style: TextStyle(
                    color: selected ? const Color(0xFF160B26) : const Color(0xFFD8CFEA),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFF0C15A), strokeWidth: 2.5));
    if (_error != null) return _ErrorView(message: _error!, isArabic: widget.isArabic, onRetry: _load);
    if (_filtered.isEmpty) return _EmptyView(isArabic: widget.isArabic);

    return RefreshIndicator(
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _StoreItemCard(
          item: _filtered[i],
          isArabic: widget.isArabic,
          onBuy: () => _buy(_filtered[i]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item card
// ---------------------------------------------------------------------------

class _StoreItemCard extends StatelessWidget {
  const _StoreItemCard({required this.item, required this.isArabic, required this.onBuy});
  final StoreItem item;
  final bool isArabic;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: item.owned
              ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
              : const Color(0xFF4A3470),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.08),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(child: _ItemPreview(item: item)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Column(
              children: [
                Text(
                  item.localName(isArabic),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monetization_on_rounded, color: Color(0xFFF0C15A), size: 14),
                    const SizedBox(width: 3),
                    Text(
                      _fmt(item.priceCoins),
                      style: const TextStyle(color: Color(0xFFF0C15A), fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                item.owned
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          isArabic ? '✓ مملوك' : '✓ Owned',
                          style: const TextStyle(color: Color(0xFF2ECC71), fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onBuy,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF0C15A),
                            foregroundColor: const Color(0xFF160B26),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text(
                            isArabic ? 'شراء' : 'Buy',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }
}

class _ItemPreview extends StatelessWidget {
  const _ItemPreview({required this.item});
  final StoreItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isFrame && item.frameKey != null) {
      return AvatarWithFrame(
        imageUrl: null,
        radius: 40,
        frameKey: item.frameKey,
        compact: false,
      );
    }
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF4B168C), Color(0xFF8B26D9)],
        ),
        border: Border.all(color: const Color(0xFF8B26D9).withValues(alpha: 0.5)),
      ),
      child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFF0C15A), size: 32),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm buy dialog
// ---------------------------------------------------------------------------

class _ConfirmBuyDialog extends StatelessWidget {
  const _ConfirmBuyDialog({required this.item, required this.isArabic});
  final StoreItem item;
  final bool isArabic;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B102A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        isArabic ? 'تأكيد الشراء' : 'Confirm Purchase',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.localName(isArabic),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.monetization_on_rounded, color: Color(0xFFF0C15A), size: 20),
              const SizedBox(width: 4),
              Text(
                _fmt(item.priceCoins),
                style: const TextStyle(color: Color(0xFFF0C15A), fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(isArabic ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Color(0xFF7A6890))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF0C15A),
            foregroundColor: const Color(0xFF160B26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(isArabic ? 'شراء' : 'Buy', style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.isArabic, required this.onRetry});
  final String message;
  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5C7A), size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(isArabic ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(color: Color(0xFFF0C15A))),
            ),
          ],
        ),
      );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_rounded, color: Color(0xFF4A3470), size: 56),
            const SizedBox(height: 12),
            Text(
              isArabic ? 'المتجر فارغ حالياً' : 'No items available',
              style: const TextStyle(color: Color(0xFF7A6890), fontSize: 15),
            ),
          ],
        ),
      );
}
