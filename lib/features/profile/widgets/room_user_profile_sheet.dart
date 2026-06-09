import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/vip_visuals.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_username.dart';
import '../../messages/services/private_message_service.dart';
import '../../messages/widgets/private_chat_sheet.dart';
import '../../rooms/utils/vip_room_features.dart';
import '../models/room_user_profile.dart';
import '../services/room_user_profile_service.dart';

class RoomUserProfileSheet extends StatefulWidget {
  const RoomUserProfileSheet({
    required this.userId,
    required this.currentUserId,
    required this.isArabic,
    required this.onSendGift,
    super.key,
  });

  final String userId;
  final String? currentUserId;
  final bool isArabic;
  final ValueChanged<String> onSendGift;

  @override
  State<RoomUserProfileSheet> createState() => _RoomUserProfileSheetState();
}

class _RoomUserProfileSheetState extends State<RoomUserProfileSheet> {
  final RoomUserProfileService _service = const RoomUserProfileService();
  final PrivateMessageService _messageService = const PrivateMessageService();

  RoomUserProfile? _profile;
  List<GiftWallItem> _giftWall = const [];
  bool _loading = true;
  bool _followBusy = false;
  bool _reminderBusy = false;
  bool _sayHiBusy = false;
  String? _error;

  bool get _isMe => widget.currentUserId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _service.fetchUserProfile(widget.userId);
      final giftWall = await _service.fetchGiftWall(widget.userId);

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _giftWall = giftWall;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _isMe || _followBusy) {
      return;
    }

    setState(() {
      _followBusy = true;
      _profile = profile.copyWith(
        isFollowedByMe: !profile.isFollowedByMe,
        followersCount:
            profile.followersCount + (profile.isFollowedByMe ? -1 : 1),
      );
    });

    try {
      if (profile.isFollowedByMe) {
        await _service.unfollowUser(profile.userId);
      } else {
        await _service.followUser(profile.userId);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _profile = profile;
      });
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _followBusy = false;
        });
      }
    }
  }

  Future<void> _createReminder() async {
    if (_isMe || _reminderBusy) {
      return;
    }

    setState(() {
      _reminderBusy = true;
    });

    try {
      await _service.createReminder(widget.userId);
      _showSnack(
        widget.isArabic
            ? '\u062a\u0645 \u062d\u0641\u0638 \u0627\u0644\u062a\u0630\u0643\u064a\u0631'
            : 'Reminder saved',
      );
    } catch (_) {
      _showSnack(
        widget.isArabic
            ? '\u062a\u0645 \u062d\u0641\u0638 \u0627\u0644\u062a\u0630\u0643\u064a\u0631'
            : 'Reminder saved',
      );
    } finally {
      if (mounted) {
        setState(() {
          _reminderBusy = false;
        });
      }
    }
  }

  Future<void> _sayHi() async {
    if (_isMe || _sayHiBusy) {
      return;
    }

    setState(() {
      _sayHiBusy = true;
    });

    try {
      await _messageService.sendHi(widget.userId, isArabic: widget.isArabic);
      _showSnack(
        widget.isArabic
            ? '\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u062a\u062d\u064a\u0629'
            : 'Hi sent',
      );
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _sayHiBusy = false;
        });
      }
    }
  }

  Future<void> _openMessageSheet() async {
    final profile = _profile;
    if (_isMe || profile == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PrivateChatSheet(
        targetUserId: profile.userId,
        targetName: profile.nickname,
        targetAvatarUrl: profile.avatarUrl,
        targetFrameKey: profile.selectedAvatarFrame,
        isArabic: widget.isArabic,
      ),
    );
  }

  void _copyId() {
    final id = _profile?.publicUserId ?? widget.userId;
    Clipboard.setData(ClipboardData(text: id));
    _showSnack(
      widget.isArabic ? '\u062a\u0645 \u0646\u0633\u062e ID' : 'ID copied',
    );
  }

  void _reportUser() {
    _showSnack(
      widget.isArabic
          ? '\u0633\u064a\u062a\u0645 \u0625\u0636\u0627\u0641\u0629 \u0627\u0644\u0628\u0644\u0627\u063a\u0627\u062a \u0641\u064a \u0645\u0631\u062d\u0644\u0629 \u0627\u0644\u0633\u0644\u0627\u0645\u0629'
          : 'Reports will be added in Safety phase',
    );
  }

  void _sendGift() {
    if (_isMe) {
      return;
    }

    Navigator.of(context).pop();
    widget.onSendGift(widget.userId);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width >= 600
        ? 460.0
        : double.infinity;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              18,
              10,
              18,
              18 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF241638),
                  Color(0xFF12091D),
                  Color(0xFF06030A),
                ],
              ),
            ),
            child: _loading
                ? const SizedBox(
                    height: 360,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                ? _ProfileErrorState(error: _error!, isArabic: widget.isArabic)
                : _ProfileContent(
                    profile: _profile!,
                    giftWall: _giftWall,
                    isArabic: widget.isArabic,
                    isMe: _isMe,
                    followBusy: _followBusy,
                    reminderBusy: _reminderBusy,
                    sayHiBusy: _sayHiBusy,
                    onCopyId: _copyId,
                    onReport: _reportUser,
                    onSayHi: _sayHi,
                    onMessage: _openMessageSheet,
                    onFollow: _toggleFollow,
                    onReminder: _createReminder,
                    onSendGift: _sendGift,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.giftWall,
    required this.isArabic,
    required this.isMe,
    required this.followBusy,
    required this.reminderBusy,
    required this.sayHiBusy,
    required this.onCopyId,
    required this.onReport,
    required this.onSayHi,
    required this.onMessage,
    required this.onFollow,
    required this.onReminder,
    required this.onSendGift,
  });

  final RoomUserProfile profile;
  final List<GiftWallItem> giftWall;
  final bool isArabic;
  final bool isMe;
  final bool followBusy;
  final bool reminderBusy;
  final bool sayHiBusy;
  final VoidCallback onCopyId;
  final VoidCallback onReport;
  final VoidCallback onSayHi;
  final VoidCallback onMessage;
  final VoidCallback onFollow;
  final VoidCallback onReminder;
  final VoidCallback onSendGift;

  @override
  Widget build(BuildContext context) {
    final vipLevel = profile.effectiveVipLevel;
    final goldenActive = isGoldenIdActive(
      profile.isGoldenId,
      profile.goldenIdExpiresAt,
    );
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Spacer(),
              Container(
                width: 54,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF5A3A86),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (value) {
                  if (value == 'copy') onCopyId();
                  if (value == 'report') onReport();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'copy',
                    child: Text(isArabic ? '\u0646\u0633\u062e ID' : 'Copy ID'),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: Text(
                      isArabic
                          ? '\u0625\u0628\u0644\u0627\u063a'
                          : 'Report user',
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: const Color(0xFF5A3A86)),
              boxShadow: VipVisualStyle.glow(vipLevel),
            ),
            child: Column(
              children: [
                AvatarWithFrame(
                  imageUrl: profile.avatarUrl,
                  radius: 46,
                  frameKey: profile.selectedAvatarFrame,
                  vipLevel: vipLevel,
                  showVipBadge: false,
                ),
                const SizedBox(height: 12),
                VipUsername(
                  name: profile.nickname,
                  vipLevel: vipLevel,
                  fontSize: 22,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 7),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (goldenActive)
                      GoldenIdBadge(
                        idText: profile.publicUserId,
                        compact: true,
                      )
                    else
                      _ProfileStatPill(
                        icon: Icons.badge_rounded,
                        label: profile.publicUserId,
                      ),
                    if (profile.age != null)
                      _ProfileStatPill(
                        icon: Icons.cake_rounded,
                        label: '${profile.age}',
                      ),
                    if (profile.gender?.trim().isNotEmpty == true)
                      _ProfileStatPill(
                        icon: Icons.person_rounded,
                        label: profile.gender!,
                      ),
                    if (profile.country?.trim().isNotEmpty == true)
                      _ProfileStatPill(
                        icon: Icons.public_rounded,
                        label: profile.country!,
                      ),
                    if (vipLevel > 0) VipBadge(vipLevel: vipLevel),
                  ],
                ),
                if (profile.bio?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    profile.bio!,
                    textAlign: textAlign,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (isMe) ...[
                  const SizedBox(height: 10),
                  _ProfileStatPill(
                    icon: Icons.verified_user_rounded,
                    label: isArabic
                        ? '\u0647\u0630\u0627 \u062d\u0633\u0627\u0628\u0643'
                        : 'This is you',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileLevelCard(
                  title: 'VIP',
                  value: 'Lv$vipLevel',
                  icon: Icons.workspace_premium_rounded,
                  level: vipLevel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileLevelCard(
                  title: 'Noble',
                  value: 'Lv${profile.nobleLevel}',
                  icon: Icons.military_tech_rounded,
                  level: profile.nobleLevel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileStatPill(
                  icon: Icons.group_rounded,
                  label: '${profile.followersCount} followers',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileStatPill(
                  icon: Icons.favorite_rounded,
                  label: '${profile.charmScore} charm',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _GiftWallPreview(items: giftWall, isArabic: isArabic),
          const SizedBox(height: 14),
          if (!isMe)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProfileActionButton(
                  icon: Icons.waving_hand_rounded,
                  label: sayHiBusy
                      ? '...'
                      : (isArabic ? '\u062a\u062d\u064a\u0629' : 'Say Hi'),
                  onTap: onSayHi,
                ),
                _ProfileActionButton(
                  icon: Icons.chat_bubble_rounded,
                  label: isArabic
                      ? '\u0631\u0633\u0627\u0644\u0629'
                      : 'Message',
                  onTap: onMessage,
                ),
                _ProfileActionButton(
                  icon: profile.isFollowedByMe
                      ? Icons.check_circle_rounded
                      : Icons.person_add_alt_1_rounded,
                  label: followBusy
                      ? '...'
                      : profile.isFollowedByMe
                      ? (isArabic
                            ? '\u062a\u062a\u0645 \u0627\u0644\u0645\u062a\u0627\u0628\u0639\u0629'
                            : 'Following')
                      : (isArabic
                            ? '\u0645\u062a\u0627\u0628\u0639\u0629'
                            : 'Follow'),
                  onTap: onFollow,
                ),
                _ProfileActionButton(
                  icon: Icons.notifications_active_rounded,
                  label: reminderBusy
                      ? '...'
                      : (isArabic
                            ? '\u062a\u0630\u0643\u064a\u0631'
                            : 'Reminder'),
                  onTap: onReminder,
                ),
                _ProfileActionButton(
                  icon: Icons.card_giftcard_rounded,
                  label: isArabic ? '\u0647\u062f\u064a\u0629' : 'Gift',
                  highlighted: true,
                  onTap: onSendGift,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProfileErrorState extends StatelessWidget {
  const _ProfileErrorState({required this.error, required this.isArabic});

  final String error;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Center(
        child: Text(
          isArabic
              ? '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0645\u0644\u0641'
              : 'Could not load profile',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFD8CFEA),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ProfileStatPill extends StatelessWidget {
  const _ProfileStatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF5A3A86)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: const Color(0xFFF0C15A)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLevelCard extends StatelessWidget {
  const _ProfileLevelCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.level,
  });

  final String title;
  final String value;
  final IconData icon;
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: VipVisualStyle.gradient(level)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF160B26), size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF160B26),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF160B26),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
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

class _GiftWallPreview extends StatelessWidget {
  const _GiftWallPreview({required this.items, required this.isArabic});

  final List<GiftWallItem> items;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: Text(
                  isArabic
                      ? '\u062c\u062f\u0627\u0631 \u0627\u0644\u0647\u062f\u0627\u064a\u0627'
                      : 'Gift Wall',
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                isArabic
                    ? '\u0639\u0631\u0636 \u0627\u0644\u0643\u0644'
                    : 'View all',
                style: const TextStyle(color: Color(0xFF9E91B8), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              isArabic
                  ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u0647\u062f\u0627\u064a\u0627 \u0628\u0639\u062f'
                  : 'No gifts yet',
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontWeight: FontWeight.w800,
              ),
            )
          else
            Row(
              children: items
                  .take(3)
                  .map(
                    (item) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF241638),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: item.imageUrl == null
                                  ? const Icon(Icons.card_giftcard_rounded)
                                  : Image.network(
                                      item.imageUrl!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.card_giftcard_rounded,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.giftName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 76,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: highlighted
              ? const Color(0xFFF0C15A)
              : const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: highlighted
                ? const Color(0xFFF0C15A)
                : const Color(0xFF5A3A86),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: highlighted
                  ? const Color(0xFF160B26)
                  : const Color(0xFFD8CFEA),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlighted
                    ? const Color(0xFF160B26)
                    : const Color(0xFFD8CFEA),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
