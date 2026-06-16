import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/room.dart';
import '../models/room_announcement.dart';
import '../models/room_ban.dart';
import '../models/room_moderator.dart';
import '../services/room_management_service.dart';
import '../services/rooms_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point: called only when _iAmRoomOwner == true
// ─────────────────────────────────────────────────────────────────────────────

class RoomOwnerManagementScreen extends StatefulWidget {
  const RoomOwnerManagementScreen({
    required this.room,
    required this.isArabic,
    super.key,
  });

  final Room room;
  final bool isArabic;

  @override
  State<RoomOwnerManagementScreen> createState() =>
      _RoomOwnerManagementScreenState();
}

class _RoomOwnerManagementScreenState extends State<RoomOwnerManagementScreen>
    with SingleTickerProviderStateMixin {
  static const _svc = RoomManagementService();
  static const _roomSvc = RoomsService();

  late final TabController _tabs;
  bool _loading = true;

  // Overview
  Map<String, int> _stats = {};
  bool _isLocked = false;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _savingMeta = false;

  // Members
  List<Map<String, dynamic>> _members = [];

  // Moderators
  List<RoomModerator> _moderators = [];

  // Bans
  List<RoomBan> _bans = [];

  // Announcement
  RoomAnnouncement? _activeAnnouncement;
  final _announcementCtrl = TextEditingController();
  bool _savingAnnouncement = false;

  // Appearance
  String? _roomCoverUrl;
  String? _roomAvatarUrl;
  bool _uploadingCover = false;
  bool _uploadingAvatar = false;

  // Schedules
  List<Map<String, dynamic>> _schedules = [];

  // Gift summary
  List<Map<String, dynamic>> _giftSummary = [];

  String get _roomId => widget.room.id;
  bool get _isArabic => widget.isArabic;

  // ── i18n helper ─────────────────────────────────────────────────────────
  String _t(String ar, String en) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _isLocked = widget.room.isLocked;
    _nameCtrl.text = widget.room.name;
    _descCtrl.text = widget.room.description ?? '';
    _roomCoverUrl = widget.room.coverUrl;
    _roomAvatarUrl = widget.room.avatarUrl;
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _announcementCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadStats(),
      _loadMembers(),
      _loadModerators(),
      _loadBans(),
      _loadAnnouncement(),
      _loadSchedules(),
      _loadGiftSummary(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadStats() async {
    try {
      _stats = await _svc.getRoomStats(_roomId);
    } catch (_) {}
  }

  Future<void> _loadMembers() async {
    try {
      // Use getAllRoomMembers (no 45-second freshness filter) so the management
      // screen shows everyone still in the room, even if heartbeats are stale.
      final list = await _roomSvc.getAllRoomMembers(_roomId);
      _members = list
          .map(
            (m) => {
              'user_id': m.userId,
              'display_name': m.displayName ?? m.username ?? 'Unknown',
              'avatar_url': m.avatarUrl,
              'role': m.role,
              'is_muted': m.isMuted,
              'seat_number': m.seatNumber,
              'public_user_id': m.displayCode,
            },
          )
          .toList();
    } catch (_) {}
  }

  Future<void> _loadModerators() async {
    try {
      _moderators = await _svc.getModerators(_roomId);
    } catch (_) {}
  }

  Future<void> _loadBans() async {
    try {
      _bans = await _svc.getBans(_roomId);
    } catch (_) {}
  }

  Future<void> _loadAnnouncement() async {
    try {
      _activeAnnouncement = await _svc.getActiveAnnouncement(_roomId);
      if (_activeAnnouncement != null) {
        _announcementCtrl.text = _activeAnnouncement!.message;
      }
    } catch (_) {}
  }

  Future<void> _loadSchedules() async {
    try {
      _schedules = await _svc.getRoomSchedules(_roomId);
    } catch (_) {}
  }

  Future<void> _loadGiftSummary() async {
    try {
      _giftSummary = await _svc.getGiftSummary(_roomId);
    } catch (_) {}
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Prompts for a password and returns it, or null if cancelled / empty.
  Future<String?> _askForPassword() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0D33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t('تعيين كلمة مرور للغرفة', 'Set room password'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: _t('3 أحرف على الأقل', 'Minimum 3 characters'),
            hintStyle: const TextStyle(color: Color(0xFF7A6A94)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFF8B26D9)),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_t('إلغاء', 'Cancel'),
                style: const TextStyle(color: Color(0xFF9E8AB8))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B26D9)),
            onPressed: () {
              if (ctrl.text.trim().length < 3) return;
              Navigator.of(ctx).pop(ctrl.text.trim());
            },
            child: Text(_t('قفل', 'Lock')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.trim().length < 3) return null;
    return result.trim();
  }

  String _friendlyError(dynamic e) {
    final s = e.toString();
    if (e is RoomPasswordRequiredException || s.contains('room_password_required')) {
      return _t(
        'يرجى إدخال كلمة مرور لقفل الغرفة',
        'Please set a password to lock the room',
      );
    }
    if (s.contains('wrong_room_password')) {
      return _t('كلمة المرور غير صحيحة', 'Incorrect room password');
    }
    if (s.contains('locked_room')) {
      return _t('الغرفة مقفلة', 'Room is locked');
    }
    if (s.contains('closed_room')) {
      return _t('الغرفة مغلقة', 'Room is closed');
    }
    return _t('حدث خطأ، يرجى المحاولة مجدداً', 'Something went wrong, please try again');
  }

  Future<void> _toggleLock() async {
    final enabling = !_isLocked;

    String? password;
    if (enabling) {
      password = await _askForPassword();
      if (password == null) return; // user cancelled
    }

    try {
      await _roomSvc.setRoomLocked(
        roomId: _roomId,
        isLocked: enabling,
        password: password,
      );
      setState(() => _isLocked = enabling);
      _snack(enabling
          ? _t('تم قفل الغرفة', 'Room locked')
          : _t('تم فتح الغرفة', 'Room unlocked'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _saveMeta() async {
    setState(() => _savingMeta = true);
    try {
      await _svc.updateRoom(
        _roomId,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      _snack(_t('تم الحفظ', 'Saved'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _savingMeta = false);
    }
  }

  Future<void> _muteMember(String userId, bool mute) async {
    try {
      await _svc.ownerMuteMember(_roomId, userId, isMuted: mute);
      await _loadMembers();
      if (mounted) setState(() {});
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _kickMember(String userId) async {
    try {
      await _roomSvc.removeMemberFromRoom(roomId: _roomId, userId: userId);
      await _loadMembers();
      if (mounted) setState(() {});
      _snack(_t('تم الطرد', 'Member removed'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _banMember(String userId, String name) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BanDialog(
        isArabic: _isArabic,
        userName: name,
        reasonCtrl: reasonCtrl,
      ),
    );
    if (confirmed != true) return;
    try {
      await _svc.banUser(_roomId, userId, reason: reasonCtrl.text.trim());
      await Future.wait([_loadMembers(), _loadBans()]);
      if (mounted) setState(() {});
      _snack(_t('تم حظر المستخدم', 'User banned'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _unbanUser(RoomBan ban) async {
    try {
      await _svc.unbanUser(_roomId, ban.userId);
      await _loadBans();
      if (mounted) setState(() {});
      _snack(_t('تم رفع الحظر', 'Ban removed'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _promoteModerator(String userId, String name) async {
    try {
      await _svc.addModerator(_roomId, userId);
      await _loadModerators();
      if (mounted) setState(() {});
      _snack(_t('تم تعيين مشرف', 'Moderator added'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _removeModerator(RoomModerator mod) async {
    try {
      await _svc.removeModerator(mod.id);
      await _loadModerators();
      if (mounted) setState(() {});
      _snack(_t('تم إزالة المشرف', 'Moderator removed'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _saveAnnouncement() async {
    final msg = _announcementCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _savingAnnouncement = true);
    try {
      await _svc.saveAnnouncement(_roomId, msg);
      await _loadAnnouncement();
      if (mounted) setState(() {});
      _snack(_t('تم نشر الإعلان', 'Announcement published'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _savingAnnouncement = false);
    }
  }

  Future<void> _clearAnnouncement() async {
    try {
      await _svc.deactivateAnnouncements(_roomId);
      _announcementCtrl.clear();
      _activeAnnouncement = null;
      if (mounted) setState(() {});
      _snack(_t('تم حذف الإعلان', 'Announcement cleared'));
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _addSchedule() async {
    final titleCtrl = TextEditingController();
    DateTime? picked;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF160B24),
          title: Text(
            _t('إضافة جلسة', 'Add Schedule'),
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: _t('العنوان', 'Title'),
                  labelStyle: const TextStyle(color: Color(0xFF9E8AB8)),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A2460)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF8B26D9)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF0C15A),
                  side: const BorderSide(color: Color(0xFF3A2460)),
                ),
                onPressed: () async {
                  final dt = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (dt == null || !ctx.mounted) return;
                  final tm = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.now(),
                  );
                  if (tm == null) return;
                  setSt(
                    () => picked = DateTime(
                      dt.year,
                      dt.month,
                      dt.day,
                      tm.hour,
                      tm.minute,
                    ),
                  );
                },
                child: Text(
                  picked == null
                      ? _t('اختر الوقت', 'Pick time')
                      : '${picked!.day}/${picked!.month}/${picked!.year} ${picked!.hour}:${picked!.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                _t('إلغاء', 'Cancel'),
                style: const TextStyle(color: Color(0xFF9E8AB8)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B26D9),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || picked == null || titleCtrl.text.trim().isEmpty) {
      return;
    }
    try {
      await _svc.createRoomSchedule(
        roomId: _roomId,
        title: titleCtrl.text.trim(),
        scheduledAt: picked!,
      );
      await _loadSchedules();
      if (mounted) setState(() {});
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _deleteSchedule(String id) async {
    try {
      await _svc.deleteSchedule(id);
      await _loadSchedules();
      if (mounted) setState(() {});
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: error ? const Color(0xFFFF6B7A) : const Color(0xFF6EE7B7),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: error
              ? const Color(0xFF2A0F1A)
              : const Color(0xFF0F2A1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: error
                  ? const Color(0xFFE63946).withValues(alpha: 0.5)
                  : const Color(0xFF10B981).withValues(alpha: 0.5),
            ),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ── Appearance actions ───────────────────────────────────────────────────

  Future<void> _pickAndUploadCover() async {
    if (_uploadingCover) return;
    setState(() => _uploadingCover = true);
    try {
      final url = await _roomSvc.pickAndUploadRoomImage(
        roomId: _roomId,
        bucket: 'room_covers',
      );
      await _roomSvc.updateRoomAppearance(roomId: _roomId, coverUrl: url);
      if (mounted) {
        setState(() => _roomCoverUrl = url);
        _snack(_t('تم تحديث غلاف الغرفة', 'Room cover updated'));
      }
    } on RoomImagePickerCancelled {
      // user dismissed picker — no-op
    } catch (e) {
      if (mounted) {
        _snack(
          _t('تعذر رفع الصورة. حاول مرة أخرى', 'Could not upload image. Please try again.'),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      final url = await _roomSvc.pickAndUploadRoomImage(
        roomId: _roomId,
        bucket: 'room_avatars',
      );
      await _roomSvc.updateRoomAppearance(roomId: _roomId, avatarUrl: url);
      if (mounted) {
        setState(() => _roomAvatarUrl = url);
        _snack(_t('تم تحديث أيقونة الغرفة', 'Room icon updated'));
      }
    } on RoomImagePickerCancelled {
      // user dismissed picker — no-op
    } catch (e) {
      if (mounted) {
        _snack(
          _t('تعذر رفع الصورة. حاول مرة أخرى', 'Could not upload image. Please try again.'),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _clearCover() async {
    await _roomSvc.clearRoomImage(roomId: _roomId, clearCover: true, clearAvatar: false);
    if (mounted) setState(() => _roomCoverUrl = null);
  }

  Future<void> _clearAvatar() async {
    await _roomSvc.clearRoomImage(roomId: _roomId, clearCover: false, clearAvatar: true);
    if (mounted) setState(() => _roomAvatarUrl = null);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF07030D),
        appBar: AppBar(
          backgroundColor: const Color(0xFF12061F),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Color(0xFFBCAED6)),
            onPressed: () => Navigator.of(context).pop(<String, String?>{
              'cover_url': _roomCoverUrl,
              'avatar_url': _roomAvatarUrl,
            }),
          ),
          title: Text(
            _t('إدارة الغرفة', 'Manage Room'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          iconTheme: const IconThemeData(color: Color(0xFFBCAED6)),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            indicatorColor: const Color(0xFF8B26D9),
            labelColor: const Color(0xFFF0C15A),
            unselectedLabelColor: const Color(0xFF9E8AB8),
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: _t('نظرة عامة', 'Overview')),
              Tab(text: _t('الأعضاء', 'Members')),
              Tab(text: _t('المشرفون', 'Mods')),
              Tab(text: _t('الحظر', 'Bans')),
              Tab(text: _t('المحتوى', 'Content')),
              Tab(text: _t('المظهر', 'Appearance')),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF8B26D9)),
              )
            : TabBarView(
                controller: _tabs,
                children: [
                  _buildOverviewTab(),
                  _buildMembersTab(),
                  _buildModsTab(),
                  _buildBansTab(),
                  _buildContentTab(),
                  _buildAppearanceTab(),
                ],
              ),
        ),
    );
  }

  // ── Tab: Overview ────────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: const Color(0xFF8B26D9),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(label: _t('إحصائيات', 'Stats')),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: [
              _StatCard(
                icon: Icons.headphones_rounded,
                label: _t('مستمعون', 'Listeners'),
                value: '${_stats['listeners'] ?? 0}',
                iconColor: const Color(0xFF7B8CDE),
              ),
              _StatCard(
                icon: Icons.mic_rounded,
                label: _t('متحدثون', 'Speakers'),
                value: '${_stats['speakers'] ?? 0}',
                iconColor: const Color(0xFF4FC3F7),
              ),
              _StatCard(
                icon: Icons.card_giftcard_rounded,
                label: _t('الهدايا', 'Gifts'),
                value: _formatCoins(_stats['total_gift_coins'] ?? 0),
                iconColor: const Color(0xFFF0C15A),
                valueColor: const Color(0xFFF0C15A),
              ),
              _StatCard(
                icon: Icons.block_rounded,
                label: _t('محظورون', 'Banned'),
                value: '${_stats['ban_count'] ?? 0}',
                iconColor: (_stats['ban_count'] ?? 0) > 0
                    ? const Color(0xFFE63946)
                    : const Color(0xFF9E8AB8),
                valueColor: (_stats['ban_count'] ?? 0) > 0
                    ? const Color(0xFFE63946)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(label: _t('قفل الغرفة', 'Room Lock')),
          const SizedBox(height: 8),
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isLocked
                            ? const Color(0xFFF0C15A).withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: _isLocked
                            ? const Color(0xFFF0C15A)
                            : const Color(0xFF9E8AB8),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isLocked
                                ? _t('الغرفة مقفلة', 'Room is locked')
                                : _t('الغرفة مفتوحة', 'Room is open'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isLocked
                                ? _t(
                                    'يحتاج الانضمام إلى كلمة مرور',
                                    'Joining requires a password',
                                  )
                                : _t(
                                    'يمكن لأي شخص الانضمام',
                                    'Anyone can join freely',
                                  ),
                            style: const TextStyle(
                                color: Color(0xFF9E8AB8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isLocked,
                      activeThumbColor: const Color(0xFF8B26D9),
                      onChanged: (_) => _toggleLock(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(label: _t('تعديل معلومات الغرفة', 'Edit Room Info')),
          const SizedBox(height: 8),
          _GlassCard(
            child: Column(
              children: [
                _Field(ctrl: _nameCtrl, label: _t('اسم الغرفة', 'Room Name')),
                const SizedBox(height: 12),
                _Field(
                  ctrl: _descCtrl,
                  label: _t('الوصف', 'Description'),
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B26D9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _savingMeta ? null : _saveMeta,
                    child: _savingMeta
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(_t('حفظ', 'Save')),
                  ),
                ),
                const SizedBox(height: 8),
                _ComingSoonRow(
                  label: _t('تغيير صورة الغرفة', 'Change Room Image'),
                ),
                _ComingSoonRow(label: _t('موسيقى الغرفة', 'Room Music')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildGiftAnalyticsSection(),
        ],
      ),
    );
  }

  Widget _buildGiftAnalyticsSection() {
    if (_giftSummary.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: _t('ملخص الهدايا', 'Gift Summary')),
          const SizedBox(height: 8),
          _GlassCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _t('لا توجد هدايا بعد', 'No gifts yet'),
                  style: const TextStyle(color: Color(0xFF9E8AB8)),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: _t('ملخص الهدايا', 'Gift Summary')),
        const SizedBox(height: 8),
        _GlassCard(
          child: Column(
            children: _giftSummary.take(10).map((g) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Text('\u{1F381}', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        g['gift_name'] as String? ?? g['gift_code'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '×${g['count']}',
                      style: const TextStyle(
                        color: Color(0xFF9E8AB8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatCoins(g['total_coins'] as int),
                      style: const TextStyle(
                        color: Color(0xFFF0C15A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Tab: Members ─────────────────────────────────────────────────────────

  Color _roleColor(String role) {
    return switch (role) {
      'host'     => const Color(0xFFF0C15A),
      'speaker'  => const Color(0xFF8B26D9),
      'mod'      => const Color(0xFF4ADE80),
      _          => const Color(0xFF9E8AB8),
    };
  }

  String _roleText(String role) {
    return switch (role) {
      'host'    => _t('المضيف', 'Host'),
      'speaker' => _t('متحدث', 'Speaker'),
      'mod'     => _t('مشرف', 'Mod'),
      _         => _t('مستمع', 'Listener'),
    };
  }

  Widget _buildMembersTab() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

    if (_members.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A0D33),
              ),
              child: const Icon(Icons.people_outline_rounded,
                  color: Color(0xFF6E3AA8), size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              _t('لا يوجد أعضاء حالياً', 'No members yet'),
              style: const TextStyle(
                color: Color(0xFF9E8AB8),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _t('اسحب للأسفل للتحديث', 'Pull down to refresh'),
              style: const TextStyle(color: Color(0xFF5A4A72), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadMembers();
        if (mounted) setState(() {});
      },
      color: const Color(0xFF8B26D9),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: _members.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text(
                    _t('الأعضاء (${_members.length})', 'Members (${_members.length})'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _t('جميع الأعضاء', 'All members'),
                    style: const TextStyle(
                      color: Color(0xFF6E3AA8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }

          final m = _members[i - 1];
          final uid = m['user_id'] as String;
          final name = m['display_name'] as String? ?? 'Unknown';
          final role = m['role'] as String? ?? 'listener';
          final isMuted = (m['is_muted'] as bool?) ?? false;
          final seat = m['seat_number'] as int?;
          final publicId = m['public_user_id'] as String? ?? '';
          final isMe = uid == currentUserId;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _Avatar(url: m['avatar_url'] as String?),
                      if (seat != null)
                        Positioned(
                          right: -4, bottom: -4,
                          child: Container(
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF8B26D9),
                              border: Border.all(
                                color: const Color(0xFF120827), width: 1.5),
                            ),
                            child: Center(
                              child: Text(
                                seat.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name + (isMe ? ' ★' : ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe
                                      ? const Color(0xFFF0C15A)
                                      : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _roleColor(role).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _roleText(role),
                                style: TextStyle(
                                  color: _roleColor(role),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (publicId.isNotEmpty)
                          Text(
                            publicId,
                            style: const TextStyle(
                              color: Color(0xFF6E3AA8),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Actions (not shown for self or host)
                  if (!isMe && role != 'host') ...[
                    _ActionIcon(
                      icon: isMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      color: isMuted
                          ? Colors.red[400]!
                          : const Color(0xFF6E3AA8),
                      tooltip: isMuted
                          ? _t('إلغاء كتم', 'Unmute')
                          : _t('كتم', 'Mute'),
                      onTap: () => _muteMember(uid, !isMuted),
                    ),
                    const SizedBox(width: 4),
                    _ActionIcon(
                      icon: Icons.shield_rounded,
                      color: const Color(0xFF8B26D9),
                      tooltip: _t('مشرف', 'Mod'),
                      onTap: () => _promoteModerator(uid, name),
                    ),
                    const SizedBox(width: 4),
                    _ActionIcon(
                      icon: Icons.logout_rounded,
                      color: Colors.orange,
                      tooltip: _t('طرد', 'Kick'),
                      onTap: () => _kickMember(uid),
                    ),
                    const SizedBox(width: 4),
                    _ActionIcon(
                      icon: Icons.block_rounded,
                      color: Colors.red,
                      tooltip: _t('حظر', 'Ban'),
                      onTap: () => _banMember(uid, name),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Tab: Moderators ──────────────────────────────────────────────────────

  Widget _buildModsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t(
                    'المشرفون (${_moderators.length})',
                    'Moderators (${_moderators.length})',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        _ComingSoonBanner(
          label: _t(
            'سيتم قريباً: ضبط الصلاحيات التفصيلية',
            'Coming soon: granular permission controls',
          ),
        ),
        Expanded(
          child: _moderators.isEmpty
              ? Center(
                  child: Text(
                    _t('لا يوجد مشرفون', 'No moderators yet'),
                    style: const TextStyle(color: Color(0xFF9E8AB8)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadModerators();
                    if (mounted) setState(() {});
                  },
                  color: const Color(0xFF8B26D9),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _moderators.length,
                    itemBuilder: (_, i) {
                      final mod = _moderators[i];
                      return _GlassCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            _Avatar(url: mod.avatarUrl),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                mod.displayName ?? mod.userId.substring(0, 8),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _permIcon(mod.canMute, Icons.mic_off_rounded),
                            _permIcon(mod.canKick, Icons.logout_rounded),
                            const SizedBox(width: 4),
                            _ActionIcon(
                              icon: Icons.remove_circle_rounded,
                              color: Colors.red,
                              tooltip: _t('إزالة', 'Remove'),
                              onTap: () => _removeModerator(mod),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _permIcon(bool enabled, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Icon(
      icon,
      size: 16,
      color: enabled ? const Color(0xFF8B26D9) : const Color(0xFF3A2460),
    ),
  );

  // ── Tab: Bans ─────────────────────────────────────────────────────────────

  Widget _buildBansTab() {
    return _bans.isEmpty
        ? Center(
            child: Text(
              _t('لا يوجد محظورون', 'No banned users'),
              style: const TextStyle(color: Color(0xFF9E8AB8)),
            ),
          )
        : RefreshIndicator(
            onRefresh: () async {
              await _loadBans();
              if (mounted) setState(() {});
            },
            color: const Color(0xFF8B26D9),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _bans.length,
              itemBuilder: (_, i) {
                final ban = _bans[i];
                return _GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _Avatar(url: ban.avatarUrl),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ban.displayName ?? ban.userId.substring(0, 8),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (ban.reason?.isNotEmpty == true)
                              Text(
                                ban.reason!,
                                style: const TextStyle(
                                  color: Color(0xFF9E8AB8),
                                  fontSize: 11,
                                ),
                              ),
                            Text(
                              ban.isPermanent
                                  ? _t('حظر دائم', 'Permanent')
                                  : '${_t('ينتهي في', 'Expires')} ${ban.expiresAt!.day}/${ban.expiresAt!.month}',
                              style: TextStyle(
                                fontSize: 11,
                                color: ban.isExpired
                                    ? Colors.green
                                    : Colors.red[300],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _ActionIcon(
                        icon: Icons.lock_open_rounded,
                        color: Colors.green,
                        tooltip: _t('رفع الحظر', 'Unban'),
                        onTap: () => _unbanUser(ban),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
  }

  // ── Tab: Content ─────────────────────────────────────────────────────────

  Widget _buildContentTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadAnnouncement(), _loadSchedules()]);
        if (mounted) setState(() {});
      },
      color: const Color(0xFF8B26D9),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(label: _t('إعلان الغرفة', 'Room Announcement')),
          const SizedBox(height: 8),
          _GlassCard(
            child: Column(
              children: [
                TextField(
                  controller: _announcementCtrl,
                  maxLines: 3,
                  maxLength: 280,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: _t('نص الإعلان', 'Announcement text'),
                    labelStyle: const TextStyle(color: Color(0xFF9E8AB8)),
                    counterStyle: const TextStyle(color: Color(0xFF9E8AB8)),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF3A2460)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF8B26D9)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B26D9),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _savingAnnouncement
                            ? null
                            : _saveAnnouncement,
                        child: _savingAnnouncement
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_t('نشر', 'Publish')),
                      ),
                    ),
                    if (_activeAnnouncement != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[400],
                          side: BorderSide(color: Colors.red[800]!),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _clearAnnouncement,
                        child: Text(_t('حذف', 'Clear')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SectionHeader(label: _t('جدول البث', 'Schedule')),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle_rounded,
                  color: Color(0xFF8B26D9),
                ),
                tooltip: _t('إضافة جلسة', 'Add Session'),
                onPressed: _addSchedule,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_schedules.isEmpty)
            _GlassCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _t('لا توجد جلسات مجدولة', 'No scheduled sessions'),
                    style: const TextStyle(color: Color(0xFF9E8AB8)),
                  ),
                ),
              ),
            )
          else
            ..._schedules.map((s) {
              final dt = DateTime.tryParse(s['scheduled_at'] as String? ?? '');
              return _GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      color: Color(0xFF8B26D9),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['title'] as String? ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (dt != null)
                            Text(
                              '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Color(0xFF9E8AB8),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _ActionIcon(
                      icon: Icons.delete_rounded,
                      color: Colors.red,
                      tooltip: _t('حذف', 'Delete'),
                      onTap: () => _deleteSchedule(s['id'] as String),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _formatCoins(int coins) {
    if (coins >= 1000000) return '${(coins / 1000000).toStringAsFixed(1)}M';
    if (coins >= 1000) return '${(coins / 1000).toStringAsFixed(1)}K';
    return '$coins';
  }

  // ── Tab: Appearance ──────────────────────────────────────────────────────

  Widget _buildAppearanceTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(label: _t('مظهر الغرفة', 'Room Appearance')),
        const SizedBox(height: 14),

        // ── Cover image ──────────────────────────────────────────────
        _AppearanceImageCard(
          isArabic: _isArabic,
          titleAr: 'غلاف الغرفة',
          titleEn: 'Room Cover',
          subtitleAr: 'يظهر في قائمة الغرف كخلفية للبطاقة',
          subtitleEn: 'Shown in the rooms list as the card background',
          imageUrl: _roomCoverUrl,
          aspectRatio: 16 / 9,
          uploading: _uploadingCover,
          onChangeTap: _pickAndUploadCover,
          onRemoveTap: _roomCoverUrl != null ? _clearCover : null,
        ),
        const SizedBox(height: 16),

        // ── Avatar / icon ────────────────────────────────────────────
        _AppearanceImageCard(
          isArabic: _isArabic,
          titleAr: 'أيقونة الغرفة',
          titleEn: 'Room Icon',
          subtitleAr: 'تظهر داخل الغرفة في أعلى اليسار',
          subtitleEn: 'Shown inside the room at the top-left',
          imageUrl: _roomAvatarUrl,
          aspectRatio: 1,
          uploading: _uploadingAvatar,
          onChangeTap: _pickAndUploadAvatar,
          onRemoveTap: _roomAvatarUrl != null ? _clearAvatar : null,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ban dialog
// ─────────────────────────────────────────────────────────────────────────────

class _BanDialog extends StatelessWidget {
  const _BanDialog({
    required this.isArabic,
    required this.userName,
    required this.reasonCtrl,
  });

  final bool isArabic;
  final String userName;
  final TextEditingController reasonCtrl;

  String _t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF160B24),
      title: Text(
        '${_t("حظر", "Ban")} $userName',
        style: const TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: reasonCtrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: _t('سبب (اختياري)', 'Reason (optional)'),
          labelStyle: const TextStyle(color: Color(0xFF9E8AB8)),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF3A2460)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF8B26D9)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            _t('إلغاء', 'Cancel'),
            style: const TextStyle(color: Color(0xFF9E8AB8)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
          onPressed: () => Navigator.pop(context, true),
          child: Text(_t('حظر', 'Ban')),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A1745)),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFFF0C15A),
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A1745)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Color(0xFF9E8AB8), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF2A1745),
      backgroundImage: url != null ? NetworkImage(url!) : null,
      child: url == null
          ? const Icon(Icons.person, color: Color(0xFF9E8AB8), size: 18)
          : null,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.ctrl, required this.label, this.maxLines = 1});

  final TextEditingController ctrl;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9E8AB8)),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF3A2460)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF8B26D9)),
        ),
      ),
    );
  }
}

class _ComingSoonRow extends StatelessWidget {
  const _ComingSoonRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 14,
            color: Color(0xFF6E3AA8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9E8AB8), fontSize: 12),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0E2B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3A2460)),
            ),
            child: const Text(
              'Coming Soon',
              style: TextStyle(
                color: Color(0xFF6E3AA8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E2B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A2460)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 14,
            color: Color(0xFF6E3AA8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9E8AB8), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appearance image card
// ─────────────────────────────────────────────────────────────────────────────

class _AppearanceImageCard extends StatelessWidget {
  const _AppearanceImageCard({
    required this.isArabic,
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.aspectRatio,
    required this.uploading,
    required this.onChangeTap,
    this.imageUrl,
    this.onRemoveTap,
  });

  final bool isArabic;
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final String? imageUrl;
  final double aspectRatio;
  final bool uploading;
  final VoidCallback onChangeTap;
  final VoidCallback? onRemoveTap;

  @override
  Widget build(BuildContext context) {
    final title    = isArabic ? titleAr    : titleEn;
    final subtitle = isArabic ? subtitleAr : subtitleEn;
    final hasImage = imageUrl?.isNotEmpty == true;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A0D33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF4A3470).withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF0C15A),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF9E8AB8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),

          // Preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: hasImage
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => _NoImagePlaceholder(
                        aspectRatio: aspectRatio,
                      ),
                    )
                  : _NoImagePlaceholder(aspectRatio: aspectRatio),
            ),
          ),
          const SizedBox(height: 12),

          // Buttons row
          Row(
            textDirection:
                isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: uploading ? null : onChangeTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6E14B8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.image_rounded, size: 18),
                  label: Text(
                    isArabic ? 'تغيير' : 'Change',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (onRemoveTap != null) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onRemoveTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE63946),
                    side: const BorderSide(color: Color(0xFF4A0010)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: Text(
                    isArabic ? 'إزالة' : 'Remove',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NoImagePlaceholder extends StatelessWidget {
  const _NoImagePlaceholder({required this.aspectRatio});
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0720),
      child: Center(
        child: Icon(
          aspectRatio == 1
              ? Icons.mic_rounded
              : Icons.image_outlined,
          size: 38,
          color: const Color(0xFF4A3470),
        ),
      ),
    );
  }
}
