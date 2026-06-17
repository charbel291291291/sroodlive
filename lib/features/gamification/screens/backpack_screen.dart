import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/theme/vip_tier_colors.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../../../shared/widgets/vip_tier_chip.dart';
import '../models/backpack_item.dart';
import '../services/gamification_service.dart';
import 'store_screen.dart';
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
  int _userVipLevel = 0;

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
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        try {
          final row = await Supabase.instance.client
              .from('profiles')
              .select('vip_level, vip_expires_at')
              .eq('id', uid)
              .maybeSingle();
          if (row != null) {
            final level = (row['vip_level'] as int?) ?? 0;
            final expiresAt = DateTime.tryParse(
              row['vip_expires_at']?.toString() ?? '',
            );
            final expired =
                expiresAt == null || expiresAt.isBefore(DateTime.now());
            _userVipLevel = expired ? 0 : level;
          }
        } catch (_) {
          _userVipLevel = 0;
        }
      }

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

  int _count(String type) =>
      type == 'all' ? _all.length : _all.where((i) => i.itemType == type).length;

  // Safe metadata VIP level parsing — handles num, int, and String from jsonb.
  static int _metaVipLevel(BackpackItem bp) {
    final v = bp.item.metadata['vip_level'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _equip(BackpackItem bp) async {
    try {
      await _service.equipBackpackItem(bp.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic ? 'تم التفعيل!' : 'Equipped!',
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
          context.isArabic ? 'الحقيبة' : 'Backpack',
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
      ('all', context.isArabic ? 'الكل' : 'All'),
      ('avatar_frame', context.isArabic ? 'الإطارات' : 'Frames'),
      ('badge', context.isArabic ? 'الشارات' : 'Badges'),
      (
        'entrance_banner',
        context.isArabic ? 'لافتات الدخول' : 'Banners',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          textDirection:
              context.isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: chips.map((c) {
          final selected = _filter == c.$1;
          final count = _loading ? null : _count(c.$1);
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.$2,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF160B26)
                            : const Color(0xFFD8CFEA),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (count != null && count > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF160B26).withValues(alpha: 0.25)
                              : const Color(0xFF4A3470),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFF160B26)
                                : const Color(0xFFD8CFEA),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
        ),
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

    // Entrance banners tab uses a single-column list with _EntranceBannerCard.
    if (_filter == 'entrance_banner') {
      return RefreshIndicator(
        color: const Color(0xFFF0C15A),
        backgroundColor: const Color(0xFF1B102A),
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final bp = _filtered[i];
            final requiredVip =
                _metaVipLevel(bp);
            final isVipLocked =
                requiredVip > 0 && _userVipLevel < requiredVip;
            return _EntranceBannerCard(
              bp: bp,
              isArabic: context.isArabic,
              isVipLocked: isVipLocked,
              requiredVipLevel: requiredVip,
              onEquip: () => _equip(bp),
            );
          },
        ),
      );
    }

    // Badges tab uses a 2-column grid with premium _BadgeCard.
    if (_filter == 'badge') {
      return RefreshIndicator(
        color: const Color(0xFFF0C15A),
        backgroundColor: const Color(0xFF1B102A),
        onRefresh: _load,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.80,
          ),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final bp = _filtered[i];
            final requiredVip =
                _metaVipLevel(bp);
            final isVipLocked =
                requiredVip > 0 && _userVipLevel < requiredVip;
            return _BadgeCard(
              bp: bp,
              isArabic: context.isArabic,
              isVipLocked: isVipLocked,
              requiredVipLevel: requiredVip,
              onEquip: () => _equip(bp),
            );
          },
        ),
      );
    }

    // All other filters (all, avatar_frame) use a vertical list.
    return RefreshIndicator(
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final bp = _filtered[i];
          final requiredVip = _metaVipLevel(bp);
          final isVipLocked = requiredVip > 0 && _userVipLevel < requiredVip;
          if (bp.isFrame) {
            return _FrameCard(
              bp: bp,
              isArabic: context.isArabic,
              isVipLocked: isVipLocked,
              requiredVipLevel: requiredVip,
              onEquip: () => _equip(bp),
            );
          }
          if (bp.itemType == 'entrance_banner') {
            return _EntranceBannerCard(
              bp: bp,
              isArabic: context.isArabic,
              isVipLocked: isVipLocked,
              requiredVipLevel: requiredVip,
              onEquip: () => _equip(bp),
            );
          }
          return _BackpackItemCard(
            bp: bp,
            isArabic: context.isArabic,
            onEquip: () => _equip(bp),
          );
        },
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
            context.isArabic ? 'إعادة المحاولة' : 'Retry',
            style: const TextStyle(color: Color(0xFFF0C15A)),
          ),
        ),
      ],
    ),
  );

  Widget _buildEmpty() {
    final isFrames = _filter == 'avatar_frame';
    final isBadges = _filter == 'badge';
    final isBanners = _filter == 'entrance_banner';

    final IconData icon = isFrames
        ? Icons.filter_frames_rounded
        : isBadges
        ? Icons.workspace_premium_rounded
        : isBanners
        ? Icons.auto_awesome_rounded
        : Icons.backpack_rounded;

    final String title = context.isArabic
        ? isFrames
              ? 'لا توجد إطارات'
              : isBadges
              ? 'لا توجد شارات'
              : isBanners
              ? 'لا توجد لافتات دخول'
              : 'حقيبتك فارغة'
        : isFrames
        ? 'No frames yet'
        : isBadges
        ? 'No badges yet'
        : isBanners
        ? 'No entrance banners yet'
        : 'Your backpack is empty';

    final String subtitle = context.isArabic
        ? isFrames
              ? 'احصل على إطارات حصرية من المتجر ومكافآت VIP.'
              : isBadges
              ? 'اجمع الشارات من الفعاليات ومكافآت VIP وعروض المتجر.'
              : isBanners
              ? 'افتح تأثيرات الدخول من مكافآت VIP والفعاليات وعروض المتجر.'
              : 'تفضل بزيارة المتجر للحصول على المزيد'
        : isFrames
        ? 'Get exclusive avatar frames from the store and VIP rewards.'
        : isBadges
        ? 'Collect badges from events, VIP rewards, and store offers.'
        : isBanners
        ? 'Unlock entrance effects from VIP rewards, events, and store offers.'
        : 'Visit the store to get more items';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF4A3470), size: 56),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF7A6890),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF4A3470), fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          _GoToStoreButton(isArabic: context.isArabic),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Go to Store CTA
