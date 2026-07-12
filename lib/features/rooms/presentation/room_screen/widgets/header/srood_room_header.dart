/// Compact premium room header — one glass bar carrying the whole top zone:
/// exit, room identity (avatar / title / copyable code), level badge, wallet,
/// online count, and owner/host tools. Replaces the legacy AppBar +
/// `_CompactRoomHeader` pair with a single row plus an optional announcement
/// strip.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:srood_live/shared/widgets/srood_toast.dart';

import '../../../../models/room.dart';
import '../../../theme/srood_room_theme.dart';

class SroodRoomHeader extends StatelessWidget {
  const SroodRoomHeader({
    required this.room,
    required this.roomName,
    required this.roomLevel,
    required this.avatarUrl,
    required this.memberCount,
    required this.walletCoins,
    required this.isHost,
    required this.isOwner,
    required this.isArabic,
    required this.leaving,
    required this.onExitTap,
    required this.onLevelTap,
    this.onManagementTap,
    this.announcement,
    super.key,
  });

  final Room room;
  final String roomName;
  final int roomLevel;
  final String? avatarUrl;
  final int memberCount;
  final int walletCoins;
  final bool isHost;
  final bool isOwner;
  final bool isArabic;
  final bool leaving;
  final VoidCallback onExitTap;
  final VoidCallback onLevelTap;
  final VoidCallback? onManagementTap;
  final String? announcement;

  // 5-digit public code, or last 6 chars of UUID for legacy rooms.
  String get _shortRoomId {
    if (room.roomCode != null && room.roomCode!.isNotEmpty) {
      return room.roomCode!;
    }
    final id = room.id.replaceAll('-', '');
    return id.length > 6
        ? id.substring(id.length - 6).toUpperCase()
        : id.toUpperCase();
  }

  Color get _levelColor {
    if (roomLevel >= 9) return const Color(0xFFFFD700);
    if (roomLevel >= 7) return SroodRoomColors.gold;
    if (roomLevel >= 5) return const Color(0xFFE8A83A);
    if (roomLevel >= 3) return const Color(0xFFB48EE0);
    return const Color(0xFF9B72CF);
  }

