import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/vip_visuals.dart';
import '../../../core/vip/vip_spec.dart';
import '../../../shared/widgets/avatar_with_frame.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_username.dart';
import '../../messages/services/private_message_service.dart';
import '../../messages/widgets/private_chat_sheet.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../models/room_user_profile.dart';
import '../services/room_user_profile_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// ── Public entry point ────────────────────────────────────────────────────────

class RoomUserProfileSheet extends StatefulWidget {
  const RoomUserProfileSheet({
    required this.userId,
    required this.currentUserId,
    required this.isArabic,
    required this.onSendGift,
    this.roomId,
    this.isViewerOwner = false,
    this.isViewerHost = false,
    this.targetRoomRole,
    this.targetMicSeat,
    this.targetIsMuted = false,
    this.onToggleMute,
    this.onKick,
    this.onStandUp,
    this.onBan,
    this.onSetAdmin,
    this.onRemoveAdmin,
    super.key,
  });

  final String userId;
  final String? currentUserId;
  final bool isArabic;
  final ValueChanged<String> onSendGift;

  // Room context — all optional so the sheet can be used outside rooms too
  final String? roomId;
  final bool isViewerOwner;
  final bool isViewerHost;
  final String? targetRoomRole;   // 'host' | 'speaker' | 'listener' | null
  final int? targetMicSeat;
  final bool targetIsMuted;

  // Moderation callbacks — null = action not available
  final Future<void> Function(bool muted)? onToggleMute;
  final Future<void> Function()? onKick;
  final Future<void> Function()? onStandUp;
  final Future<void> Function()? onBan;
  final Future<void> Function()? onSetAdmin;
  final Future<void> Function()? onRemoveAdmin;

  @override
  State<RoomUserProfileSheet> createState() => _RoomUserProfileSheetState();
}