// ---------------------------------------------------------------------------

class _GoToStoreButton extends StatelessWidget {
  const _GoToStoreButton({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoreScreen(isArabic: isArabic)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6B2FD4), Color(0xFF9B4DFF)],
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          isArabic ? 'الذهاب إلى المتجر' : 'Go to Store',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Frame card — premium layout with VIP lock support
// ---------------------------------------------------------------------------

class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.bp,
    required this.isArabic,
    required this.isVipLocked,
    required this.requiredVipLevel,
    required this.onEquip,
  });
  final BackpackItem bp;
  final bool isArabic;
  final bool isVipLocked;
  final int requiredVipLevel;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final tierColors = requiredVipLevel > 0
        ? VipTierColors.of(requiredVipLevel)
        : null;

    final borderColor = bp.equipped
        ? const Color(0xFFF0C15A)
        : isVipLocked && tierColors != null
        ? tierColors.border.withValues(alpha: 0.6)
        : const Color(0xFF4A3470);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: bp.equipped ? 1.5 : 1),
        gradient: bp.equipped
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1030),
                  const Color(0xFF0F0820).withValues(alpha: 0.95),
                ],
              )
            : null,
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large avatar preview
          _FramePreview(bp: bp, isVipLocked: isVipLocked),
          const SizedBox(width: 16),

          // Info column
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Name + Equipped chip
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Expanded(
                      child: Text(
                        bp.item.localName(isArabic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isVipLocked
                              ? const Color(0xFF7A6890)
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (bp.equipped) ...[
                      const SizedBox(width: 8),
                      _EquippedBadge(isArabic: isArabic),
                    ],
                  ],
                ),
                const SizedBox(height: 4),

                // Description
                Text(
                  bp.item.localDescription(isArabic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A6890),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),

                // Bottom action row
                if (isVipLocked)
                  _VipLockRow(
                    isArabic: isArabic,
                    requiredLevel: requiredVipLevel,
                  )
                else if (!bp.equipped)
                  _EquipButton(isArabic: isArabic, onEquip: onEquip),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FramePreview extends StatelessWidget {
  const _FramePreview({required this.bp, required this.isVipLocked});
  final BackpackItem bp;
  final bool isVipLocked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AvatarWithFrame(
            imageUrl: null,
            radius: 36,
            frameKey: bp.item.frameKey,
            compact: false,
          ),
          if (isVipLocked)
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(44),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }
}

