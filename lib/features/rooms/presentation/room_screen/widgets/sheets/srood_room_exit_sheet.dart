/// Room exit options sheet: minimize, exit, and (owner-only) close room.
/// Pops a [SroodRoomExitAction] for the screen to act on.
library;

import 'package:flutter/material.dart';

import '../../../theme/srood_room_theme.dart';

enum SroodRoomExitAction { minimize, exit, closeRoom }

class SroodRoomExitSheet extends StatelessWidget {
  const SroodRoomExitSheet({
    required this.isOwner,
    required this.isArabic,
    super.key,
  });

  final bool isOwner;
  final bool isArabic;

  String _t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compactHeight = media.size.height < 760;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        decoration: const BoxDecoration(
          color: SroodRoomColors.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SroodRoomDims.radiusSheet),
          ),
          border: Border(
            top: BorderSide(color: SroodRoomColors.violetSoft, width: 1),
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            SroodRoomDims.space20,
            compactHeight ? SroodRoomDims.space12 : SroodRoomDims.space16,
            SroodRoomDims.space20,
            media.viewPadding.bottom + SroodRoomDims.space20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grabber
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(
                    SroodRoomDims.radiusPill,
                  ),
                ),
              ),
              SizedBox(height: compactHeight ? 10 : SroodRoomDims.space16),
              Text(
                _t('خيارات الغرفة', 'Room Options'),
                style: SroodRoomText.title.copyWith(fontSize: 16),
              ),
              SizedBox(height: compactHeight ? 12 : SroodRoomDims.space20),

              // Minimize
              _ExitOption(
                icon: Icons.picture_in_picture_alt_rounded,
                iconColor: SroodRoomColors.violet,
                iconBg: const Color(0xFF2A0E50),
                title: _t('تصغير', 'Minimize'),
                subtitle: _t(
                  'تصفح التطبيق مع البقاء في الغرفة',
                  'Browse the app while staying in the room',
                ),
                onTap: () =>
                    Navigator.of(context).pop(SroodRoomExitAction.minimize),
              ),
              const SizedBox(height: 10),

              // Exit room — always available; even the owner can leave
              // without closing.
              _ExitOption(
                icon: Icons.logout_rounded,
                iconColor: const Color(0xFFFF6B6B),
                iconBg: const Color(0xFF3A1010),
                title: _t('مغادرة الغرفة', 'Exit Room'),
                subtitle: _t(
                  'ستغادر الغرفة وستبقى مفتوحة للآخرين',
                  'Leave the room. It stays open for others.',
                ),
                onTap: () => Navigator.of(context).pop(SroodRoomExitAction.exit),
              ),

              // Close room — owner only
              if (isOwner) ...[
                const SizedBox(height: 10),
                _ExitOption(
                  icon: Icons.cancel_rounded,
                  iconColor: const Color(0xFFFF3B3B),
                  iconBg: const Color(0xFF3A0808),
                  title: _t('إغلاق الغرفة', 'Close Room'),
                  subtitle: _t(
                    'سيتم إغلاق الغرفة لجميع المشاركين',
                    'End the room for all participants',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(SroodRoomExitAction.closeRoom),
                ),
              ],

              SizedBox(height: compactHeight ? 8 : SroodRoomDims.space12),

              // Cancel
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    _t('إلغاء', 'Cancel'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: SroodRoomDims.textLg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExitOption extends StatelessWidget {
  const _ExitOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SroodRoomDims.gutter,
          vertical: SroodRoomDims.space12,
        ),
        decoration: SroodRoomDecor.glass(),
        child: Row(
          children: [
            Container(
              width: SroodRoomDims.touchTarget,
              height: SroodRoomDims.touchTarget,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
              ),
              child: Icon(icon, color: iconColor, size: SroodRoomDims.iconLg - 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: SroodRoomDims.textSm,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.25),
              size: SroodRoomDims.iconMd,
            ),
          ],
        ),
      ),
    );
  }
}