  @override
  Widget build(BuildContext context) {
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDir,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(
              horizontal: SroodRoomDims.space2,
              vertical: SroodRoomDims.space4,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: SroodRoomDims.space8,
              vertical: SroodRoomDims.space6,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.60),
                  SroodRoomColors.bgRaised.withValues(alpha: 0.72),
                ],
              ),
              borderRadius: BorderRadius.circular(SroodRoomDims.radiusLg),
              border: Border.all(color: SroodRoomColors.glassBorder),
            ),
            child: Row(
              children: [
                // ── Exit (back position, RTL-aware) ─────────────────────────
                _HeaderIconButton(
                  icon: leaving ? null : Icons.logout_rounded,
                  spinner: leaving,
                  color: SroodRoomColors.danger,
                  semanticLabel: isArabic ? 'مغادرة الغرفة' : 'Leave room',
                  onTap: leaving ? null : onExitTap,
                ),
                const SizedBox(width: SroodRoomDims.space6),

                // ── Room avatar ─────────────────────────────────────────────
                Container(
                  width: 36,
                  height: 36,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: SroodRoomColors.glassViolet,
                    borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
                    border: Border.all(
                      color: SroodRoomColors.violet.withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                  ),
                  child: avatarUrl?.isNotEmpty == true
                      ? Image.network(
                          avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, e, s) => const Icon(
                            Icons.mic_rounded,
                            color: SroodRoomColors.violet,
                            size: SroodRoomDims.iconMd,
                          ),
                        )
                      : const Icon(
                          Icons.mic_rounded,
                          color: SroodRoomColors.violet,
                          size: SroodRoomDims.iconMd,
                        ),
                ),
                const SizedBox(width: SroodRoomDims.space8),

                // ── Title + code + host/coins line ──────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        roomName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SroodRoomText.title.copyWith(
                          fontSize: SroodRoomDims.textMd,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: _RoomCodeChip(
                              shortId: _shortRoomId,
                              isArabic: isArabic,
                            ),
                          ),
                          const SizedBox(width: SroodRoomDims.space4),
                          _MiniPill(
                            icon: Icons.monetization_on_rounded,
                            label: walletCoins > 999
                                ? '${(walletCoins / 1000).toStringAsFixed(1)}k'
                                : walletCoins.toString(),
                            color: SroodRoomColors.gold,
                          ),
                          if (isHost) ...[
                            const SizedBox(width: SroodRoomDims.space4),
                            _MiniPill(
                              icon: Icons.admin_panel_settings_rounded,
                              label: isArabic ? 'مضيف' : 'Host',
                              color: SroodRoomColors.gold,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SroodRoomDims.space6),

                // ── Right cluster: level, online, tools ─────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: onLevelTap,
                      child: _LevelBadge(
                        level: roomLevel,
                        levelColor: _levelColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _MiniPill(
                      icon: Icons.people_alt_rounded,
                      label: memberCount.toString(),
                      color: SroodRoomColors.cyan,
                    ),
                  ],
                ),
                if (onManagementTap != null && (isOwner || isHost)) ...[
                  const SizedBox(width: SroodRoomDims.space6),
                  _HeaderIconButton(
                    icon: Icons.manage_accounts_rounded,
                    color: SroodRoomColors.textSecondary,
                    semanticLabel: isArabic ? 'إدارة الغرفة' : 'Room management',
                    onTap: onManagementTap,
                  ),
                ],
              ],
            ),
          ),

          // ── Announcement strip ────────────────────────────────────────────
          if (announcement != null && announcement!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: SroodRoomDims.space4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: SroodRoomDims.space12,
                  vertical: SroodRoomDims.space6,
                ),
                decoration: BoxDecoration(
                  color: SroodRoomColors.bgRaised,
                  borderRadius: BorderRadius.circular(SroodRoomDims.radiusMd),
                  border: Border.all(
                    color: SroodRoomColors.violetSoft.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.campaign_rounded,
                      color: SroodRoomColors.gold,
                      size: SroodRoomDims.iconSm,
                    ),
                    const SizedBox(width: SroodRoomDims.space8),
                    Expanded(
                      child: Text(
                        announcement!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SroodRoomText.body.copyWith(
                          fontSize: SroodRoomDims.textSm,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.color,
    required this.semanticLabel,
    this.icon,
    this.spinner = false,
    this.onTap,
  });

  final IconData? icon;
  final bool spinner;
  final Color color;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          // Visual is compact; hit target stays at the 44px floor via the
          // parent row height + this width.
          width: SroodRoomDims.touchTarget,
          height: SroodRoomDims.touchTarget,
          child: Center(
            child: Container(
              width: SroodRoomDims.controlVisual - 4,
              height: SroodRoomDims.controlVisual - 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.14),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: spinner
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: color, size: SroodRoomDims.iconMd),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomCodeChip extends StatelessWidget {
  const _RoomCodeChip({required this.shortId, required this.isArabic});

  final String shortId;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: shortId));
        if (context.mounted) {
          SroodToast.show(
            context,
            isArabic ? 'تم نسخ كود الغرفة' : 'Room code copied',
            type: SroodToastType.success,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: SroodRoomColors.cyan.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusSm - 2),
          border: Border.all(
            color: SroodRoomColors.cyan.withValues(alpha: 0.20),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.grid_3x3_rounded,
              size: 8,
              color: SroodRoomColors.cyan,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                shortId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: SroodRoomColors.cyan,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.copy_rounded,
              size: 8,
              color: SroodRoomColors.cyan.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.levelColor});

  final int level;
  final Color levelColor;

  @override
  Widget build(BuildContext context) {
    final isElite = level >= 9;
    final isRoyal = level >= 7;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isElite
              ? [const Color(0xFF3D2000), const Color(0xFF1A0840)]
              : isRoyal
              ? [const Color(0xFF2D1254), const Color(0xFF160830)]
              : [const Color(0xFF1E0E38), const Color(0xFF0E0620)],
        ),
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusSm),
        border: Border.all(
          color: levelColor.withValues(alpha: 0.7),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: levelColor.withValues(alpha: isElite ? 0.40 : 0.22),
            blurRadius: isElite ? 10 : 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isElite
                ? Icons.star_rounded
                : isRoyal
                ? Icons.diamond_rounded
                : Icons.military_tech_rounded,
            size: 10,
            color: levelColor,
          ),
          const SizedBox(width: 4),
          Text(
            'LV $level',
            style: TextStyle(
              fontSize: SroodRoomDims.textXs,
              fontWeight: FontWeight.w900,
              color: levelColor,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.icon,
    required this.label,
    this.color = SroodRoomColors.gold,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: SroodRoomColors.glassFill,
        borderRadius: BorderRadius.circular(SroodRoomDims.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
