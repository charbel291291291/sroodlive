import 'package:flutter/material.dart';

import '../models/profile_hub_models.dart';
import '../services/badge_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class BadgeScreen extends StatefulWidget {
  const BadgeScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<BadgeScreen> createState() => _BadgeScreenState();
}

class _BadgeScreenState extends State<BadgeScreen> {
  final BadgeService _service = const BadgeService();
  late Future<List<BadgeItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getBadges();
  }

  void _retry() => setState(() => _future = _service.getBadges());

  Future<void> _equip(BadgeItem badge) async {
    await _service.equipBadge(badge.id);
    _retry();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'الشارات' : 'Badge',
      isArabic: isArabic,
      children: [
        FutureBuilder<List<BadgeItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return ProfileErrorState(
                message: snapshot.error?.toString() ?? 'Failed to load badges.',
                onRetry: _retry,
                isArabic: isArabic,
              );
            }

            final badges = snapshot.data!;
            if (badges.isEmpty) {
              return ProfileEmptyState(
                icon: Icons.verified_rounded,
                title: isArabic ? 'لا توجد شارات' : 'No badges yet',
                description: isArabic
                    ? 'ستظهر الشارات المتاحة والمقفلة هنا.'
                    : 'Owned and locked badges will appear here.',
                isArabic: isArabic,
              );
            }

            final equipped = badges.where((badge) => badge.isEquipped).toList();

            return Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (equipped.isNotEmpty)
                  ProfileInfoCard(
                    icon: Icons.workspace_premium_rounded,
                    title: isArabic ? 'الشارة المجهزة' : 'Equipped badge',
                    body: equipped.first.name,
                    isArabic: isArabic,
                  ),
                ProfileSectionTitle(
                  title: isArabic ? 'كل الشارات' : 'All badges',
                  isArabic: isArabic,
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: badges.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  itemBuilder: (context, index) {
                    final badge = badges[index];
                    return _BadgeGridItem(
                      badge: badge,
                      isArabic: isArabic,
                      onEquip: badge.isOwned && !badge.isEquipped
                          ? () => _equip(badge)
                          : null,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BadgeGridItem extends StatelessWidget {
  const _BadgeGridItem({
    required this.badge,
    required this.isArabic,
    required this.onEquip,
  });

  final BadgeItem badge;
  final bool isArabic;
  final VoidCallback? onEquip;

  @override
  Widget build(BuildContext context) {
    final lockedText = [
      if (badge.requiredLevel != null) 'Lv ${badge.requiredLevel}',
      if (badge.requiredVipLevel != null) 'VIP ${badge.requiredVipLevel}',
      if (badge.priceCoins > 0) '${badge.priceCoins} coins',
    ].join(' / ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: profileHubCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: badge.isEquipped ? profileHubGold : profileHubBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Icon(
            badge.isOwned ? Icons.verified_rounded : Icons.lock_rounded,
            color: badge.isOwned ? profileHubGold : profileHubMuted,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            badge.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            badge.isOwned
                ? (badge.isEquipped
                      ? (isArabic ? 'مجهزة' : 'Equipped')
                      : badge.rarity)
                : (lockedText.isEmpty
                      ? (isArabic ? 'مقفلة' : 'Locked')
                      : lockedText),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: profileHubMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (onEquip != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onEquip,
                child: Text(isArabic ? 'تجهيز' : 'Equip'),
              ),
            ),
        ],
      ),
    );
  }
}