class _EquippedBadge extends StatelessWidget {
  const _EquippedBadge({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0C15A).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        isArabic ? 'مفعّل' : 'Equipped',
        style: const TextStyle(
          color: Color(0xFFF0C15A),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EquipButton extends StatelessWidget {
  const _EquipButton({required this.isArabic, required this.onEquip});
  final bool isArabic;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: onEquip,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4B168C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Text(
          isArabic ? 'تفعيل' : 'Equip',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
      ),
    );
  }
}

class _VipLockRow extends StatelessWidget {
  const _VipLockRow({required this.isArabic, required this.requiredLevel});
  final bool isArabic;
  final int requiredLevel;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        VipTierChip(level: requiredLevel, compact: true),
        const SizedBox(width: 6),
        Text(
          isArabic ? 'مطلوب' : 'Required',
          style: const TextStyle(
            color: Color(0xFF7A6890),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Badge card — 2-column grid layout with VIP lock and equip support
// ---------------------------------------------------------------------------

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({
    required this.bp,
    required this.isArabic,
    required this.isVipLocked,
    required this.requiredVipLevel,
    required this.onEquip,
  });
  final BackpackItem bp;
  final bool isArabic;
  final bool isVipLocked;
  final int requiredVipLevel;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final tierColors = requiredVipLevel > 0
        ? VipTierColors.of(requiredVipLevel)
        : null;

    final borderColor = bp.equipped
        ? const Color(0xFFF0C15A)
        : isVipLocked && tierColors != null
        ? tierColors.border.withValues(alpha: 0.6)
        : const Color(0xFF4A3470);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: bp.equipped ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Badge preview
            _BadgePreview(bp: bp, isVipLocked: isVipLocked),
            const SizedBox(height: 10),

            // Rarity / type chip
            _BadgeMetaChip(bp: bp, isArabic: isArabic),
            const SizedBox(height: 6),

            // Name
            Text(
              bp.item.localName(isArabic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isVipLocked ? const Color(0xFF5A4870) : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),

            const Spacer(),

            // Bottom: equipped / locked / equip
            if (bp.equipped)
              _EquippedBadge(isArabic: isArabic)
            else if (isVipLocked)
              _VipLockRow(isArabic: isArabic, requiredLevel: requiredVipLevel)
            else
              _FullWidthEquipButton(isArabic: isArabic, onEquip: onEquip),
          ],
        ),
      ),
    );
  }
}

class _BadgePreview extends StatelessWidget {
  const _BadgePreview({required this.bp, required this.isVipLocked});
  final BackpackItem bp;
  final bool isVipLocked;

  @override
  Widget build(BuildContext context) {
    final imageUrl = (bp.item.metadata['image_url'] as String?)?.trim();

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isVipLocked
                    ? [const Color(0xFF1E1430), const Color(0xFF130D20)]
                    : [const Color(0xFF4B168C), const Color(0xFF8B26D9)],
              ),
              border: Border.all(
                color: isVipLocked
                    ? const Color(0xFF2A1A40)
                    : const Color(0xFF6B2FD4).withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context2, err, stack) => const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFF0C15A),
                        size: 30,
                      ),
                    ),
                  )
                : Icon(
                    Icons.workspace_premium_rounded,
                    color: isVipLocked
                        ? const Color(0xFF3A2850)
                        : const Color(0xFFF0C15A),
                    size: 30,
                  ),
          ),
          if (isVipLocked)
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.50),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeMetaChip extends StatelessWidget {
  const _BadgeMetaChip({required this.bp, required this.isArabic});
  final BackpackItem bp;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final rarity = bp.item.metadata['rarity'] as String?;
    final category = bp.item.metadata['category'] as String?;
    final label = (rarity ?? category ?? '').trim();
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF4B168C).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF6B2FD4).withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFB98EFF),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entrance banner card — wide premium card with banner preview
// ---------------------------------------------------------------------------

