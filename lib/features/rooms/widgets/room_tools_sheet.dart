import 'package:flutter/material.dart';

import '../../games/screens/crash_game_screen.dart';
import '../services/room_management_service.dart';
import '../models/room_ban.dart';
import 'room_settings_sheet.dart';
import '../models/room.dart';

/// Interactive Features + Management Tools bottom sheet (inspired by Image C).
///
/// Three sections:
///   A – Interactive features (Counter, Team PK, Salute, Red Envelope, Game Center)
///   B – Management tools (Clean Text, Settings, Music, Voice Effect, Lock Room,
///                         Mic Mode, Background, Kick Record)
///   C – Other tools (Sound On, Visual Effect)
class RoomToolsSheet extends StatefulWidget {
  const RoomToolsSheet({
    required this.room,
    required this.isArabic,
    required this.isOwner,
    required this.isHost,
    required this.moderatorCount,
    required this.isLocked,
    required this.onToggleLock,
    required this.onClearChat,
    super.key,
  });

  final Room room;
  final bool isArabic;
  final bool isOwner;
  final bool isHost;
  final int moderatorCount;
  final bool isLocked;
  final Future<void> Function() onToggleLock;
  final VoidCallback onClearChat;

  @override
  State<RoomToolsSheet> createState() => _RoomToolsSheetState();
}

class _RoomToolsSheetState extends State<RoomToolsSheet> {
  final _mgmt = const RoomManagementService();
  bool _soundOn = true;

  // ── Navigation helpers ─────────────────────────────────────────────────────

