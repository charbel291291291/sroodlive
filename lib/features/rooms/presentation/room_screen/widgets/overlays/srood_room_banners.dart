/// Header-zone event banners: gift support, VIP entry (prestige-styled),
/// and regular user entry. Shown one-at-a-time by the screen state via
/// ValueNotifiers with priority gift > VIP > entry.
library;

import 'package:flutter/material.dart';

import 'package:srood_live/shared/widgets/vip_badge.dart';

import '../../../../../../core/vip/vip_spec.dart';
import '../../../../models/room_gift.dart';
import '../../../../models/room_member.dart';
import '../../../../services/gifts_service.dart';
import '../../../../utils/vip_room_features.dart';
import '../../../theme/srood_room_theme.dart';
import '../common/srood_room_avatar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Gift support banner
// ─────────────────────────────────────────────────────────────────────────────

class SroodGiftRoomBanner extends StatelessWidget {
  const SroodGiftRoomBanner({
    required this.gift,
    required this.isArabic,
    required this.onProfileTap,
    super.key,
  });

  final RoomGiftTransaction gift;
  final bool isArabic;
  final ValueChanged<String> onProfileTap;

  @override
  Widget build(BuildContext context) {
    final senderVip = gift.sender?.effectiveVipLevel ?? 0;
    final receiverVip = gift.receiver?.effectiveVipLevel ?? 0;
    final text = isArabic
        ? '${gift.senderLabel} دعم ${gift.receiverLabel} بهدية ${gift.giftName}'
        : '${gift.senderLabel} supported ${gift.receiverLabel} with ${gift.giftName}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusLg + 2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1A45), Color(0xFF18103A), Color(0xFF0F0820)],
        ),
        border: Border.all(
          color: const Color(0xFFD4A017).withValues(alpha: 0.72),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: SroodRoomColors.gold.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          SroodRoomAvatar(
            avatarUrl: gift.sender?.avatarUrl,
            frameKey: gift.sender?.selectedAvatarFrameKey,
            vipLevel: senderVip,
            size: 38,
            selected: false,
            fallbackIcon: Icons.person_rounded,
            onTap: gift.sender == null
                ? null
                : () => onProfileTap(gift.sender!.userId),
          ),
          const SizedBox(width: SroodRoomDims.space8),
          SroodGiftMiniImage(gift: gift.giftPreview, size: 38),
          const SizedBox(width: SroodRoomDims.space8),
          SroodRoomAvatar(
            avatarUrl: gift.receiver?.avatarUrl,
            frameKey: gift.receiver?.selectedAvatarFrameKey,
            vipLevel: receiverVip,
            size: 38,
            selected: true,
            fallbackIcon: Icons.person_rounded,
            onTap: gift.receiver == null
                ? null
                : () => onProfileTap(gift.receiver!.userId),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: senderVip > 0
                        ? VipVisualStyle.nameColor(senderVip, context)
                        : Colors.white,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (senderVip > 0 || receiverVip > 0) ...[
                  const SizedBox(height: SroodRoomDims.space4),
                  Wrap(
                    spacing: SroodRoomDims.space4,
                    children: [
                      if (senderVip > 0)
                        VipBadge(vipLevel: senderVip, compact: true),
                      if (receiverVip > 0)
                        VipBadge(vipLevel: receiverVip, compact: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIP entry banner
// ─────────────────────────────────────────────────────────────────────────────

class SroodVipEntryRoomBanner extends StatefulWidget {
  const SroodVipEntryRoomBanner({
    required this.member,
    required this.isArabic,
    super.key,
  });

  final RoomMember member;
  final bool isArabic;

  @override
  State<SroodVipEntryRoomBanner> createState() =>
      _SroodVipEntryRoomBannerState();
}

class _SroodVipEntryRoomBannerState extends State<SroodVipEntryRoomBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _aura;

  @override
  void initState() {
    super.initState();
    final prestige = VipSpecResolver.resolve(widget.member.effectiveVipLevel);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _aura = Tween<double>(
      begin: 0.65,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (prestige.isElite) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.member.effectiveVipLevel;
    final prestige = VipSpecResolver.resolve(level);
    final isArabic = widget.isArabic;

    final text = isArabic
        ? '${widget.member.fallbackName(isArabic)} دخل الغرفة كـ VIP $level'
        : '${widget.member.fallbackName(isArabic)} entered as VIP $level';

    // Tier-based border radius: more rounded for higher VIP.
    final br = BorderRadius.circular(
      prestige.isElite
          ? 22
          : prestige.entryTier.index >= VipEntryTier.glow.index
          ? 20
          : 16,
    );

    return AnimatedBuilder(
      animation: _aura,
      builder: (ctx, child) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: prestige.isElite ? 12 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: br,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: prestige.bannerGradient,
            ),
            boxShadow: prestige.buildGlowShadows(pulseFactor: _aura.value),
            border: prestige.isElite
                ? Border.all(
                    color: prestige.borderColor.withValues(alpha: 0.60),
                    width: 1.4,
                  )
                : null,
          ),
          child: child,
        );
      },
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Avatar with VIP halo ring
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: prestige.buildGlowShadows(pulseFactor: 0.8),
            ),
            child: SroodRoomAvatar(
              avatarUrl: widget.member.avatarUrl,
              frameKey: widget.member.selectedAvatarFrameKey,
              vipLevel: level,
              size: prestige.isElite ? 42 : 38,
              selected: false,
              fallbackIcon: Icons.person_rounded,
              isOfficialAgent: widget.member.isOfficialAgent,
            ),
          ),
          const SizedBox(width: 10),
          VipBadge(vipLevel: level, compact: true),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: prestige.entryTextColor,
                fontSize: prestige.isElite ? 13 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (prestige.isLegendary) ...[
            const SizedBox(width: SroodRoomDims.space6),
            Icon(
              Icons.local_fire_department_rounded,
              color: prestige.entryTextColor.withValues(alpha: 0.85),
              size: 18,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Regular user entry banner
// ─────────────────────────────────────────────────────────────────────────────

class SroodUserEntryRoomBanner extends StatelessWidget {
  const SroodUserEntryRoomBanner({
    required this.member,
    required this.isArabic,
    super.key,
  });

  final RoomMember member;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final name = member.fallbackName(isArabic);
    final text = isArabic ? '$name دخل الغرفة' : '$name entered the room';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1028).withValues(alpha: 0.92),
            const Color(0xFF28133E).withValues(alpha: 0.86),
          ],
        ),
        border: Border.all(
          color: SroodRoomColors.gold.withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: SroodRoomColors.gold.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          SroodRoomAvatar(
            avatarUrl: member.avatarUrl,
            frameKey: member.selectedAvatarFrameKey,
            vipLevel: member.effectiveVipLevel,
            size: 34,
            selected: false,
            fallbackIcon: Icons.person_rounded,
            isOfficialAgent: member.isOfficialAgent,
          ),
          const SizedBox(width: 10),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SroodRoomColors.gold.withValues(alpha: 0.14),
              border: Border.all(
                color: SroodRoomColors.gold.withValues(alpha: 0.34),
              ),
            ),
            child: const Icon(
              Icons.login_rounded,
              color: SroodRoomColors.gold,
              size: SroodRoomDims.iconSm,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gift mini image (gold medallion)
// ─────────────────────────────────────────────────────────────────────────────

class SroodGiftMiniImage extends StatelessWidget {
  const SroodGiftMiniImage({
    required this.gift,
    required this.size,
    super.key,
  });

  final RoomGift gift;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFD978), Color(0xFFE0A83A), Color(0xFF8B26D9)],
        ),
        boxShadow: [
          BoxShadow(
            color: SroodRoomColors.gold.withValues(alpha: 0.22),
            blurRadius: 10,
          ),
        ],
      ),
      child: Image.network(
        gift.imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            gift.materialIcon,
            color: SroodRoomColors.bg,
            size: size * 0.52,
          );
        },
      ),
    );
  }
}
