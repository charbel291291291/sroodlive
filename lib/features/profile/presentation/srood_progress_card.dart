/// Progress & status card: current level, current XP, XP required for the
/// next level, percentage, next milestone title, plus the VIP and
/// Charm/Wealth navigation tiles. Values come straight from the existing
/// [UserLevel] model — no recalculation.
///
/// Fixes the old "0 points to the next level" contradiction: at max level
/// the card says so, at 100% it says "ready for next level", otherwise it
/// shows the authoritative remaining XP.
library;

import 'package:flutter/material.dart';

import '../../profile_hub/models/profile_hub_models.dart';
import 'srood_profile_theme.dart';

class SroodProgressCard extends StatelessWidget {
  const SroodProgressCard({
    required this.isArabic,
    required this.userLevel,
    required this.vipLevel,
    required this.charmLevel,
    required this.wealthLevel,
    required this.onLevelTap,
    required this.onVipTap,
    required this.onWealthTap,
    super.key,
  });

  final bool isArabic;
  final UserLevel? userLevel;
  final int vipLevel;
  final int? charmLevel;
  final int? wealthLevel;
  final VoidCallback onLevelTap;
  final VoidCallback onVipTap;
  final VoidCallback onWealthTap;

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final level = userLevel?.level ?? 1;
    final progress = (userLevel?.levelProgress ?? 0).clamp(0.0, 1.0);
    final xp = userLevel?.xp;
    final requiredXp = userLevel?.nextLevelRequiredXp;
    final remaining = userLevel?.xpToNextLevel;
    final nextTitle = userLevel?.nextLevelTitle;
    final isMax = userLevel?.isMaxLevel == true;

    // Status line without contradictions.
    final String statusLine;
    if (isMax) {
      statusLine = isArabic
          ? 'تم الوصول لأعلى مستوى حالي'
          : 'Maximum current level reached';
    } else if (progress >= 1.0 || (remaining != null && remaining <= 0)) {
      statusLine = isArabic ? 'جاهز للمستوى التالي' : 'Ready for next level';
    } else if (remaining != null) {
      statusLine = isArabic
          ? '${_fmt(remaining)} XP للمستوى التالي'
          : '${_fmt(remaining)} XP to the next level';
    } else {
      statusLine = isArabic ? 'اكسب XP من نشاطك' : 'Earn XP through activity';
    }

    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: sroodProfileCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Level headline + XP figures ───────────────────────────────
            Semantics(
              label: isArabic
                  ? 'المستوى $level، $statusLine'
                  : 'Level $level, $statusLine',
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(
                  SroodProfileDims.innerRadius,
                ),
                onTap: onLevelTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: SroodProfileColors.violet.withValues(
                                alpha: 0.14,
                              ),
                              border: Border.all(
                                color: SroodProfileColors.violet.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.military_tech_rounded,
                              color: Color(0xFFC590FF),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isArabic ? 'المستوى $level' : 'Level $level',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: SroodProfileColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (xp != null)
                                  Text(
                                    requiredXp != null && !isMax
                                        ? '${_fmt(xp)} / ${_fmt(requiredXp)} XP'
                                        : '${_fmt(xp)} XP',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SroodProfileText.caption,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: const TextStyle(
                              color: Color(0xFFC590FF),
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Premium progress bar — subtle animation ──────────
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          SroodProfileDims.chipRadius,
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: progress),
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (_, value, _) => Stack(
                            children: [
                              Container(
                                height: 9,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              FractionallySizedBox(
                                widthFactor: value.clamp(0.0, 1.0),
                                child: Container(
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        SroodProfileColors.violetSoft,
                                        SroodProfileColors.violet,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              statusLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.66),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (nextTitle != null && !isMax) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                isArabic ? '→ $nextTitle' : '→ $nextTitle',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SroodProfileText.caption.copyWith(
                                  color: SroodProfileColors.violet.withValues(
                                    alpha: 0.9,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── VIP + Charm/Wealth navigation tiles ───────────────────────
            Row(
              children: [
                Expanded(
                  child: _StatusTile(
                    icon: Icons.workspace_premium_rounded,
                    label: 'VIP',
                    value: vipLevel > 0
                        ? (isArabic ? 'المستوى $vipLevel' : 'Level $vipLevel')
                        : (isArabic ? 'غير نشط' : 'Not active'),
                    accent: SroodProfileColors.gold,
                    onTap: onVipTap,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusTile(
                    icon: Icons.diamond_rounded,
                    label: isArabic ? 'السحر والثروة' : 'Charm & Wealth',
                    value: charmLevel == null && wealthLevel == null
                        ? (isArabic ? 'ابدأ التقدم' : 'Start progressing')
                        : '${charmLevel ?? 0} / ${wealthLevel ?? 0}',
                    accent: const Color(0xFF55B8FF),
                    onTap: onWealthTap,
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

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(SroodProfileDims.innerRadius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 76,
            minWidth: SroodProfileDims.touchTarget,
          ),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(SroodProfileDims.innerRadius),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, color: accent, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SroodProfileColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
