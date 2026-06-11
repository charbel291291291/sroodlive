import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../profile/screens/user_profile_screen.dart';

class GiftHistoryScreen extends StatefulWidget {
  const GiftHistoryScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<GiftHistoryScreen> createState() => _GiftHistoryScreenState();
}

class _GiftRecord {
  final String id;
  final String giftName;
  final int quantity;
  final int coinValue;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final DateTime createdAt;
  final bool isSent;

  const _GiftRecord({
    required this.id,
    required this.giftName,
    required this.quantity,
    required this.coinValue,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.createdAt,
    required this.isSent,
  });
}

class _GiftHistoryScreenState extends State<GiftHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _error;
  List<_GiftRecord> _received = const [];
  List<_GiftRecord> _sent = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = SupabaseService.requiredClient.auth.currentUser?.id;
      if (me == null) throw Exception('Not logged in');

      final [receivedRaw, sentRaw] = await Future.wait<dynamic>([
        SupabaseService.requiredClient
            .from('gift_transactions')
            .select(
              'id, gift_name, quantity, total_cost_coins, created_at, sender_id, sender:profiles!gift_transactions_sender_id_fkey(display_name, avatar_url)',
            )
            .eq('receiver_id', me)
            .order('created_at', ascending: false)
            .limit(100),
        SupabaseService.requiredClient
            .from('gift_transactions')
            .select(
              'id, gift_name, quantity, total_cost_coins, created_at, receiver_id, receiver:profiles!gift_transactions_receiver_id_fkey(display_name, avatar_url)',
            )
            .eq('sender_id', me)
            .order('created_at', ascending: false)
            .limit(100),
      ]);

      _GiftRecord mapReceived(Map<String, dynamic> r) {
        final sender = r['sender'] is Map<String, dynamic>
            ? r['sender'] as Map<String, dynamic>
            : <String, dynamic>{};
        return _GiftRecord(
          id: r['id'] as String,
          giftName: r['gift_name'] as String? ?? '',
          quantity: r['quantity'] as int? ?? 1,
          coinValue: r['total_cost_coins'] as int? ?? 0,
          otherUserId: r['sender_id'] as String,
          otherUserName: sender['display_name'] as String? ?? '',
          otherUserAvatar: sender['avatar_url'] as String?,
          createdAt:
              DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now(),
          isSent: false,
        );
      }

      _GiftRecord mapSent(Map<String, dynamic> r) {
        final receiver = r['receiver'] is Map<String, dynamic>
            ? r['receiver'] as Map<String, dynamic>
            : <String, dynamic>{};
        return _GiftRecord(
          id: r['id'] as String,
          giftName: r['gift_name'] as String? ?? '',
          quantity: r['quantity'] as int? ?? 1,
          coinValue: r['total_cost_coins'] as int? ?? 0,
          otherUserId: r['receiver_id'] as String,
          otherUserName: receiver['display_name'] as String? ?? '',
          otherUserAvatar: receiver['avatar_url'] as String?,
          createdAt:
              DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now(),
          isSent: true,
        );
      }

      if (!mounted) return;
      setState(() {
        _received = (receivedRaw as List)
            .map((r) => mapReceived(r as Map<String, dynamic>))
            .toList();
        _sent = (sentRaw as List)
            .map((r) => mapSent(r as Map<String, dynamic>))
            .toList();
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

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
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
                  isArabic ? 'سجل الهدايا' : 'Gift History',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isArabic
                      ? 'الهدايا المُرسلة والمستلمة'
                      : 'Sent and received gifts',
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: const Color(0xFF3A174F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8B26D9)),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF9E91B8),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
            text: isArabic
                ? 'مستلمة (${_received.length})'
                : 'Received (${_received.length})',
          ),
          Tab(
            text: isArabic
                ? 'مُرسلة (${_sent.length})'
                : 'Sent (${_sent.length})',
          ),
        ],
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
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
            ),
            const SizedBox(height: 12),
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
      controller: _tabController,
      children: [_buildList(_received, isArabic), _buildList(_sent, isArabic)],
    );
  }

  Widget _buildList(List<_GiftRecord> records, bool isArabic) {
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.card_giftcard_rounded,
              color: Color(0xFF2A1840),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isArabic ? 'لا توجد هدايا بعد' : 'No gifts yet',
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
        itemCount: records.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) =>
            _GiftTile(record: records[i], isArabic: isArabic),
      ),
    );
  }
}

class _GiftTile extends StatelessWidget {
  const _GiftTile({required this.record, required this.isArabic});

  final _GiftRecord record;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final isSent = record.isSent;
    final accentColor = isSent
        ? const Color(0xFFFF4D6D)
        : const Color(0xFF3ECC8C);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              UserProfileScreen(userId: record.otherUserId, isArabic: isArabic),
        ),
      ),
      child: Container(
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
            // Gift emoji / icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF0C15A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFF0C15A).withValues(alpha: 0.3),
                ),
              ),
              alignment: Alignment.center,
              child: const Text('🎁', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    record.giftName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: const Color(0xFF241638),
                        backgroundImage: record.otherUserAvatar != null
                            ? NetworkImage(record.otherUserAvatar!)
                            : null,
                        child: record.otherUserAvatar == null
                            ? Text(
                                record.otherUserName.isNotEmpty
                                    ? record.otherUserName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '${isSent ? (isArabic ? 'إلى' : 'To') : (isArabic ? 'من' : 'From')} ${record.otherUserName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF9E91B8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Icon(
                      isSent
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: accentColor,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${record.quantity}×',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.coinValue}🪙',
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(record.createdAt),
                  style: const TextStyle(
                    color: Color(0xFF6E5A8A),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }
}
