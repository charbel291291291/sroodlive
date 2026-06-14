import 'package:flutter/material.dart';

import '../models/room.dart';
import '../services/room_management_service.dart';

/// Premium settings bottom sheet (inspired by Image B).
///
/// Owners can edit name, description, and announcement.
/// All users see the current settings read-only.
class RoomSettingsSheet extends StatefulWidget {
  const RoomSettingsSheet({
    required this.room,
    required this.isArabic,
    required this.isOwner,
    required this.moderatorCount,
    required this.isLocked,
    required this.onToggleLock,
    super.key,
  });

  final Room room;
  final bool isArabic;
  final bool isOwner;
  final int moderatorCount;
  final bool isLocked;
  final Future<void> Function() onToggleLock;

  @override
  State<RoomSettingsSheet> createState() => _RoomSettingsSheetState();
}

class _RoomSettingsSheetState extends State<RoomSettingsSheet> {
  final _mgmt = const RoomManagementService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _announcementCtrl;
  bool _savingName = false;
  bool _savingAnnouncement = false;
  bool _lockBusy = false;
  bool _loadingAnnouncement = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.room.name);
    _announcementCtrl = TextEditingController();
    _loadAnnouncement();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _announcementCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnnouncement() async {
    try {
      final ann = await _mgmt.getActiveAnnouncement(widget.room.id);
      if (mounted) {
        setState(() {
          _announcementCtrl.text = ann?.message ?? '';
          _loadingAnnouncement = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAnnouncement = false);
    }
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || name == widget.room.name) return;
    setState(() => _savingName = true);
    try {
      await _mgmt.updateRoom(widget.room.id, name: name);
      if (mounted) _showSuccess(widget.isArabic ? 'تم تحديث الاسم' : 'Name updated');
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _saveAnnouncement() async {
    final text = _announcementCtrl.text.trim();
    setState(() => _savingAnnouncement = true);
    try {
      if (text.isEmpty) {
        await _mgmt.deactivateAnnouncements(widget.room.id);
      } else {
        await _mgmt.saveAnnouncement(widget.room.id, text);
      }
      if (mounted) {
        _showSuccess(widget.isArabic ? 'تم تحديث الإعلان' : 'Announcement updated');
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _savingAnnouncement = false);
    }
  }

  Future<void> _toggleLock() async {
    setState(() => _lockBusy = true);
    try {
      await widget.onToggleLock();
    } finally {
      if (mounted) setState(() => _lockBusy = false);
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A6FFF),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE63946)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Directionality(
      textDirection: textDir,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A1547), Color(0xFF1A0D33), Color(0xFF0F0820)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Grabber
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    isArabic ? 'إعدادات الغرفة' : 'Settings',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16, 0, 16,
                      16 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    shrinkWrap: true,
                    children: [
                      // ── Room Cover (placeholder) ──────────────────────────
                      _SettingsTile(
                        icon: Icons.image_rounded,
                        label: isArabic ? 'غلاف الغرفة' : 'Room Cover',
                        trailing: widget.room.coverUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  widget.room.coverUrl!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, stack) =>
                                      const Icon(Icons.broken_image_rounded,
                                          size: 24, color: Color(0xFF9E91B8)),
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded,
                                color: Color(0xFF9E91B8)),
                        onTap: widget.isOwner
                            ? () => _showComingSoon(
                                  isArabic ? 'رفع الغلاف' : 'Cover upload')
                            : null,
                      ),
                      const _SettingsDivider(),

                      // ── Room Label ────────────────────────────────────────
                      if (widget.isOwner)
                        _EditableSettingsTile(
                          icon: Icons.label_rounded,
                          label: isArabic ? 'اسم الغرفة' : 'Room Label',
                          controller: _nameCtrl,
                          isArabic: isArabic,
                          busy: _savingName,
                          onSave: _saveName,
                        )
                      else
                        _SettingsTile(
                          icon: Icons.label_rounded,
                          label: isArabic ? 'اسم الغرفة' : 'Room Label',
                          trailing: Text(
                            widget.room.name,
                            style: const TextStyle(
                              color: Color(0xFF9E91B8),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      const _SettingsDivider(),

                      // ── Announcement ──────────────────────────────────────
                      if (widget.isOwner)
                        _MultilineEditableSettingsTile(
                          icon: Icons.campaign_rounded,
                          label: isArabic ? 'الإعلان' : 'Announcement',
                          controller: _announcementCtrl,
                          isArabic: isArabic,
                          busy: _savingAnnouncement || _loadingAnnouncement,
                          onSave: _saveAnnouncement,
                        )
                      else
                        _SettingsTile(
                          icon: Icons.campaign_rounded,
                          label: isArabic ? 'الإعلان' : 'Announcement',
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: Color(0xFF9E91B8)),
                        ),
                      const _SettingsDivider(),

                      // ── Admin count ───────────────────────────────────────
                      _SettingsTile(
                        icon: Icons.admin_panel_settings_rounded,
                        label: isArabic ? 'المشرفون' : 'Admin',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.moderatorCount}/20',
                              style: const TextStyle(
                                color: Color(0xFFF0C15A),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded,
                                color: Color(0xFF9E91B8)),
                          ],
                        ),
                        onTap: () => Navigator.of(context).pop('open_admin'),
                      ),
                      const _SettingsDivider(),

                      // ── Lock Room ─────────────────────────────────────────
                      _SettingsTile(
                        icon: widget.isLocked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        label: isArabic
                            ? (widget.isLocked ? 'فتح الغرفة' : 'قفل الغرفة')
                            : (widget.isLocked ? 'Unlock Room' : 'Lock Room'),
                        trailing: _lockBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Switch(
                                value: widget.isLocked,
                                onChanged: widget.isOwner
                                    ? (_) => _toggleLock()
                                    : null,
                                activeThumbColor: const Color(0xFF8B26D9),
                              ),
                      ),
                      const _SettingsDivider(),

                      // ── Send pictures ─────────────────────────────────────
                      _SettingsTile(
                        icon: Icons.photo_rounded,
                        label: isArabic
                            ? 'إرسال صور في الغرفة'
                            : 'Send pictures in the room',
                        trailing: Switch(
                          value: true,
                          onChanged: widget.isOwner
                              ? (_) => _showComingSoon(
                                    isArabic ? 'ضبط الصور' : 'Picture settings')
                              : null,
                          activeThumbColor: const Color(0xFF8B26D9),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isArabic
              ? '$feature - قريباً'
              : '$feature — coming soon',
        ),
      ),
    );
  }
}