class _RoomUserProfileSheetState extends State<RoomUserProfileSheet>
    with SingleTickerProviderStateMixin {
  final _service = const RoomUserProfileService();
  final _msgService = const PrivateMessageService();

  RoomUserProfile? _profile;
  List<GiftWallItem> _giftWall = const [];
  bool _loading = true;
  bool _followBusy = false;
  bool _reminderBusy = false;
  bool _sayHiBusy = false;
  bool _muteBusy = false;
  bool _kickBusy = false;
  bool _standBusy = false;
  bool _banBusy = false;
  bool _adminBusy = false;
  String? _error;

  // Local copy so we can optimistically update isMuted
  bool _isMuted = false;

  AnimationController? _glowCtrl;
  late final Animation<double> _glowAnim;

  bool get _isMe => widget.currentUserId == widget.userId;
  bool get _isInRoom => widget.roomId != null;
  bool get _canModerate =>
      _isInRoom &&
      !_isMe &&
      (widget.isViewerOwner || widget.isViewerHost) &&
      widget.targetRoomRole != 'host';

  @override
  void initState() {
    super.initState();
    _isMuted = widget.targetIsMuted;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.fetchUserProfile(widget.userId),
        _service.fetchGiftWall(widget.userId),
      ]);
      if (!mounted) return;

      final profile = results[0] as RoomUserProfile;
      final wall = results[1] as List<GiftWallItem>;
      final vip = profile.effectiveVipLevel;

      if (vip >= 7) {
        _glowCtrl = AnimationController(
          vsync: this,
          duration: Duration(milliseconds: vip == 9 ? 1400 : 2000),
        )..repeat(reverse: true);
        _glowAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
          CurvedAnimation(parent: _glowCtrl!, curve: Curves.easeInOut),
        );
      } else {
        _glowAnim = const AlwaysStoppedAnimation(1.0);
      }

      setState(() {
        _profile = profile;
        _giftWall = wall;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _glowCtrl?.dispose();
    super.dispose();
  }

  // ── Social actions ──────────────────────────────────────────────────────────

  Future<void> _toggleFollow() async {
    final p = _profile;
    if (p == null || _isMe || _followBusy) return;
    setState(() {
      _followBusy = true;
      _profile = p.copyWith(
        isFollowedByMe: !p.isFollowedByMe,
        followersCount: p.followersCount + (p.isFollowedByMe ? -1 : 1),
      );
    });
    try {
      if (p.isFollowedByMe) {
        await _service.unfollowUser(p.userId);
      } else {
        await _service.followUser(p.userId);
      }
    } catch (_) {
      if (mounted) setState(() => _profile = p);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _createReminder() async {
    if (_isMe || _reminderBusy) return;
    final isArabic = context.isArabic;
    setState(() => _reminderBusy = true);
    try {
      await _service.createReminder(widget.userId);
      _snack(isArabic ? 'تم حفظ التذكير' : 'Reminder saved');
    } catch (_) {
      _snack(isArabic ? 'تم حفظ التذكير' : 'Reminder saved');
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  Future<void> _sayHi() async {
    if (_isMe || _sayHiBusy) return;
    final isArabic = context.isArabic;
    setState(() => _sayHiBusy = true);
    try {
      await _msgService.sendHi(widget.userId, isArabic: isArabic);
      _snack(isArabic ? 'تم إرسال التحية' : 'Hi sent');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _sayHiBusy = false);
    }
  }

  Future<void> _openMessage() async {
    final p = _profile;
    if (_isMe || p == null) return;
    final isArabic = context.isArabic;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PrivateChatSheet(
        targetUserId: p.userId,
        targetName: p.nickname,
        targetAvatarUrl: p.avatarUrl,
        targetFrameKey: p.selectedAvatarFrame,
        isArabic: isArabic,
      ),
    );
  }

  void _sendGift() {
    if (_isMe) return;
    Navigator.of(context).pop();
    widget.onSendGift(widget.userId);
  }

  void _viewFullProfile() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UserProfileScreen(
        userId: widget.userId,
        isArabic: context.isArabic,
      ),
    ));
  }

  void _copyId() {
    final id = _profile?.publicUserId ?? widget.userId;
    Clipboard.setData(ClipboardData(text: id));
    _snack(context.isArabic ? 'تم نسخ ID' : 'ID copied');
  }

  // ── Moderation actions ──────────────────────────────────────────────────────

  Future<void> _doMute() async {
    final cb = widget.onToggleMute;
    if (cb == null || _muteBusy) return;
    final isArabic = context.isArabic;
    setState(() => _muteBusy = true);
    try {
      final newMuted = !_isMuted;
      await cb(newMuted);
      if (mounted) setState(() => _isMuted = newMuted);
      _snack(
        _isMuted
            ? (isArabic ? 'تم كتم الصوت' : 'Mic muted')
            : (isArabic ? 'تم فك الكتم' : 'Mic unmuted'),
      );
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _muteBusy = false);
    }
  }

  Future<void> _doStandUp() async {
    final cb = widget.onStandUp;
    if (cb == null || _standBusy) return;
    final isArabic = context.isArabic;
    final ok = await _confirmDialog(
      icon: Icons.hearing_rounded,
      iconColor: const Color(0xFF8B26D9),
      title: isArabic ? 'إنزال من المايك' : 'Stand Up',
      body: isArabic
          ? 'هل تريد إزالة هذا المستخدم من المايك؟'
          : 'Remove this user from the mic seat?',
    );
    if (!ok || !mounted) return;
    setState(() => _standBusy = true);
    try {
      await cb();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _standBusy = false);
    }
  }

  Future<void> _doKick() async {
    final cb = widget.onKick;
    if (cb == null || _kickBusy) return;
    final isArabic = context.isArabic;
    final ok = await _confirmDialog(
      icon: Icons.logout_rounded,
      iconColor: const Color(0xFFE63946),
      title: isArabic ? 'طرد من الغرفة' : 'Kick Out',
      body: isArabic
          ? 'هل تريد طرد هذا المستخدم من الغرفة؟'
          : 'Remove this user from the room?',
    );
    if (!ok || !mounted) return;
    setState(() => _kickBusy = true);
    try {
      await cb();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _kickBusy = false);
    }
  }

  Future<void> _doBan() async {
    final cb = widget.onBan;
    if (cb == null || _banBusy) return;
    final isArabic = context.isArabic;
    final ok = await _confirmDialog(
      icon: Icons.block_rounded,
      iconColor: const Color(0xFFE63946),
      title: isArabic ? 'حظر من الغرفة' : 'Ban from Room',
      body: isArabic
          ? 'هل تريد حظر هذا المستخدم من الغرفة؟'
          : 'Ban this user from the room?',
    );
    if (!ok || !mounted) return;
    setState(() => _banBusy = true);
    try {
      await cb();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _banBusy = false);
    }
  }

  Future<void> _doSetAdmin() async {
    final cb = widget.onSetAdmin;
    if (cb == null || _adminBusy) return;
    final isArabic = context.isArabic;
    setState(() => _adminBusy = true);
    try {
      await cb();
      _snack(isArabic ? 'تم تعيين مشرف' : 'Admin set');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _adminBusy = false);
    }
  }

  Future<void> _doRemoveAdmin() async {
    final cb = widget.onRemoveAdmin;
    if (cb == null || _adminBusy) return;
    final isArabic = context.isArabic;
    setState(() => _adminBusy = true);
    try {
      await cb();
      _snack(isArabic ? 'تم إزالة المشرف' : 'Admin removed');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _adminBusy = false);
    }
  }

  Future<bool> _confirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF140B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: Icon(icon, color: iconColor, size: 34),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        content: Text(
          body,
          style: const TextStyle(color: Color(0xFFD8CFEA)),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              context.isArabic ? 'إلغاء' : 'Cancel',
              style: const TextStyle(color: Color(0xFF9E91B8)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.isArabic ? 'تأكيد' : 'Confirm',
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxH = size.height * 0.88;
    final maxW = size.width >= 600 ? 460.0 : double.infinity;
    final vip = _profile?.effectiveVipLevel ?? 0;
    final prestige = VipSpecResolver.resolve(vip);

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1C0D30), Color(0xFF0E0620), Color(0xFF060210)],
              ),
              border: Border(
                top: BorderSide(
                  color: prestige.borderColor.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TopBar(
                    accentColor: prestige.primaryColor,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        16 + MediaQuery.of(context).padding.bottom,
                      ),
                      child: _loading
                          ? SizedBox(
                              height: 340,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: prestige.primaryColor,
                                ),
                              ),
                            )
                          : _error != null
                              ? _ErrorBody(isArabic: context.isArabic)
                              : _SheetBody(
                                  profile: _profile!,
                                  giftWall: _giftWall,
                                  prestige: prestige,
                                  glowAnim: _glowAnim,
                                  isArabic: context.isArabic,
                                  isMe: _isMe,
                                  canModerate: _canModerate,
                                  isViewerOwner: widget.isViewerOwner,
                                  targetRoomRole: widget.targetRoomRole,
                                  targetMicSeat: widget.targetMicSeat,
                                  isMuted: _isMuted,
                                  isOnMic: widget.targetMicSeat != null &&
                                      (widget.targetRoomRole == 'speaker' ||
                                          widget.targetRoomRole == 'host'),
                                  followBusy: _followBusy,
                                  reminderBusy: _reminderBusy,
                                  sayHiBusy: _sayHiBusy,
                                  muteBusy: _muteBusy,
                                  kickBusy: _kickBusy,
                                  standBusy: _standBusy,
                                  banBusy: _banBusy,
                                  adminBusy: _adminBusy,
                                  hasMuteAction: widget.onToggleMute != null,
                                  hasKickAction: widget.onKick != null,
                                  hasStandAction: widget.onStandUp != null,
                                  hasBanAction: widget.onBan != null,
                                  hasSetAdminAction: widget.onSetAdmin != null,
                                  hasRemoveAdminAction: widget.onRemoveAdmin != null,
                                  onCopyId: _copyId,
                                  onSayHi: _sayHi,
                                  onMessage: _openMessage,
                                  onFollow: _toggleFollow,
                                  onReminder: _createReminder,
                                  onSendGift: _sendGift,
                                  onViewProfile: _viewFullProfile,
                                  onMute: _doMute,
                                  onKick: _doKick,
                                  onStandUp: _doStandUp,
                                  onBan: _doBan,
                                  onSetAdmin: _doSetAdmin,
                                  onRemoveAdmin: _doRemoveAdmin,
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top bar (drag handle + close button) ─────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.accentColor, required this.onClose});
  final Color accentColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          const Spacer(),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error fallback ────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_rounded,
                color: Color(0xFF5A3A86), size: 48),
            const SizedBox(height: 12),
            Text(
              isArabic ? 'تعذر تحميل الملف الشخصي' : 'Could not load profile',
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main sheet body ───────────────────────────────────────────────────────────

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.profile,
    required this.giftWall,
    required this.prestige,
    required this.glowAnim,
    required this.isArabic,
    required this.isMe,
    required this.canModerate,
    required this.isViewerOwner,
    required this.targetRoomRole,
    required this.targetMicSeat,
    required this.isMuted,
    required this.isOnMic,
    required this.followBusy,
    required this.reminderBusy,
    required this.sayHiBusy,
    required this.muteBusy,
    required this.kickBusy,
    required this.standBusy,
    required this.banBusy,
    required this.adminBusy,
    required this.hasMuteAction,
    required this.hasKickAction,
    required this.hasStandAction,
    required this.hasBanAction,
    required this.hasSetAdminAction,
    required this.hasRemoveAdminAction,
    required this.onCopyId,
    required this.onSayHi,
    required this.onMessage,
    required this.onFollow,
    required this.onReminder,
    required this.onSendGift,
    required this.onViewProfile,
    required this.onMute,
    required this.onKick,
    required this.onStandUp,
    required this.onBan,
    required this.onSetAdmin,
    required this.onRemoveAdmin,
  });

  final RoomUserProfile profile;
  final List<GiftWallItem> giftWall;
  final VipSpec prestige;
  final Animation<double> glowAnim;
  final bool isArabic;
  final bool isMe;
  final bool canModerate;
  final bool isViewerOwner;
  final String? targetRoomRole;
  final int? targetMicSeat;
  final bool isMuted;
  final bool isOnMic;
  final bool followBusy;
  final bool reminderBusy;
  final bool sayHiBusy;
  final bool muteBusy;
  final bool kickBusy;
  final bool standBusy;
  final bool banBusy;
  final bool adminBusy;
  final bool hasMuteAction;
  final bool hasKickAction;
  final bool hasStandAction;
  final bool hasBanAction;
  final bool hasSetAdminAction;
  final bool hasRemoveAdminAction;
  final VoidCallback onCopyId;
  final VoidCallback onSayHi;
  final VoidCallback onMessage;
  final VoidCallback onFollow;
  final VoidCallback onReminder;
  final VoidCallback onSendGift;
  final VoidCallback onViewProfile;
  final VoidCallback onMute;
  final VoidCallback onKick;
  final VoidCallback onStandUp;
  final VoidCallback onBan;
  final VoidCallback onSetAdmin;
  final VoidCallback onRemoveAdmin;

  @override
  Widget build(BuildContext context) {
    final vip = profile.effectiveVipLevel;
    final goldenActive =
        isGoldenIdActive(profile.isGoldenId, profile.goldenIdExpiresAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header card ──────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: glowAnim,
          builder: (ctx, child) => Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: vip >= 2
                    ? prestige.bannerGradient
                    : [
                        const Color(0xFF1E0E38),
                        const Color(0xFF130728),
                      ],
              ),
              border: Border.all(
                color: prestige.borderColor.withValues(alpha: 0.55),
                width: prestige.borderWidth,
              ),
              boxShadow:
                  prestige.buildGlowShadows(pulseFactor: glowAnim.value),
            ),
            child: child,
          ),
          child: _HeaderContent(
            profile: profile,
            prestige: prestige,
            vip: vip,
            goldenActive: goldenActive,
            isArabic: isArabic,
            isMe: isMe,
            targetRoomRole: targetRoomRole,
            targetMicSeat: targetMicSeat,
            isMuted: isMuted,
            onCopyId: onCopyId,
          ),
        ),
        const SizedBox(height: 12),

        // ── VIP + Noble cards ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _LevelCard(
                title: 'VIP',
                value: vip > 0 ? 'Lv $vip' : '–',
                icon: vip >= 9
                    ? Icons.local_fire_department_rounded
                    : vip >= 7
                        ? Icons.workspace_premium_rounded
                        : Icons.diamond_rounded,
                prestige: prestige,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NobleLevelCard(
                nobleLevel: profile.nobleLevel,
                isArabic: isArabic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Stats row ──────────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _StatPill(
                icon: Icons.group_rounded,
                label: _fmt(profile.followersCount) +
                    (isArabic ? ' متابع' : ' followers'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatPill(
                icon: Icons.favorite_rounded,
                label: _fmt(profile.charmScore) +
                    (isArabic ? ' سحر' : ' charm'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Gift wall ──────────────────────────────────────────────────────────
        _GiftWall(items: giftWall, isArabic: isArabic),
        const SizedBox(height: 14),

        // ── Moderation section (owner/host only, can't moderate host) ─────────
        if (canModerate) ...[
          _SectionLabel(
            icon: Icons.admin_panel_settings_rounded,
            label: isArabic ? 'إدارة الغرفة' : 'Moderation',
            color: const Color(0xFF8B26D9),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (hasMuteAction)
                  _ActionBtn(
                    icon: isMuted
                        ? Icons.mic_rounded
                        : Icons.mic_off_rounded,
                    label: isMuted
                        ? (isArabic ? 'فتح الكتم' : 'Unmute')
                        : (isArabic ? 'كتم الصوت' : 'Mute'),
                    color: isMuted
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFE63946),
                    busy: muteBusy,
                    onTap: onMute,
                  ),
                if (hasStandAction && isOnMic)
                  _ActionBtn(
                    icon: Icons.hearing_rounded,
                    label: isArabic ? 'نزال المايك' : 'Stand Up',
                    color: const Color(0xFF8B26D9),
                    busy: standBusy,
                    onTap: onStandUp,
                  ),
                if (hasKickAction)
                  _ActionBtn(
                    icon: Icons.logout_rounded,
                    label: isArabic ? 'طرد' : 'Kick',
                    color: const Color(0xFFE63946),
                    busy: kickBusy,
                    onTap: onKick,
                  ),
                if (hasBanAction)
                  _ActionBtn(
                    icon: Icons.block_rounded,
                    label: isArabic ? 'حظر' : 'Ban',
                    color: const Color(0xFFE63946),
                    busy: banBusy,
                    onTap: onBan,
                  ),
                if (isViewerOwner && hasSetAdminAction)
                  _ActionBtn(
                    icon: Icons.manage_accounts_rounded,
                    label: isArabic ? 'مشرف' : 'Set Admin',
                    color: const Color(0xFFF0C15A),
                    busy: adminBusy,
                    onTap: onSetAdmin,
                  ),
                if (isViewerOwner && hasRemoveAdminAction)
                  _ActionBtn(
                    icon: Icons.person_remove_rounded,
                    label: isArabic ? 'إزالة مشرف' : 'Rm Admin',
                    color: const Color(0xFF9E91B8),
                    busy: adminBusy,
                    onTap: onRemoveAdmin,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ── Social section ─────────────────────────────────────────────────────
        if (!isMe) ...[
          _SectionLabel(
            icon: Icons.people_rounded,
            label: isArabic ? 'تفاعل' : 'Social',
            color: const Color(0xFFF0C15A),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionBtn(
                icon: Icons.waving_hand_rounded,
                label:
                    sayHiBusy ? '...' : (isArabic ? 'تحية' : 'Say Hi'),
                color: const Color(0xFF9E91B8),
                busy: sayHiBusy,
                onTap: onSayHi,
              ),
              _ActionBtn(
                icon: Icons.chat_bubble_rounded,
                label: isArabic ? 'رسالة' : 'Message',
                color: const Color(0xFF9E91B8),
                onTap: onMessage,
              ),
              _ActionBtn(
                icon: profile.isFollowedByMe
                    ? Icons.check_circle_rounded
                    : Icons.person_add_alt_1_rounded,
                label: followBusy
                    ? '...'
                    : profile.isFollowedByMe
                        ? (isArabic ? 'متابَع' : 'Following')
                        : (isArabic ? 'متابعة' : 'Follow'),
                color: profile.isFollowedByMe
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF9E91B8),
                busy: followBusy,
                onTap: onFollow,
              ),
              _ActionBtn(
                icon: Icons.notifications_active_rounded,
                label: reminderBusy
                    ? '...'
                    : (isArabic ? 'تذكير' : 'Remind'),
                color: const Color(0xFF9E91B8),
                busy: reminderBusy,
                onTap: onReminder,
              ),
              _ActionBtn(
                icon: Icons.card_giftcard_rounded,
                label: isArabic ? 'هدية' : 'Gift',
                color: const Color(0xFFF0C15A),
                highlighted: true,
                onTap: onSendGift,
              ),
              _ActionBtn(
                icon: Icons.person_rounded,
                label: isArabic ? 'الملف' : 'Profile',
                color: const Color(0xFF9E91B8),
                onTap: onViewProfile,
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Header content ────────────────────────────────────────────────────────────

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
    required this.profile,
    required this.prestige,
    required this.vip,
    required this.goldenActive,
    required this.isArabic,
    required this.isMe,
    required this.targetRoomRole,
    required this.targetMicSeat,
    required this.isMuted,
    required this.onCopyId,
  });

  final RoomUserProfile profile;
  final VipSpec prestige;
  final int vip;
  final bool goldenActive;
  final bool isArabic;
  final bool isMe;
  final String? targetRoomRole;
  final int? targetMicSeat;
  final bool isMuted;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    final textColor = vip >= 2 ? prestige.entryTextColor : Colors.white;
    final subColor = textColor.withValues(alpha: 0.70);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Avatar ──────────────────────────────────────────────────────────
        Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarWithFrame(
              imageUrl: profile.avatarUrl,
              radius: 44,
              frameKey: profile.selectedAvatarFrame,
              vipLevel: vip,
              showVipBadge: false,
            ),
            if (isMuted)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE63946),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF060210), width: 1.5),
                  ),
                  child: const Icon(Icons.mic_off_rounded,
                      color: Colors.white, size: 11),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),

        // ── Name / meta ──────────────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name row
              Row(
                children: [
                  Expanded(
                    child: VipUsername(
                      name: profile.nickname,
                      vipLevel: vip,
                      fontSize: 17,
                      textAlign: TextAlign.left,
                    ),
                  ),
                  if (isMe)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isArabic ? 'أنت' : 'You',
                        style: TextStyle(
                          color: subColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),

              // Public ID
              GestureDetector(
                onTap: onCopyId,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tag_rounded, size: 12, color: subColor),
                    const SizedBox(width: 3),
                    Text(
                      profile.publicUserId,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded, size: 10, color: subColor),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Badges row
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  // Room role badge
                  if (targetRoomRole != null)
                    _RoomRoleBadge(
                      role: targetRoomRole!,
                      seatNumber: targetMicSeat,
                      isArabic: isArabic,
                      textColor: textColor,
                    ),
                  // Country
                  if (profile.country?.trim().isNotEmpty == true)
                    _MetaBadge(
                      icon: Icons.public_rounded,
                      label: profile.country!,
                      textColor: textColor,
                    ),
                  // VIP badge
                  if (vip > 0)
                    goldenActive
                        ? GoldenIdBadge(
                            idText: profile.publicUserId,
                            goldenIdStyle: profile.goldenIdStyle,
                            goldenIdFrame: profile.goldenIdFrame,
                            compact: true)
                        : VipBadge(vipLevel: vip, compact: true),
                  // Noble
                  if (profile.nobleLevel > 0)
                    _MetaBadge(
                      icon: Icons.military_tech_rounded,
                      label: 'Noble ${profile.nobleLevel}',
                      textColor: textColor,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Room role badge ───────────────────────────────────────────────────────────

class _RoomRoleBadge extends StatelessWidget {
  const _RoomRoleBadge({
    required this.role,
    required this.seatNumber,
    required this.isArabic,
    required this.textColor,
  });

  final String role;
  final int? seatNumber;
  final bool isArabic;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (role) {
      'host' => (
          Icons.star_rounded,
          const Color(0xFFF0C15A),
          isArabic ? 'مضيف' : 'Host',
        ),
      'speaker' => (
          Icons.mic_rounded,
          const Color(0xFF8B26D9),
          isArabic
              ? (seatNumber != null ? 'مايك $seatNumber' : 'متحدث')
              : (seatNumber != null ? 'Mic $seatNumber' : 'Speaker'),
        ),
      _ => (Icons.hearing_rounded, const Color(0xFF6B7280), isArabic ? 'مستمع' : 'Listener'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Meta badge ────────────────────────────────────────────────────────────────

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: textColor.withValues(alpha: 0.70)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.80),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── VIP level card ────────────────────────────────────────────────────────────

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.prestige,
  });

  final String title;
  final String value;
  final IconData icon;
  final VipSpec prestige;

  @override
  Widget build(BuildContext context) {
    final hasGradient = prestige.level > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: hasGradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: prestige.badgeGradient,
              )
            : null,
        color: hasGradient ? null : const Color(0xFF1A0D2E),
        border: hasGradient
            ? null
            : Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: hasGradient
                ? prestige.badgeTextColor
                : const Color(0xFF6B7280),
            size: 22,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: hasGradient
                      ? prestige.badgeTextColor.withValues(alpha: 0.80)
                      : const Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: hasGradient
                      ? prestige.badgeTextColor
                      : const Color(0xFF4A3470),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Noble/prestige level card ─────────────────────────────────────────────────

class _NobleLevelCard extends StatelessWidget {
  const _NobleLevelCard({required this.nobleLevel, required this.isArabic});
  final int nobleLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final hasLevel = nobleLevel > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: hasLevel
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4A1D96), Color(0xFF2D0F6B)],
              )
            : null,
        color: hasLevel ? null : const Color(0xFF1A0D2E),
        border: hasLevel ? null : Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.military_tech_rounded,
            color: hasLevel ? const Color(0xFFF0C15A) : const Color(0xFF6B7280),
            size: 22,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'نبيل' : 'Noble',
                style: TextStyle(
                  color: hasLevel
                      ? const Color(0xFFD8CFEA)
                      : const Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                hasLevel ? 'Lv $nobleLevel' : '–',
                style: TextStyle(
                  color: hasLevel
                      ? const Color(0xFFF0C15A)
                      : const Color(0xFF4A3470),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF3D2860)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFF0C15A)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gift wall ─────────────────────────────────────────────────────────────────

class _GiftWall extends StatelessWidget {
  const _GiftWall({required this.items, required this.isArabic});
  final List<GiftWallItem> items;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0620),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3D2860)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard_rounded,
                  size: 14, color: Color(0xFFF0C15A)),
              const SizedBox(width: 6),
              Text(
                isArabic ? 'جدار الهدايا' : 'Gift Wall',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              isArabic ? 'لا توجد هدايا بعد' : 'No gifts yet',
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 12),
            )
          else
            Row(
              children: items
                  .take(3)
                  .map(
                    (g) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A0D2E),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: g.imageUrl == null
                                  ? const Icon(Icons.card_giftcard_rounded,
                                      color: Color(0xFFF0C15A))
                                  : Image.network(
                                      g.imageUrl!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.card_giftcard_rounded,
                                        color: Color(0xFFF0C15A),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              g.giftName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD8CFEA),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
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

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            color: color.withValues(alpha: 0.25),
            thickness: 0.8,
          ),
        ),
      ],
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.highlighted = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool highlighted;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 72,
        height: 62,
        margin: const EdgeInsets.only(right: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: highlighted
              ? color
              : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted
                ? color
                : color.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: highlighted ? const Color(0xFF160B26) : color,
                ),
              )
            else
              Icon(
                icon,
                size: 20,
                color: highlighted ? const Color(0xFF160B26) : color,
              ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: highlighted
                    ? const Color(0xFF160B26)
                    : color.withValues(alpha: 0.90),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
