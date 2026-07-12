/// Participants sheet: full member list with roles, VIP badges, support
/// totals, and host moderation shortcuts (promote / move to listener /
/// remove). Data and actions are owned by the screen.
library;

import 'package:flutter/material.dart';

import 'package:srood_live/shared/widgets/vip_badge.dart';

import '../../../../models/room_member.dart';
import '../../../../utils/vip_room_features.dart';
import '../../../../widgets/agent_identity_badge.dart';
import '../../../../widgets/room_details/room_status_badges.dart';
import '../../../theme/srood_room_theme.dart';
import '../common/srood_room_avatar.dart';
import '../mic_grid/srood_support_pill.dart';

class SroodRoomParticipantsSheet extends StatelessWidget {
  const SroodRoomParticipantsSheet({
    required this.members,
    required this.currentUserId,
    required this.isArabic,
    required this.refreshing,
    required this.supportByUserId,
    required this.roleBusyUserId,
    required this.roleLabel,
    required this.isHost,
    required this.onRefresh,
    required this.onProfileTap,
    required this.onPromote,
    required this.onMoveToListener,
    required this.onRemove,
    super.key,
  });

  final List<RoomMember> members;
  final String? currentUserId;
  final bool isArabic;
  final bool refreshing;
  final Map<String, int> supportByUserId;
  final String? roleBusyUserId;
  final String Function(String role) roleLabel;
  final bool isHost;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onProfileTap;
  final ValueChanged<RoomMember> onPromote;
  final ValueChanged<RoomMember> onMoveToListener;
  final ValueChanged<RoomMember> onRemove;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;

    return FractionallySizedBox(
      heightFactor: 0.70,
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: const BoxDecoration(
            color: SroodRoomColors.bgDeep,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(SroodRoomDims.radiusSheet + 6),
            ),
            border: Border(
              top: BorderSide(color: Color(0xFF5A3A86), width: 1.2),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF5A3A86),
                  borderRadius: BorderRadius.circular(
                    SroodRoomDims.radiusPill,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: isArabic
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic ? 'المشاركون' : 'Participants',
                          textAlign: textAlign,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isArabic
                              ? '${members.length} في الغرفة'
                              : '${members.length} in room',
                          textAlign: textAlign,
                          style: const TextStyle(
                            color: Color(0xFFB9A9D4),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: isArabic ? 'تحديث' : 'Refresh',
                    onPressed: refreshing ? null : onRefresh,
                    icon: refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: SroodRoomDims.space12),
              Expanded(
                child: members.isEmpty
                    ? Center(
                        child: Text(
                          isArabic
                              ? 'لا يوجد مشاركون نشطون بعد.'
                              : 'No active participants yet.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFD8CFEA)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: members.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: SroodRoomDims.space8),
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final isSelf = member.userId == currentUserId;

                          return _ParticipantRow(
                            member: member,
                            isSelf: isSelf,
                            isArabic: isArabic,
                            roleLabel: roleLabel(member.role),
                            supportAmount: supportByUserId[member.userId] ?? 0,
                            isBusy: roleBusyUserId == member.userId,
                            showHostActions:
                                isHost && !isSelf && member.role != 'host',
                            onProfileTap: () => onProfileTap(member.userId),
                            onPromote: () => onPromote(member),
                            onMoveToListener: () => onMoveToListener(member),
                            onRemove: () => onRemove(member),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.member,
    required this.isSelf,
    required this.isArabic,
    required this.roleLabel,
    required this.supportAmount,
    required this.isBusy,
    required this.showHostActions,
    required this.onProfileTap,
    required this.onPromote,
    required this.onMoveToListener,
    required this.onRemove,
  });

  final RoomMember member;
  final bool isSelf;
  final bool isArabic;
  final String roleLabel;
  final int supportAmount;
  final bool isBusy;
  final bool showHostActions;
  final VoidCallback onProfileTap;
  final VoidCallback onPromote;
  final VoidCallback onMoveToListener;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final vipLevel = member.effectiveVipLevel;
    final isSpeaker = member.role == 'speaker';
    final isListener = member.role == 'listener';

    return InkWell(
      borderRadius: BorderRadius.circular(SroodRoomDims.radiusLg + 2),
      onTap: onProfileTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B102A),
          borderRadius: BorderRadius.circular(SroodRoomDims.radiusLg + 2),
          border: Border.all(color: const Color(0xFF3E285E)),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            SroodRoomAvatar(
              avatarUrl: member.avatarUrl,
              frameKey: member.selectedAvatarFrameKey,
              vipLevel: vipLevel,
              size: 42,
              selected: false,
              isOfficialAgent: member.isOfficialAgent,
              fallbackIcon: member.isMuted
                  ? Icons.mic_off_rounded
                  : Icons.person_rounded,
              onTap: onProfileTap,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: isArabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Flexible(
                        child: Text(
                          member.fallbackName(isArabic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: vipLevel > 0
                                ? VipVisualStyle.nameColor(vipLevel, context)
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: SroodRoomDims.space6),
                        RoomMiniStatusPill(label: isArabic ? 'أنت' : 'You'),
                      ],
                      if (member.isOfficialAgent) ...[
                        const SizedBox(width: SroodRoomDims.space6),
                        const AgentBadge(compact: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        member.displayCode,
                        style: const TextStyle(
                          color: Color(0xFF9E91B8),
                          fontSize: SroodRoomDims.textSm,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (vipLevel > 0)
                        VipBadge(vipLevel: vipLevel, compact: true),
                      if (member.role == 'host')
                        RoomMiniStatusPill(
                          label: isArabic ? 'مضيف' : 'Host',
                          gold: true,
                        ),
                      RoomMiniStatusPill(label: roleLabel),
                      if (member.isMuted)
                        RoomMiniStatusPill(
                          label: isArabic ? 'مكتوم' : 'Muted',
                        ),
                      SroodSupportPill(amount: supportAmount, compact: true),
                    ],
                  ),
                ],
              ),
            ),
            if (showHostActions) ...[
              const SizedBox(width: SroodRoomDims.space8),
              Wrap(
                spacing: SroodRoomDims.space6,
                children: [
                  if (isListener)
                    RoomTinyIconButton(
                      icon: Icons.record_voice_over_rounded,
                      busy: isBusy,
                      onTap: onPromote,
                    ),
                  if (isSpeaker)
                    RoomTinyIconButton(
                      icon: Icons.hearing_rounded,
                      busy: isBusy,
                      onTap: onMoveToListener,
                    ),
                  RoomTinyIconButton(
                    icon: Icons.person_remove_rounded,
                    busy: isBusy,
                    danger: true,
                    onTap: onRemove,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