// ── Shared tile widgets ────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF8B26D9).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFFD8CFEA), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Colors.white.withValues(alpha: 0.07),
      indent: 50,
    );
  }
}

class _EditableSettingsTile extends StatefulWidget {
  const _EditableSettingsTile({
    required this.icon,
    required this.label,
    required this.controller,
    required this.isArabic,
    required this.busy,
    required this.onSave,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool isArabic;
  final bool busy;
  final VoidCallback onSave;

  @override
  State<_EditableSettingsTile> createState() => _EditableSettingsTileState();
}

class _EditableSettingsTileState extends State<_EditableSettingsTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(widget.icon, color: const Color(0xFFD8CFEA), size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  widget.controller.text.isNotEmpty
                      ? widget.controller.text
                      : (widget.isArabic ? 'لا يوجد' : 'Not set'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF9E91B8), fontSize: 12),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.chevron_right_rounded,
                  color: const Color(0xFF9E91B8),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          TextField(
            controller: widget.controller,
            textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.busy ? null : widget.onSave,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B26D9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: widget.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.isArabic ? 'حفظ' : 'Save'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MultilineEditableSettingsTile extends StatefulWidget {
  const _MultilineEditableSettingsTile({
    required this.icon,
    required this.label,
    required this.controller,
    required this.isArabic,
    required this.busy,
    required this.onSave,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool isArabic;
  final bool busy;
  final VoidCallback onSave;

  @override
  State<_MultilineEditableSettingsTile> createState() =>
      _MultilineEditableSettingsTileState();
}

class _MultilineEditableSettingsTileState
    extends State<_MultilineEditableSettingsTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(widget.icon, color: const Color(0xFFD8CFEA), size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.controller.text.isNotEmpty)
                        Text(
                          widget.controller.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF9E91B8), fontSize: 11),
                        ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.chevron_right_rounded,
                  color: const Color(0xFF9E91B8),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          TextField(
            controller: widget.controller,
            maxLines: 3,
            textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: widget.isArabic
                  ? 'اكتب إعلاناً للغرفة…'
                  : 'Write a room announcement…',
              hintStyle:
                  const TextStyle(color: Color(0xFF6B5A8A), fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.busy ? null : widget.onSave,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B26D9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: widget.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.isArabic ? 'حفظ الإعلان' : 'Save Announcement'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
