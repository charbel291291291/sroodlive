import 'package:flutter/material.dart';

import '../../../shared/widgets/avatar_with_frame.dart';
import '../models/backpack_item.dart';
import '../services/gamification_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class BackpackScreen extends StatefulWidget {
  const BackpackScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<BackpackScreen> createState() => _BackpackScreenState();
}

class _BackpackScreenState extends State<BackpackScreen> {
  final _service = const GamificationService();
  List<BackpackItem> _all = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.getMyBackpack();
      if (!mounted) return;
      setState(() {
        _all = items;
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

  List<BackpackItem> get _filtered {
    if (_filter == 'all') return _all;
    return _all.where((i) => i.itemType == _filter).toList();
  }

  Future<void> _equip(BackpackItem bp) async {
    try {
      await _service.equipBackpackItem(bp.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic
                ? '\u062a\u0645 \u0627\u0644\u062a\u0641\u0639\u064a\u0644!'
                : 'Equipped!',
          ),
          backgroundColor: const Color(0xFF2ECC71),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFFFF4D6D),
        ),
      );
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
      textDirection: context.isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        Text(
          context.isArabic
              ? '\u0627\u0644\u062d\u0642\u064a\u0628\u0629'
              : 'Backpack',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _buildFilters() {
    final chips = [
      ('all', context.isArabic ? '\u0627\u0644\u0643\u0644' : 'All'),
      (
        'avatar_frame',
        context.isArabic
            ? '\u0627\u0644\u0625\u0637\u0627\u0631\u0627\u062a'
            : 'Frames',
      ),
      (
        'badge',
        context.isArabic
            ? '\u0627\u0644\u0634\u0627\u0631\u0627\u062a'
            : 'Badges',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        textDirection: context.isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: chips.map((c) {
          final selected = _filter == c.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = c.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFF0C15A)
                      : const Color(0xFF1B102A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFF0C15A)
                        : const Color(0xFF4A3470),
                  ),
                ),
                child: Text(
                  c.$2,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF160B26)
                        : const Color(0xFFD8CFEA),
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
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF0C15A),
          strokeWidth: 2.5,
        ),
      );
    }
    if (_error != null) return _buildError();
    if (_filtered.isEmpty) return _buildEmpty();

    return RefreshIndicator(
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _BackpackItemCard(
          bp: _filtered[i],
          isArabic: context.isArabic,
          onEquip: () => _equip(_filtered[i]),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
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
            context.isArabic
                ? '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'
                : 'Retry',
            style: const TextStyle(color: Color(0xFFF0C15A)),
          ),
        ),
      ],
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.backpack_rounded, color: Color(0xFF4A3470), size: 56),
        const SizedBox(height: 12),
        Text(
          context.isArabic
              ? '\u062d\u0642\u064a\u0628\u062a\u0643 \u0641\u0627\u0631\u063a\u0629'
              : 'Your backpack is empty',
          style: const TextStyle(
            color: Color(0xFF7A6890),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.isArabic
              ? '\u0627\u0634\u062a\u0631\u064a \u0648\u0641\u0639\u0651\u0644'
              : 'Equipped',
          style: const TextStyle(color: Color(0xFF4A3470), fontSize: 13),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Backpack item card
// ---------------------------------------------------------------------------

class _BackpackItemCard extends StatelessWidget {
  const _BackpackItemCard({
    required this.bp,
    required this.isArabic,
    required this.onEquip,
  });
  final BackpackItem bp;
  final bool isArabic;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: bp.equipped
              ? const Color(0xFFF0C15A).withValues(alpha: 0.7)
              : const Color(0xFF4A3470),
          width: bp.equipped ? 1.5 : 1,
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Preview
          SizedBox(
            width: 60,
            height: 60,
            child: bp.isFrame && bp.item.frameKey != null
                ? AvatarWithFrame(
                    imageUrl: null,
                    radius: 24,
                    frameKey: bp.item.frameKey,
                    compact: false,
                  )
                : Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF4B168C), Color(0xFF8B26D9)],
                      ),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFF0C15A),
                      size: 28,
                    ),
                  ),
          ),
          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Expanded(
                      child: Text(
                        bp.item.localName(isArabic),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (bp.equipped)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF0C15A,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(
                              0xFFF0C15A,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          isArabic
                              ? '\u0645\u0641\u0639\u0651\u0644'
                              : 'Equipped',
                          style: const TextStyle(
                            color: Color(0xFFF0C15A),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  bp.item.localDescription(isArabic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A6890),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                if (!bp.equipped)
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: onEquip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4B168C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isArabic ? '\u062a\u0641\u0639\u064a\u0644' : 'Equip',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
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
}