class _EntranceBannerCard extends StatelessWidget {
  const _EntranceBannerCard({
    required this.bp,
    required this.isArabic,
    required this.isVipLocked,
    required this.requiredVipLevel,
    required this.onEquip,
  });
  final BackpackItem bp;
  final bool isArabic;
  final bool isVipLocked;
  final int requiredVipLevel;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final tierColors = requiredVipLevel > 0
        ? VipTierColors.of(requiredVipLevel)
        : null;

    final borderColor = bp.equipped
        ? const Color(0xFFF0C15A)
        : isVipLocked && tierColors != null
        ? tierColors.border.withValues(alpha: 0.55)
        : const Color(0xFF4A3470);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: bp.equipped ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wide banner preview at the top
          _EntranceBannerPreview(bp: bp, isVipLocked: isVipLocked),

          // Info section below preview
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Name row + equipped chip
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Expanded(
                      child: Text(
                        bp.item.localName(isArabic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isVipLocked
                              ? const Color(0xFF7A6890)
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (bp.equipped) ...[
                      const SizedBox(width: 8),
                      _EquippedBadge(isArabic: isArabic),
                    ],
                  ],
                ),
                const SizedBox(height: 4),

                // Description
                Text(
                  bp.item.localDescription(isArabic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A6890),
                    fontSize: 12,
                  ),
                ),

                // Rarity / type chip if present (returns SizedBox.shrink when empty)
                const SizedBox(height: 6),
                _BadgeMetaChip(bp: bp, isArabic: isArabic),
                const SizedBox(height: 10),

                // Action row
                if (isVipLocked)
                  _VipLockRow(
                    isArabic: isArabic,
                    requiredLevel: requiredVipLevel,
                  )
                else if (!bp.equipped)
                  _FullWidthEquipButton(isArabic: isArabic, onEquip: onEquip),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntranceBannerPreview extends StatelessWidget {
  const _EntranceBannerPreview({
    required this.bp,
    required this.isVipLocked,
  });
  final BackpackItem bp;
  final bool isVipLocked;

  @override
  Widget build(BuildContext context) {
    final imageUrl = (bp.item.metadata['image_url'] as String?)?.trim();

    return SizedBox(
      height: 120,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient or network image
          if (imageUrl != null && imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => _BannerGradientBg(
                isVipLocked: isVipLocked,
              ),
            )
          else
            _BannerGradientBg(isVipLocked: isVipLocked),

          // Sparkle icon when no image
          if (imageUrl == null || imageUrl.isEmpty)
            Center(
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 40,
                color: isVipLocked
                    ? const Color(0xFF3A2850)
                    : const Color(0xFFF0C15A).withValues(alpha: 0.85),
              ),
            ),

          // Lock overlay
          if (isVipLocked)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: const Center(
                child: Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),

          // Bottom fade for text legibility
          if (!isVipLocked)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 48,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BannerGradientBg extends StatelessWidget {
  const _BannerGradientBg({required this.isVipLocked});
  final bool isVipLocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isVipLocked
              ? [const Color(0xFF0E0818), const Color(0xFF120D1E)]
              : [
                  const Color(0xFF3B0E8A),
                  const Color(0xFF6B2FD4),
                  const Color(0xFF9B3FA0),
                ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-width equip button — used by grid/banner cards where width fills the card
// ---------------------------------------------------------------------------

class _FullWidthEquipButton extends StatelessWidget {
  const _FullWidthEquipButton({required this.isArabic, required this.onEquip});
  final bool isArabic;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 34,
      child: ElevatedButton(
        onPressed: onEquip,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4B168C),
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Text(
          isArabic ? 'تفعيل' : 'Equip',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic backpack item card (non-frame/non-badge types + All-tab fallback)
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                          isArabic ? 'مفعّل' : 'Equipped',
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
                        isArabic ? 'تفعيل' : 'Equip',
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
