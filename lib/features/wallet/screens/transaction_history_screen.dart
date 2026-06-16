import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TxEntry {
  final String id;
  final String type;
  final String label;
  final String? note;
  final int coinsDelta;
  final int diamondsDelta;
  final DateTime createdAt;

  const _TxEntry({
    required this.id,
    required this.type,
    required this.label,
    this.note,
    required this.coinsDelta,
    required this.diamondsDelta,
    required this.createdAt,
  });
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<_TxEntry> _all = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = SupabaseService.requiredClient.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _loading = false;
          _all = const [];
        });
        return;
      }
      final rows = await SupabaseService.requiredClient
          .from('wallet_transactions')
          .select(
            'id, type, label, note, coins_delta, diamonds_delta, created_at',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(200);

      final entries = (rows as List)
          .map(
            (r) => _TxEntry(
              id: r['id'] as String,
              type: r['type'] as String? ?? 'system',
              label: r['label'] as String? ?? 'Transaction',
              note: r['note'] as String?,
              coinsDelta: (r['coins_delta'] as num?)?.toInt() ?? 0,
              diamondsDelta: (r['diamonds_delta'] as num?)?.toInt() ?? 0,
              createdAt: DateTime.parse(r['created_at'] as String),
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _all = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_TxEntry> get _coins => _all.where((t) => t.coinsDelta != 0).toList();
  List<_TxEntry> get _diamonds =>
      _all.where((t) => t.diamondsDelta != 0).toList();

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
              Expanded(child: _buildBody(isArabic)),
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
                  isArabic ? 'سجل المعاملات' : 'Transaction History',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isArabic
                      ? 'عمليات العملات والألماس'
                      : 'Coins and diamonds activity',
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF0C15A)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isArabic) {
    final labels = isArabic
        ? [
            'الكل (${_all.length})',
            'عملات (${_coins.length})',
            'ألماس (${_diamonds.length})',
          ]
        : [
            'All (${_all.length})',
            'Coins (${_coins.length})',
            'Diamonds (${_diamonds.length})',
          ];

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

  Widget _buildBody(bool isArabic) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B26D9)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF5C7A),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _load,
              child: Text(
                isArabic ? 'إعادة' : 'Retry',
                style: const TextStyle(color: Color(0xFFF0C15A)),
              ),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [
        _buildList(_all, isArabic),
        _buildList(_coins, isArabic),
        _buildList(_diamonds, isArabic),
      ],
    );
  }

  Widget _buildList(List<_TxEntry> items, bool isArabic) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFF2A1840),
              size: 64,
            ),
            const SizedBox(height: 14),
            Text(
              isArabic ? 'لا توجد معاملات' : 'No transactions yet',
              style: const TextStyle(
                color: Color(0xFF9E91B8),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _TxTile(entry: items[i], isArabic: isArabic),
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.entry, required this.isArabic});

  final _TxEntry entry;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final delta = entry.coinsDelta != 0
        ? entry.coinsDelta
        : entry.diamondsDelta;
    final unit = entry.coinsDelta != 0
        ? (isArabic ? 'عملة' : 'coins')
        : (isArabic ? 'ألماس' : 'diamonds');
    final isPositive = delta > 0;
    final color = isPositive
        ? const Color(0xFF63E6A1)
        : const Color(0xFFFF6B8A);
    final icon = _iconFor(entry.type);
    final subtitle = entry.note?.trim().isNotEmpty == true
        ? entry.note!
        : _dateLabel(entry.createdAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF0C15A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFF0C15A), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9E91B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${delta > 0 ? "+" : ""}$delta $unit',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'gift_sent' => Icons.card_giftcard_rounded,
      'gift_received' => Icons.redeem_rounded,
      'recharge' => Icons.add_card_rounded,
      'agency_recharge' => Icons.groups_rounded,
      'admin' => Icons.tune_rounded,
      'refund' => Icons.undo_rounded,
      _ => Icons.receipt_long_rounded,
    };
  }

  String _dateLabel(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}