  void _openSettings() {
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomSettingsSheet(
        room: widget.room,
        isArabic: widget.isArabic,
        isOwner: widget.isOwner,
        moderatorCount: widget.moderatorCount,
        isLocked: widget.isLocked,
        onToggleLock: widget.onToggleLock,
      ),
    );
  }

  void _openGameCenter() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrashGameScreen(isArabic: widget.isArabic),
      ),
    );
  }

  void _openKickRecord() async {
    final bans = await _mgmt.getBans(widget.room.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _KickRecordSheet(bans: bans, isArabic: widget.isArabic),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isArabic ? '$feature - قريباً' : '$feature — coming soon',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDir,
      child: SafeArea(
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
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16, 8, 16,
                    16 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Section A: Interactive features ──────────────────
                      _SectionLabel(
                        label: isArabic ? 'ميزات تفاعلية' : 'Interactive',
                      ),
                      const SizedBox(height: 10),
                      _IconGrid(
                        items: [
                          _ToolItem(
                            icon: Icons.add_circle_outline_rounded,
                            label: isArabic ? 'العداد' : 'Counter',
                            onTap: () => _showComingSoon(
                              isArabic ? 'العداد' : 'Counter'),
                          ),
                          _ToolItem(
                            icon: Icons.groups_rounded,
                            label: isArabic ? 'بي كي' : 'Team PK',
                            onTap: () => _showComingSoon(
                              isArabic ? 'بي كي' : 'Team PK'),
                          ),
                          _ToolItem(
                            icon: Icons.military_tech_rounded,
                            label: isArabic ? 'تحية' : 'Salute',
                            onTap: () => _showComingSoon(
                              isArabic ? 'تحية' : 'Salute'),
                          ),
                          _ToolItem(
                            icon: Icons.redeem_rounded,
                            label: isArabic ? 'مظروف أحمر' : 'Red Envelope',
                            onTap: () => _showComingSoon(
                              isArabic ? 'مظروف أحمر' : 'Red Envelope'),
                          ),
                          _ToolItem(
                            icon: Icons.sports_esports_rounded,
                            label: isArabic ? 'مركز الألعاب' : 'Game Center',
                            onTap: _openGameCenter,
                            accent: const Color(0xFFF0C15A),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Section B: Management tools ──────────────────────
                      _SectionLabel(
                        label: isArabic ? 'أدوات الإدارة' : 'Management',
                      ),
                      const SizedBox(height: 10),
                      _IconGrid(
                        items: [
                          _ToolItem(
                            icon: Icons.cleaning_services_rounded,
                            label: isArabic ? 'مسح الدردشة' : 'Clean Text',
                            onTap: (widget.isOwner || widget.isHost)
                                ? () {
                                    Navigator.of(context).pop();
                                    widget.onClearChat();
                                  }
                                : null,
                          ),
                          _ToolItem(
                            icon: Icons.settings_rounded,
                            label: isArabic ? 'الإعدادات' : 'Settings',
                            onTap: (widget.isOwner || widget.isHost)
                                ? _openSettings
                                : null,
                          ),
                          _ToolItem(
                            icon: Icons.music_note_rounded,
                            label: isArabic ? 'الموسيقى' : 'Music',
                            onTap: () => _showComingSoon(
                              isArabic ? 'الموسيقى' : 'Music'),
                          ),
                          _ToolItem(
                            icon: Icons.graphic_eq_rounded,
                            label: isArabic ? 'مؤثر صوتي' : 'Voice Effect',
                            onTap: () => _showComingSoon(
                              isArabic ? 'مؤثر صوتي' : 'Voice Effect'),
                          ),
                          _ToolItem(
                            icon: widget.isLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            label: widget.isLocked
                                ? (isArabic ? 'فتح الغرفة' : 'Unlock Room')
                                : (isArabic ? 'قفل الغرفة' : 'Lock Room'),
                            onTap: (widget.isOwner || widget.isHost)
                                ? () async {
                                    Navigator.of(context).pop();
                                    await widget.onToggleLock();
                                  }
                                : null,
                            accent: widget.isLocked
                                ? const Color(0xFFE63946)
                                : null,
                          ),
                          _ToolItem(
                            icon: Icons.mic_rounded,
                            label: isArabic ? 'وضع الميكروفون' : 'Mic Mode',
                            onTap: () => _showComingSoon(
                              isArabic ? 'وضع الميكروفون' : 'Mic Mode'),
                          ),
                          _ToolItem(
                            icon: Icons.wallpaper_rounded,
                            label: isArabic ? 'الخلفية' : 'Background',
                            onTap: () => _showComingSoon(
                              isArabic ? 'الخلفية' : 'Background'),
                          ),
                          _ToolItem(
                            icon: Icons.person_off_rounded,
                            label: isArabic ? 'سجل الطرد' : 'Kick Record',
                            onTap: (widget.isOwner || widget.isHost)
                                ? _openKickRecord
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Section C: Other tools ───────────────────────────
                      _SectionLabel(
                        label: isArabic ? 'أدوات أخرى' : 'Other',
                      ),
                      const SizedBox(height: 10),
                      _IconGrid(
                        items: [
                          _ToolItem(
                            icon: _soundOn
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            label: isArabic ? 'الصوت' : 'Sound On',
                            isToggled: _soundOn,
                            onTap: () => setState(() => _soundOn = !_soundOn),
                            accent: _soundOn
                                ? const Color(0xFF1A6FFF)
                                : null,
                          ),
                          _ToolItem(
                            icon: Icons.auto_awesome_rounded,
                            label: isArabic ? 'تأثير بصري' : 'Visual Effect',
                            onTap: () => _showComingSoon(
                              isArabic ? 'تأثير بصري' : 'Visual Effect'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
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

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ToolItem {
  const _ToolItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent,
    this.isToggled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? accent;
  final bool isToggled;
}

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.items});
  final List<_ToolItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _GridCell(item: items[i]),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({required this.item});
  final _ToolItem item;

  @override
  Widget build(BuildContext context) {
    final active = item.onTap != null;
    final accent = item.accent ?? const Color(0xFF8B26D9);

    return GestureDetector(
      onTap: item.onTap,
      child: Opacity(
        opacity: active ? 1.0 : 0.38,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: (item.isToggled || item.accent != null)
                    ? accent.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (item.isToggled || item.accent != null)
                      ? accent.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
              child: Icon(
                item.icon,
                size: 22,
                color: (item.isToggled || item.accent != null)
                    ? accent
                    : const Color(0xFFD8CFEA),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kick Record sub-sheet ────────────────────────────────────────────────────

class _KickRecordSheet extends StatelessWidget {
  const _KickRecordSheet({
    required this.bans,
    required this.isArabic,
  });

  final List<RoomBan> bans;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    return Directionality(
      textDirection: textDir,
      child: SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF1A0D33),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  isArabic ? 'سجل الطرد' : 'Kick Record',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Flexible(
                child: bans.isEmpty
                    ? Center(
                        child: Text(
                          isArabic ? 'لا يوجد مطرودون' : 'No bans yet',
                          style: const TextStyle(
                              color: Color(0xFF9E91B8), fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: bans.length,
                        separatorBuilder: (ctx, idx) => Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                        itemBuilder: (_, i) {
                          final ban = bans[i];
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 4),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF8B26D9),
                              backgroundImage: ban.avatarUrl != null
                                  ? NetworkImage(ban.avatarUrl!)
                                  : null,
                              child: ban.avatarUrl == null
                                  ? const Icon(Icons.person_rounded,
                                      color: Colors.white, size: 18)
                                  : null,
                            ),
                            title: Text(
                              ban.displayName ?? ban.userId,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: ban.reason != null
                                ? Text(
                                    ban.reason!,
                                    style: const TextStyle(
                                        color: Color(0xFF9E91B8), fontSize: 12),
                                  )
                                : null,
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
