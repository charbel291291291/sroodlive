/// Social stats card — Friends / Following / Followers as three equal,
/// fully-tappable columns with dividers, a large numeric value, and a small
/// label. Navigation callbacks are owned by the screen.
library;

import 'package:flutter/material.dart';

import 'srood_profile_theme.dart';

class SroodSocialStatsCard extends StatelessWidget {
  const SroodSocialStatsCard({
    required this.isArabic,
    required this.friends,
    required this.following,
    required this.followers,
    this.onFriendsTap,
    this.onFollowingTap,
    this.onFollowersTap,
    super.key,
  });

  final bool isArabic;
  final int friends;
  final int following;
  final int followers;
  final VoidCallback? onFriendsTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: sroodProfileCard(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SroodProfileDims.cardRadius),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Expanded(
              child: _StatColumn(
                value: _fmt(friends),
                label: isArabic ? 'الأصدقاء' : 'Friends',
                icon: Icons.people_rounded,
                onTap: onFriendsTap,
              ),
            ),
            const _Divider(),
            Expanded(
              child: _StatColumn(
                value: _fmt(following),
                label: isArabic ? 'يتابع' : 'Following',
                icon: Icons.person_add_rounded,
                onTap: onFollowingTap,
              ),
            ),
            const _Divider(),
            Expanded(
              child: _StatColumn(
                value: _fmt(followers),
                label: isArabic ? 'المتابعون' : 'Followers',
                icon: Icons.person_rounded,
                onTap: onFollowersTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: SroodProfileDims.touchTarget + 20,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SroodProfileText.sectionValue,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 11,
                    color: onTap != null
                        ? SroodProfileColors.gold.withValues(alpha: 0.8)
                        : SroodProfileColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SroodProfileText.label,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}
