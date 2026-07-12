/// One chat feed row: user message bubble with VIP prestige styling, host /
/// agent / VIP badges, image support, plus dedicated renders for system and
/// removed messages. Long-press exposes remove / report actions when the
/// caller grants them.
library;

import 'package:flutter/material.dart';

import '../../../../../../core/vip/vip_spec.dart';
import '../../../../services/room_messages_service.dart';
import '../../../../widgets/agent_identity_badge.dart';
import '../../../theme/srood_room_theme.dart';
import '../common/srood_room_avatar.dart';
import 'srood_chat_image_thumbnail.dart';

class SroodChatMessageRow extends StatefulWidget {
  const SroodChatMessageRow({
    required this.message,
    required this.isArabic,
    this.onProfileTap,
    this.onRemoveTap,
    this.onReportTap,
    super.key,
  });

  final RoomMessage message;
  final bool isArabic;
  final VoidCallback? onProfileTap;
  final VoidCallback? onRemoveTap;
  final VoidCallback? onReportTap;

  @override
  State<SroodChatMessageRow> createState() => _SroodChatMessageRowState();
}

class _SroodChatMessageRowState extends State<SroodChatMessageRow>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    final lvl = widget.message.senderVipLevel;
    if (lvl >= 7) {
      _ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: lvl == 9 ? 1600 : 2200),
      )..repeat(reverse: true);
      _pulse = Tween<double>(
        begin: 0.60,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut));
    } else {
      _pulse = const AlwaysStoppedAnimation(1.0);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isArabic = widget.isArabic;
    final isAgent = msg.senderIsOfficialAgent;

    if (msg.isRemoved) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: SroodRoomDims.space2,
          horizontal: SroodRoomDims.space8,
        ),
        child: Row(
          children: [
            const SizedBox(width: SroodRoomDims.touchTarget),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  isArabic ? '🚫 تم حذف الرسالة' : '🚫 Message removed',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(SroodRoomDims.radiusXl),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              msg.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: SroodRoomDims.textSm,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    final vipLevel = msg.senderVipLevel.clamp(0, 9);
    final prestige = VipSpecResolver.resolve(vipLevel);
    final nameColor = vipLevel > 0
        ? prestige.nameColor
        : const Color(0xFF9BE8FF);
    final isHost = msg.senderRole == 'host';

    final bubble = Padding(
      padding: const EdgeInsets.only(bottom: SroodRoomDims.space4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Official-agent accent rail on the leading edge.
          border: isAgent
              ? Border(
                  left: BorderSide(
                    color: const Color(
                      0xFFE7B85C,
                    ).withValues(alpha: isArabic ? 0.0 : 0.72),
                    width: isArabic ? 0 : 2,
                  ),
                  right: BorderSide(
                    color: const Color(
                      0xFFE7B85C,
                    ).withValues(alpha: isArabic ? 0.72 : 0.0),
                    width: isArabic ? 2 : 0,
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: isAgent ? 5 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              GestureDetector(
                onTap: widget.onProfileTap,
                child: _buildAvatar(prestige, msg, vipLevel),
              ),
              const SizedBox(width: SroodRoomDims.space6),
              Flexible(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (ctx, _) => _buildBubble(
                    ctx,
                    prestige,
                    msg,
                    nameColor,
                    isHost,
                    isArabic,
                    vipLevel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final hasRemove = widget.onRemoveTap != null;
    final hasReport = widget.onReportTap != null;
    if (!hasRemove && !hasReport) return bubble;

    return GestureDetector(
      onLongPress: () {
        if (hasRemove && hasReport) {
          _showMessageActions(context);
        } else if (hasRemove) {
          widget.onRemoveTap!();
        } else {
          widget.onReportTap!();
        }
      },
      child: bubble,
    );
  }

  void _showMessageActions(BuildContext context) {
    final isArabic = widget.isArabic;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SroodRoomColors.bgRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SroodRoomDims.radiusSheet),
        ),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onRemoveTap != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  isArabic ? 'حذف الرسالة' : 'Remove message',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onRemoveTap!();
                },
              ),
            if (widget.onReportTap != null)
              ListTile(
                leading: const Icon(
                  Icons.flag_rounded,
                  color: SroodRoomColors.warning,
                ),
                title: Text(
                  isArabic ? 'إبلاغ عن المستخدم' : 'Report user',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onReportTap!();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(VipSpec prestige, RoomMessage msg, int vipLevel) {
    final hasRing = prestige.avatarRingWidth > 0;
    // Compact 26px avatar keeps the feed light.
    final avatar = SroodRoomAvatar(
      avatarUrl: msg.senderAvatarUrl,
      frameKey: null,
      vipLevel: hasRing ? 0 : vipLevel,
      size: 26,
      selected: false,
      fallbackIcon: Icons.person_rounded,
      isOfficialAgent: msg.senderIsOfficialAgent,
    );
    if (!hasRing) return avatar;

    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: prestige.avatarRingColor,
                  width: prestige.avatarRingWidth,
                ),
                boxShadow: vipLevel >= 4
                    ? [
                        BoxShadow(
                          color: prestige.avatarRingColor.withValues(
                            alpha: 0.40,
                          ),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          avatar,
        ],
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    VipSpec prestige,
    RoomMessage msg,
    Color nameColor,
    bool isHost,
    bool isArabic,
    int vipLevel,
  ) {
    final glowFactor = _pulse.value;
    final isRtl = isArabic;
    final crossAxis = isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final cr = prestige.cardCornerRadius;
    final tailR = vipLevel >= 3 ? cr : 4.0;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(isRtl ? tailR : cr),
      topRight: Radius.circular(isRtl ? cr : tailR),
      bottomLeft: Radius.circular(cr),
      bottomRight: Radius.circular(cr),
    );

    final shadows = prestige.buildGlowShadows(pulseFactor: glowFactor);
    final isGradient = prestige.bubbleGradient[0] != prestige.bubbleGradient[1];
    final deco = isGradient
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: prestige.bubbleGradient,
            ),
            borderRadius: radius,
            border: Border.all(
              color: prestige.borderColor,
              width: prestige.borderWidth,
            ),
            boxShadow: shadows,
          )
        : BoxDecoration(
            color: prestige.surfaceTint,
            borderRadius: radius,
            border: Border.all(
              color: prestige.borderColor,
              width: prestige.borderWidth,
            ),
            boxShadow: shadows,
          );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SroodRoomDims.space8,
        vertical: 5,
      ),
      decoration: deco,
      child: Column(
        crossAxisAlignment: crossAxis,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Flexible(
                child: Text(
                  msg.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: SroodRoomDims.textSm,
                    fontWeight: prestige.nameFontWeight,
                  ),
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: SroodRoomDims.space4),
                _buildBadge(
                  'HOST',
                  SroodRoomColors.gold,
                  const Color(0x30F0C15A),
                  borderColor: SroodRoomColors.gold.withValues(alpha: 0.40),
                ),
              ],
              if (msg.senderIsOfficialAgent) ...[
                const SizedBox(width: SroodRoomDims.space4),
                const AgentBadge(compact: true),
              ],
              if (vipLevel > 0) ...[
                const SizedBox(width: 3),
                _buildBadge(
                  'VIP $vipLevel',
                  prestige.badgeTextColor,
                  prestige.badgeGradient.first.withValues(alpha: 0.22),
                  borderColor: prestige.borderColor.withValues(alpha: 0.50),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          if (msg.isImage && msg.imageUrl != null)
            SroodChatImageThumbnail(imageUrl: msg.imageUrl!)
          else
            Text(
              msg.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.25,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBadge(
    String label,
    Color textColor,
    Color bg, {
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 0.6)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
