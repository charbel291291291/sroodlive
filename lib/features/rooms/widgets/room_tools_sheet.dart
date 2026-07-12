import 'dart:async';
import 'dart:math' as math;
import 'package:srood_live/shared/utils/error_utils.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../games/crash_v2/crash_v2_screen.dart';
import '../../games/screens/gold_ladder_quiz_screen.dart';
import '../../games/screens/hungry_cat_webview_screen.dart';
import '../../games/screens/magic_srood_screen.dart';
import '../../games/screens/spin_wheel_screen.dart';
import '../../games/screens/srood_loto_screen.dart';
import '../../games/screens/srood_treasure_screen.dart';
import '../../charisma/screens/charisma_challenge_screen.dart';
import '../services/room_management_service.dart';
import '../models/room_member.dart';
import 'pk_start_sheet.dart';
import 'room_settings_sheet.dart';
import '../models/room.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// --------------------
// RoomToolsSheet - premium tools bottom sheet for live rooms.
//
// Overflow fix: SafeArea is NOT used as a wrapper. Instead we read
// MediaQuery.viewPadding.bottom (device navigation bar inset) and add it
// explicitly to the scroll content bottom padding. This avoids the 1.1 px
// overflow that happens when SafeArea pads the sheet before the Column
// computes its height.
// --------------------

class RoomToolsSheet extends StatefulWidget {
  const RoomToolsSheet({
    required this.room,
    required this.isArabic,
    required this.isOwner,
    required this.isHost,
    required this.isModerator,
    required this.moderatorCount,
    required this.onClearChat,
    this.onMaxSeatsChanged,
    this.onSoundChanged,
    this.onVisualChanged,
    this.onBackgroundChanged,
    this.micMembers = const [],
    this.activePkSessionId,
    this.onPkStarted,
    this.onPkCancelRequested,
    this.onMusicTap,
    this.onRedEnvelopeCreated,
    super.key,
  });

  final Room room;
  final bool isArabic;
  final bool isOwner;
  final bool isHost;
  final bool isModerator;
  final int moderatorCount;
  final VoidCallback onClearChat;
  final void Function(int newSeats)? onMaxSeatsChanged;
  final void Function(bool)? onSoundChanged;
  final void Function(bool)? onVisualChanged;
  final void Function(String? backgroundUrl)? onBackgroundChanged;
  // PK integration
  final List<RoomMember> micMembers;
  final String? activePkSessionId;
  final VoidCallback? onPkStarted;
  final VoidCallback? onPkCancelRequested;
  // Music
  final VoidCallback? onMusicTap;
  final ValueChanged<Map<String, dynamic>>? onRedEnvelopeCreated;

  @override
  State<RoomToolsSheet> createState() => _RoomToolsSheetState();
}

class _RoomToolsSheetState extends State<RoomToolsSheet> {
  bool _soundOn = true;
  bool _visualOn = true;

  static const _kSoundKey = 'room_pref_sound';
  static const _kVisualKey = 'room_pref_visual';

  bool get _canManage => widget.isOwner || widget.isHost;

  // Moderators can use a subset of tools (Clean, Kicks, Mic Mode).
  bool get _canModerate => _canManage || widget.isModerator;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _soundOn = prefs.getBool(_kSoundKey) ?? true;
        _visualOn = prefs.getBool(_kVisualKey) ?? true;
      });
    }
  }

  Future<void> _toggleSound() async {
    HapticFeedback.selectionClick();
    final next = !_soundOn;
    setState(() => _soundOn = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundKey, next);
    widget.onSoundChanged?.call(next);
  }

  Future<void> _toggleVisual() async {
    HapticFeedback.selectionClick();
    final next = !_visualOn;
    setState(() => _visualOn = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVisualKey, next);
    widget.onVisualChanged?.call(next);
  }

  String _t(String ar, String en) => context.isArabic ? ar : en;

  // -- Permission check ------------------------------------------------------

  void _requirePermission(VoidCallback onGranted, {String tool = 'unknown'}) {
    if (_canManage) {
      debugPrint('[RoomPerm] tool=$tool allowed=true reason=canManage');
      onGranted();
    } else {
      debugPrint(
        '[RoomPerm] tool=$tool allowed=false '
        'isOwner=${widget.isOwner} isHost=${widget.isHost} isModerator=${widget.isModerator}',
      );
      _snack(
        _t(
          'ليس لديك صلاحية لاستخدام هذه الأداة',
          'You do not have permission to use this tool.',
        ),
        isError: true,
      );
    }
  }

  void _requireModeratePermission(
    VoidCallback onGranted, {
    String tool = 'unknown',
  }) {
    if (_canModerate) {
      debugPrint('[RoomPerm] tool=$tool allowed=true reason=canModerate');
      onGranted();
    } else {
      debugPrint(
        '[RoomPerm] tool=$tool allowed=false '
        'isOwner=${widget.isOwner} isHost=${widget.isHost} isModerator=${widget.isModerator}',
      );
      _snack(
        _t(
          'ليس لديك صلاحية لاستخدام هذه الأداة',
          'You do not have permission to use this tool.',
        ),
        isError: true,
      );
    }
  }

  // -- Snack helper ----------------------------------------------------------

  void _snack(String msg, {bool isError = false}) {
    SroodToast.show(
      context,
      msg,
      type: isError ? SroodToastType.error : SroodToastType.success,
    );
  }

  // -- Navigation helpers ----------------------------------------------------

  void _openSettings() {
    HapticFeedback.lightImpact();
    // Capture everything from context/widget BEFORE popping — once this sheet is
    // popped the BuildContext is no longer mounted and must not be used in closures.
    final isArabic = context.isArabic;
    final room = widget.room;
    final isOwner = widget.isOwner;
    final moderatorCount = widget.moderatorCount;
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator:
          true, // anchor to root overlay, not the popped sheet route
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomSettingsSheet(
        room: room,
        isArabic: isArabic,
        isOwner: isOwner,
        moderatorCount: moderatorCount,
      ),
    );
  }

  void _openGameCenter() {
    HapticFeedback.lightImpact();
    // Capture isArabic before popping - context will be defunct afterwards.
    final isArabic = context.isArabic;
    Navigator.of(context).pop(); // close tools sheet
    // useRootNavigator: true so the sheet is anchored to the root navigator,
    // not to the (now-popped) tools sheet context.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) =>
          _GameCenterSheet(isArabic: isArabic, roomId: widget.room.id),
    );
  }

  Future<void> _openRedEnvelope() async {
    HapticFeedback.lightImpact();

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _LuckyBagSheet(roomId: widget.room.id, isArabic: context.isArabic),
    );

    if (!mounted || result == null) return;

    Map<String, dynamic>? envelope;
    if (result is Map) {
      envelope = Map<String, dynamic>.from(result);
    } else if (result is List && result.isNotEmpty && result.first is Map) {
      envelope = Map<String, dynamic>.from(result.first as Map);
    }

    if (envelope != null) {
      widget.onRedEnvelopeCreated?.call(envelope);
    }

    if (!mounted) return;

    // Close the tools sheet now that the lucky bag was sent successfully.
    Navigator.of(context).pop();

    SroodToast.show(
      context,
      context.isArabic ? 'تم إرسال حقيبة الحظ' : 'Lucky Bag sent!',
      type: SroodToastType.success,
    );
  }

  void _openMusic() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
    widget.onMusicTap?.call();
  }

  void _confirmClearChat() {
    HapticFeedback.mediumImpact();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0D33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t('مسح الدردشة', 'Clear Chat'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          _t(
            'هل أنت متأكد أنك تريد مسح جميع رسائل الدردشة؟',
            'Are you sure you want to clear all chat messages?',
          ),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t('إلغاء', 'Cancel'),
              style: const TextStyle(color: Color(0xFF9E91B8)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B26D9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(true);
              Navigator.of(context).pop(); // close tools sheet
              widget.onClearChat();
            },
            child: Text(_t('مسح', 'Clear')),
          ),
        ],
      ),
    );
  }

  void _openTeamPk() {
    HapticFeedback.lightImpact();

    // If a PK is already active and user is host, offer to cancel.
    if (widget.activePkSessionId != null && _canManage) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PkActiveOptionsSheet(
          isArabic: context.isArabic,
          onCancel: () {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
            widget.onPkCancelRequested?.call();
          },
        ),
      );
      return;
    }

    if (!_canManage) return;

    final micMembers = widget.micMembers;
    if (micMembers.isEmpty) {
      SroodToast.show(
        context,
        context.isArabic ? 'لا يوجد أحد على المايك' : 'No one is on mic',
        type: SroodToastType.info,
      );
      return;
    }

    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PkStartSheet(
        roomId: widget.room.id,
        micMembers: micMembers,
        isArabic: context.isArabic,
      ),
    ).then((started) {
      if (!mounted) return;
      if (started == true) {
        Navigator.of(context).pop(); // close tools sheet
        widget.onPkStarted?.call();
      }
    });
  }

  void _openMicMode() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MicModeSheet(
        isArabic: context.isArabic,
        roomId: widget.room.id,
        currentSeats: widget.room.maxSeats,
        onSeatsChanged: widget.onMaxSeatsChanged,
      ),
    );
  }

  void _openBackground() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BackgroundSheet(
        isArabic: context.isArabic,
        roomId: widget.room.id,
        currentBackgroundUrl: widget.room.backgroundUrl,
        onBackgroundChanged: widget.onBackgroundChanged,
      ),
    );
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    // Read nav-bar inset without SafeArea wrapper so we control padding exactly.
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: textDir,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF231440), Color(0xFF160C2F), Color(0xFF0C0619)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            _Handle(),
            // Scrollable content - bottom padding includes nav-bar inset
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 20 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section A - Interactive
                    _SectionLabel(_t('ميزات تفاعلية', 'Interactive')),
                    const SizedBox(height: 10),
                    _ToolGrid(
                      isArabic: isArabic,
                      items: [
                        _ToolDef(
                          icon: Icons.groups_2_rounded,
                          labelAr: 'بي كي',
                          labelEn: 'Team PK',
                          onTap: _canManage
                              ? _openTeamPk
                              : () => _requirePermission(() {}, tool: 'TeamPK'),
                          disabled: !_canManage,
                        ),
                        _ToolDef(
                          icon: Icons.redeem_rounded,
                          labelAr: 'حقيبة',
                          labelEn: 'Lucky',
                          accent: const Color(0xFFE63946),
                          onTap: _openRedEnvelope,
                        ),
                        _ToolDef(
                          icon: Icons.sports_esports_rounded,
                          labelAr: 'ألعاب',
                          labelEn: 'Game',
                          accent: const Color(0xFFF0C15A),
                          onTap: _openGameCenter,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section B - Management
                    _SectionLabel(_t('أدوات الإدارة', 'Management')),
                    const SizedBox(height: 10),
                    _ToolGrid(
                      isArabic: isArabic,
                      items: [
                        _ToolDef(
                          icon: Icons.cleaning_services_rounded,
                          labelAr: 'مسح',
                          labelEn: 'Clean',
                          onTap: _canModerate
                              ? _confirmClearChat
                              : () => _requireModeratePermission(
                                  () {},
                                  tool: 'Clean',
                                ),
                          disabled: !_canModerate,
                        ),
                        _ToolDef(
                          icon: Icons.settings_rounded,
                          labelAr: 'الإعدادات',
                          labelEn: 'Settings',
                          onTap: _canManage
                              ? _openSettings
                              : () =>
                                    _requirePermission(() {}, tool: 'Settings'),
                          disabled: !_canManage,
                        ),
                        _ToolDef(
                          icon: Icons.music_note_rounded,
                          labelAr: 'موسيقى',
                          labelEn: 'Music',
                          accent: const Color(0xFFC875FF),
                          onTap: _openMusic,
                        ),
                        _ToolDef(
                          icon: Icons.mic_rounded,
                          labelAr: 'ميكروفون',
                          labelEn: 'Mic Mode',
                          onTap: _canModerate
                              ? _openMicMode
                              : () => _requireModeratePermission(
                                  () {},
                                  tool: 'MicMode',
                                ),
                          disabled: !_canModerate,
                        ),
                        _ToolDef(
                          icon: Icons.wallpaper_rounded,
                          labelAr: 'الخلفية',
                          labelEn: 'Background',
                          onTap: _openBackground,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section C - Other
                    _SectionLabel(_t('أدوات أخرى', 'Other')),
                    const SizedBox(height: 10),
                    _ToolGrid(
                      isArabic: isArabic,
                      items: [
                        _ToolDef(
                          icon: _soundOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          labelAr: _soundOn ? 'الصوت' : 'كتم',
                          labelEn: _soundOn ? 'Sound' : 'Muted',
                          accent: _soundOn ? const Color(0xFF1A8CB0) : null,
                          isToggled: _soundOn,
                          onTap: _toggleSound,
                        ),
                        _ToolDef(
                          icon: _visualOn
                              ? Icons.auto_awesome_rounded
                              : Icons.auto_awesome_outlined,
                          labelAr: _visualOn ? 'مؤثرات' : 'بدون مؤثرات',
                          labelEn: _visualOn ? 'Visual' : 'Visual Off',
                          accent: _visualOn ? const Color(0xFF8B26D9) : null,
                          isToggled: _visualOn,
                          onTap: _toggleVisual,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------
// Tool definition data class
// --------------------

class _ToolDef {
  const _ToolDef({
    required this.icon,
    required this.labelAr,
    required this.labelEn,
    this.onTap,
    this.accent,
    this.isToggled = false,
    this.disabled = false,
  });

  final IconData icon;
  final String labelAr;
  final String labelEn;
  final VoidCallback? onTap;
  final Color? accent;
  final bool isToggled;
  final bool disabled;
}

// --------------------
// Tool grid - uses Wrap instead of GridView to avoid aspect-ratio overflow.
// Each tile has a fixed 56x56 icon box and a 1-line label below it.
// Total tile height ≈ 56 + 5 + 15 = 76 px, so 5 columns at ~64 px wide each
// never overflows the grid cell.
// --------------------

class _ToolGrid extends StatelessWidget {
  const _ToolGrid({required this.items, required this.isArabic});

  final List<_ToolDef> items;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 5 columns with 8 px gaps -> each tile width
        const cols = 5;
        const gap = 8.0;
        final tileW = (constraints.maxWidth - gap * (cols - 1)) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: tileW,
                  child: _ToolTile(
                    def: item,
                    label: isArabic ? item.labelAr : item.labelEn,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// --------------------
// Individual tool tile - premium nav-footer style
// --------------------

class _ToolTile extends StatefulWidget {
  const _ToolTile({required this.def, required this.label});

  final _ToolDef def;
  final String label;

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 140),
      lowerBound: 0,
      upperBound: 1,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _press, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _press.forward();
  void _onTapUp(_) => _press.reverse();
  void _onTapCancel() => _press.reverse();

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final active = def.onTap != null && !def.disabled;
    final accent = def.accent ?? const Color(0xFF8B26D9);
    final isActive = def.isToggled || def.accent != null;

    return GestureDetector(
      onTapDown: active ? _onTapDown : null,
      onTapUp: active ? _onTapUp : null,
      onTapCancel: active ? _onTapCancel : null,
      onTap: def.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Opacity(
          opacity: def.disabled ? 0.40 : 1.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon container
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: isActive
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.30),
                            accent.withValues(alpha: 0.12),
                          ],
                        )
                      : LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.10),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  border: Border.all(
                    color: isActive
                        ? accent.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 1.2,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.28),
                            blurRadius: 12,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  def.icon,
                  size: 22,
                  color: isActive ? accent : const Color(0xFFCBC4E0),
                ),
              ),
              const SizedBox(height: 5),
              // Label - always 1 line, ellipsis
              Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: isActive
                      ? accent.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.75),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------
// Helper sub-widgets
// --------------------

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.40),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// --------------------
// --------------------
// Shown when a PK is already active and host opens the tool again.
// --------------------

class _PkActiveOptionsSheet extends StatelessWidget {
  const _PkActiveOptionsSheet({required this.isArabic, required this.onCancel});
  final bool isArabic;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final t = isArabic;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF231440), Color(0xFF160C2F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Handle(),
          const SizedBox(height: 14),
          Text(
            t ? 'منافسة نشطة' : 'PK is Live',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t ? 'المنافسة جارية الآن' : 'A battle is currently in progress.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE63946),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: onCancel,
              child: Text(
                t ? 'إلغاء المنافسة' : 'Cancel PK',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              t ? 'رجوع' : 'Go Back',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------
// Mic Mode Sheet - picks 6 / 9 / 12 mic seats and updates rooms.max_seats
// --------------------

class _MicModeSheet extends StatefulWidget {
  const _MicModeSheet({
    required this.isArabic,
    required this.roomId,
    required this.currentSeats,
    this.onSeatsChanged,
  });
  final bool isArabic;
  final String roomId;
  final int currentSeats;
  final void Function(int)? onSeatsChanged;

  @override
  State<_MicModeSheet> createState() => _MicModeSheetState();
}

class _MicModeSheetState extends State<_MicModeSheet> {
  static const _options = [
    (
      seats: 6,
      ar: '٦ مقاعد',
      en: '6 Seats',
      descAr: 'مناسب للغرف الصغيرة',
      descEn: 'Best for small rooms',
    ),
    (
      seats: 9,
      ar: '٩ مقاعد',
      en: '9 Seats',
      descAr: 'توازن مثالي',
      descEn: 'Balanced experience',
    ),
    (
      seats: 12,
      ar: '١٢ مقعد',
      en: '12 Seats',
      descAr: 'للغرف الكبيرة والحفلات',
      descEn: 'Large rooms & events',
    ),
  ];

  late int _selected;
  bool _saving = false;
  final _mgmt = const RoomManagementService();

  @override
  void initState() {
    super.initState();
    _selected = widget.currentSeats;
  }

  String _t(String ar, String en) => context.isArabic ? ar : en;

  Future<void> _pick(int seats) async {
    if (_saving || seats == _selected) return;
    setState(() {
      _selected = seats;
      _saving = true;
    });
    try {
      await _mgmt.updateRoom(widget.roomId, maxSeats: seats);
      widget.onSeatsChanged?.call(seats);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _selected = widget.currentSeats;
          _saving = false;
        });
        SroodToast.show(
          context,
          _t('فشل تحديث المقاعد', 'Failed to update seats'),
          type: SroodToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF231440), Color(0xFF160C2F)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Handle(),
          const SizedBox(height: 8),
          Text(
            _t('عدد مقاعد الميكروفون', 'Mic Seats'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'يؤثر على جميع المشاركين في الغرفة',
              'Affects all participants in the room',
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(_options.length, (i) {
            final opt = _options[i];
            final isSelected = _selected == opt.seats;
            return GestureDetector(
              onTap: _saving ? null : () => _pick(opt.seats),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isSelected
                      ? const Color(0xFF8B26D9).withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF8B26D9)
                        : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? const Color(0xFF8B26D9).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                      child: Center(
                        child: Text(
                          '${opt.seats}',
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFC875FF)
                                : Colors.white.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(opt.ar, opt.en),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _t(opt.descAr, opt.descEn),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_saving && isSelected)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFC875FF),
                        ),
                      )
                    else if (isSelected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFFC875FF),
                        size: 20,
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// --------------------
// Background Sheet - gradient presets (local) + custom image upload (global)
// --------------------

class _BackgroundSheet extends StatefulWidget {
  const _BackgroundSheet({
    required this.isArabic,
    required this.roomId,
    this.currentBackgroundUrl,
    this.onBackgroundChanged,
  });
  final bool isArabic;
  final String roomId;
  final String? currentBackgroundUrl;
  final void Function(String?)? onBackgroundChanged;

  @override
  State<_BackgroundSheet> createState() => _BackgroundSheetState();
}

class _BackgroundSheetState extends State<_BackgroundSheet> {
  static const _kBgKey = 'room_pref_background';

  static const _themes = [
    (
      ar: 'ليلي كلاسيكي',
      en: 'Classic Night',
      colors: [Color(0xFF231440), Color(0xFF160C2F), Color(0xFF0C0619)],
    ),
    (
      ar: 'شفق أرجواني',
      en: 'Purple Dusk',
      colors: [Color(0xFF2D1B69), Color(0xFF11998e), Color(0xFF1A0D33)],
    ),
    (
      ar: 'نار ذهبية',
      en: 'Golden Flame',
      colors: [Color(0xFF3D1C02), Color(0xFF7B3F00), Color(0xFF1A0900)],
    ),
    (
      ar: 'سماء زرقاء',
      en: 'Deep Ocean',
      colors: [Color(0xFF0A1628), Color(0xFF1A3A5C), Color(0xFF0D1F35)],
    ),
  ];

  int _selectedTheme = 0;
  bool _uploading = false;
  final _mgmt = const RoomManagementService();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _selectedTheme = prefs.getInt(_kBgKey) ?? 0);
    });
  }

  String _t(String ar, String en) => context.isArabic ? ar : en;

  Future<void> _pickTheme(int index) async {
    setState(() => _selectedTheme = index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBgKey, index);
    // Clear any uploaded background from the room so gradient shows for all
    await _mgmt.updateRoom(widget.roomId, clearBackground: true);
    widget.onBackgroundChanged?.call(null);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (file == null) return;
    if (!mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? 'image/jpeg';
      final url = await _mgmt.uploadRoomBackground(widget.roomId, bytes, mime);
      await _mgmt.updateRoom(widget.roomId, backgroundUrl: url);
      widget.onBackgroundChanged?.call(url);
      widget.onBackgroundChanged?.call(url);
      if (!mounted) return;
      SroodToast.show(
        context,
        'Background updated',
        type: SroodToastType.success,
      );
      Navigator.of(context).pop();
    } catch (e, st) {
      debugError('_BackgroundSheetState._uploadImage', e, st);
      if (!mounted) return;
      setState(() => _uploading = false);
      SroodToast.show(
        context,
        'Failed to upload image',
        type: SroodToastType.error,
      );
    }
  }

  Future<void> _removeBackground() async {
    if (_uploading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0D33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove background?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'The room will revert to its default color.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF9E91B8)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE63946),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _mgmt.updateRoom(widget.roomId, clearBackground: true);
      widget.onBackgroundChanged?.call(null);
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugError('_BackgroundSheetState._removeBackground', e, st);
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final hasCustomBg = widget.currentBackgroundUrl != null;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF231440), Color(0xFF160C2F)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Handle(),
            const SizedBox(height: 8),
            Text(
              _t('خلفية الغرفة', 'Room Background'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Visible to everyone in the room',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            // -- Gradient presets --
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _t('ألوان', 'COLORS').toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.4,
              ),
              itemCount: _themes.length,
              itemBuilder: (_, i) {
                final theme = _themes[i];
                final isSelected = !hasCustomBg && _selectedTheme == i;
                return GestureDetector(
                  onTap: _uploading ? null : () => _pickTheme(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: theme.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFF0C15A)
                            : Colors.white.withValues(alpha: 0.12),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          _t(theme.ar, theme.en),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF0C15A),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 12,
                                color: Colors.black,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            // -- Custom image upload --
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _t('صورة مخصصة', 'CUSTOM IMAGE').toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (hasCustomBg) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    Image.network(
                      widget.currentBackgroundUrl!,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 100,
                        color: Colors.white.withValues(alpha: 0.05),
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _uploading ? null : _removeBackground,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _t('صورة مخصصة نشطة', 'Custom image active'),
                          style: const TextStyle(
                            color: Color(0xFFF0C15A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC875FF),
                  side: BorderSide(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _uploading ? null : _uploadImage,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFC875FF),
                        ),
                      )
                    : const Icon(Icons.add_photo_alternate_rounded, size: 20),
                label: Text(
                  _uploading
                      ? _t('جاري الرفع...', 'Uploading...')
                      : _t('رفع صورة مخصصة', 'Upload Custom Image'),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// --------------------
// Red Envelope create sheet
// ─────────────────────────────────────────────────────────────────────────────
// Lucky Bag sheet — premium send UI (backed by red_envelopes table)
// ─────────────────────────────────────────────────────────────────────────────

class _LuckyBagSheet extends StatefulWidget {
  const _LuckyBagSheet({required this.roomId, required this.isArabic});
  final String roomId;
  final bool isArabic;

  @override
  State<_LuckyBagSheet> createState() => _LuckyBagSheetState();
}

class _LuckyBagSheetState extends State<_LuckyBagSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  static const _coinPresetsNormal = [777, 999, 2999, 4999];
  static const _coinPresetsSuper = [9999, 19999, 49999, 99999];
  static const _countPresets = [9, 19, 29, 49];
  static const _timerPresets = [15, 30, 60, 120, 300];

  int _selectedCoins = 777;
  int _selectedCount = 9;
  int _selectedTimer = 60;
  bool _loading = false;
  String? _error;

  AudioPlayer? _sfxPlayer;

  bool get _isSuper => _tab.index == 1;
  String _t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _sfxPlayer = AudioPlayer(handleInterruptions: false);
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) return;
      HapticFeedback.selectionClick();
      _playSfx('assets/sounds/lucky_bag_open.mp3');
      setState(() {
        _selectedCoins = _tab.index == 0 ? 777 : 9999;
        _selectedCount = 9;
        _error = null;
      });
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _sfxPlayer?.dispose();
    super.dispose();
  }

  Future<void> _playSfx(String asset) async {
    try {
      await _sfxPlayer?.setAsset(asset);
      await _sfxPlayer?.seek(Duration.zero);
      unawaited(_sfxPlayer?.play());
    } catch (e, st) {
      debugError('_LuckyBagSheetState._playSfx', e, st);
    }
  }

  List<int> get _coinPresets =>
      _isSuper ? _coinPresetsSuper : _coinPresetsNormal;

  Future<void> _send() async {
    HapticFeedback.mediumImpact();
    _playSfx('assets/sounds/lucky_bag_win.wav');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final expiresAt = DateTime.now()
          .toUtc()
          .add(Duration(seconds: _selectedTimer))
          .toIso8601String();
      final result = await Supabase.instance.client.rpc(
        'create_red_envelope',
        params: {
          'p_room_id': widget.roomId,
          'p_total_coins': _selectedCoins,
          'p_count': _selectedCount,
          'p_is_super': _isSuper,
          'p_expires_at': expiresAt,
        },
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      debugPrint(
        '[LuckyBag] send — room=${widget.roomId} '
        'coins=$_selectedCoins count=$_selectedCount super=$_isSuper err=$e',
      );
      final msg = e.toString();
      final String friendly;
      if (msg.contains('insufficient_balance')) {
        friendly = _t('رصيدك غير كافٍ', 'Insufficient balance');
      } else if (msg.contains('not_room_member')) {
        friendly = _t('يجب أن تكون في الغرفة', 'You must be in the room');
      } else if (msg.contains('room_not_found')) {
        friendly = _t('الغرفة غير موجودة', 'Room not found');
      } else {
        friendly = _t('حدث خطأ، حاول مرة أخرى', 'An error occurred, try again');
      }
      setState(() {
        _error = friendly;
        _loading = false;
      });
    }
  }

  void _openRules() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LuckyBagRulesSheet(isArabic: widget.isArabic),
    );
  }

  void _openHistory() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LuckyBagHistorySheet(
        roomId: widget.roomId,
        isArabic: widget.isArabic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    final coinPresets = _coinPresets;
    final avg = (_selectedCoins / _selectedCount).round();
    final isSuper = _isSuper;

    return Directionality(
      textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSuper
                ? [
                    const Color(0xFF3A0A0A),
                    const Color(0xFF220505),
                    const Color(0xFF130318),
                  ]
                : [
                    const Color(0xFF2D0808),
                    const Color(0xFF1C0505),
                    const Color(0xFF120316),
                  ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ─────────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header: title + Rules + History ─────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  Text(
                    _t('حقيبة الحظ', 'Lucky Bag'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  // Rules button
                  _BagHeaderAction(
                    label: _t('القواعد', 'Rules'),
                    icon: Icons.info_outline_rounded,
                    onTap: _openRules,
                  ),
                  const SizedBox(width: 8),
                  // History button
                  _BagHeaderAction(
                    label: _t('السجل', 'History'),
                    icon: Icons.history_rounded,
                    onTap: _openHistory,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Luxury bag illustration ──────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _LuxuryBagWidget(
                  key: ValueKey(isSuper),
                  isSuper: isSuper,
                  size: 96,
                ),
              ),
              const SizedBox(height: 10),

              // ── Subtitle ────────────────────────────────────────────────
              Text(
                isSuper
                    ? _t(
                        'أرسل حقيبة الحظ الكبرى 🔥',
                        'Send a Super Lucky Bag 🔥',
                      )
                    : _t('أرسل حقيبة الحظ', 'Send a Lucky Bag'),
                style: TextStyle(
                  color: isSuper ? const Color(0xFFFFD700) : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _t(
                  'اضغط على حقيبة الحظ لفرصة الفوز بعملات',
                  'Tap the Lucky Bag for a chance to win coins',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),

              // ── Tab selector ─────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tab,
                  indicator: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isSuper
                          ? [const Color(0xFFD4380D), const Color(0xFFFF6B00)]
                          : [const Color(0xFFD4380D), const Color(0xFFE63946)],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE63946).withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  tabs: [
                    Tab(text: _t('حقيبة الحظ', 'Lucky Bag')),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_t('الكبرى', 'Super')),
                          const SizedBox(width: 4),
                          const Text('✨', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Coins presets ─────────────────────────────────────────────
              _BagSectionLabel(
                _t('عدد العملات', 'Coins'),
                const Color(0xFFF0C15A),
              ),
              const SizedBox(height: 10),
              Row(
                children: coinPresets
                    .map(
                      (v) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _BagPresetChip(
                            label: _fmtN(v),
                            selected: _selectedCoins == v,
                            selectedColor: const Color(0xFFF0C15A),
                            selectedBg: const Color(0xFF3D2200),
                            onTap: () => setState(() {
                              _selectedCoins = v;
                              _error = null;
                            }),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),

              // ── Quantity presets ──────────────────────────────────────────
              _BagSectionLabel(
                _t('عدد الحقائب', 'Quantity'),
                const Color(0xFFE63946),
              ),
              const SizedBox(height: 10),
              Row(
                children: _countPresets
                    .map(
                      (v) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _BagPresetChip(
                            label: '$v',
                            selected: _selectedCount == v,
                            selectedColor: Colors.white,
                            selectedBg: const Color(0xFFD4380D),
                            onTap: () => setState(() {
                              _selectedCount = v;
                              _error = null;
                            }),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),

              // ── Timer presets ─────────────────────────────────────────────
              _BagSectionLabel(
                _t('مدة الحقيبة', 'Duration'),
                const Color(0xFF7EC8E3),
              ),
              const SizedBox(height: 10),
              Row(
                children: _timerPresets
                    .map(
                      (secs) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _BagPresetChip(
                            label: _fmtTimer(secs),
                            selected: _selectedTimer == secs,
                            selectedColor: Colors.white,
                            selectedBg: const Color(0xFF1A5276),
                            onTap: () => setState(() {
                              _selectedTimer = secs;
                              _error = null;
                            }),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),

              // ── Summary pill ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF0C15A).withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: Color(0xFFF0C15A),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _t(
                        '$_selectedCoins ÷ $_selectedCount ≈ $avg لكل حقيبة',
                        '$_selectedCoins ÷ $_selectedCount ≈ $avg per bag',
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    if (isSuper) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD4380D), Color(0xFFFF6B00)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'SUPER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // ── Send button ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _loading
                      ? Container(
                          key: const ValueKey('loading'),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isSuper
                                  ? [
                                      const Color(0xFFFF8C00),
                                      const Color(0xFFD4380D),
                                    ]
                                  : [
                                      const Color(0xFFFFD700),
                                      const Color(0xFFC8850A),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : GestureDetector(
                          key: const ValueKey('send'),
                          onTap: _send,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isSuper
                                    ? [
                                        const Color(0xFFFF8C00),
                                        const Color(0xFFD4380D),
                                      ]
                                    : [
                                        const Color(0xFFFFD700),
                                        const Color(0xFFC8850A),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isSuper
                                              ? const Color(0xFFFF6B00)
                                              : const Color(0xFFFFD700))
                                          .withValues(alpha: 0.38),
                                  blurRadius: 18,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.card_giftcard_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isSuper
                                      ? _t('إرسال الكبرى', 'Send Super Bag')
                                      : _t(
                                          'إرسال حقيبة الحظ',
                                          'Send Lucky Bag',
                                        ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _fmtN(_selectedCoins),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.monetization_on_rounded,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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

  String _fmtN(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return k == k.truncateToDouble()
          ? '${k.toInt()}k'
          : '${k.toStringAsFixed(1)}k';
    }
    return '$n';
  }

  String _fmtTimer(int secs) {
    if (secs < 60) return '${secs}s';
    final m = secs ~/ 60;
    return '${m}m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small header action button (Rules / History)
// ─────────────────────────────────────────────────────────────────────────────

class _BagHeaderAction extends StatelessWidget {
  const _BagHeaderAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white60),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Luxury red bag illustration (CustomPaint)
// ─────────────────────────────────────────────────────────────────────────────

class _LuxuryBagWidget extends StatelessWidget {
  const _LuxuryBagWidget({super.key, required this.size, this.isSuper = false});
  final double size;
  final bool isSuper;

  @override
  Widget build(BuildContext context) {
    final totalH = size * 1.26;
    return SizedBox(
      width: size,
      height: totalH,
      child: Stack(
        children: [
          // Outer glow halo
          Positioned(
            left: size * 0.1,
            top: size * 0.28,
            child: Container(
              width: size * 0.8,
              height: size * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        (isSuper
                                ? const Color(0xFFFF6B00)
                                : const Color(0xFFE63946))
                            .withValues(alpha: 0.42),
                    blurRadius: 36,
                    spreadRadius: 8,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.18),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          // The bag itself
          CustomPaint(
            size: Size(size, totalH),
            painter: _LuxuryBagPainter(isSuper: isSuper),
          ),
        ],
      ),
    );
  }
}

class _LuxuryBagPainter extends CustomPainter {
  const _LuxuryBagPainter({required this.isSuper});
  final bool isSuper;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Layout fractions
    final handleH = h * 0.20;
    final bodyTop = handleH * 0.55;
    final bodyH = h - bodyTop;
    final radius = w * 0.16;

    final bodyRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, bodyTop, w, bodyH),
      topLeft: Radius.circular(radius * 0.45),
      topRight: Radius.circular(radius * 0.45),
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );

    // ── Body fill ────────────────────────────────────────────────────────────
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.35),
        radius: 1.15,
        colors: isSuper
            ? [
                const Color(0xFFE84820),
                const Color(0xFFA01008),
                const Color(0xFF5C0004),
              ]
            : [
                const Color(0xFFBF1B0B),
                const Color(0xFF8B0000),
                const Color(0xFF4A0000),
              ],
      ).createShader(Rect.fromLTWH(0, bodyTop, w, bodyH));
    canvas.drawRRect(bodyRect, bodyPaint);

    // ── Body gold border ─────────────────────────────────────────────────────
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // ── Top rim / crease line ────────────────────────────────────────────────
    canvas.drawLine(
      Offset(w * 0.06, bodyTop + 1),
      Offset(w * 0.94, bodyTop + 1),
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.3)
        ..strokeWidth = 0.8,
    );

    // ── Highlight streak (upper-left gloss) ──────────────────────────────────
    final glossPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.07, bodyTop + 5, w * 0.33, bodyH * 0.18),
          const Radius.circular(20),
        ),
      );
    canvas.drawPath(
      glossPath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.28),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromLTWH(w * 0.07, bodyTop + 5, w * 0.33, bodyH * 0.18),
            ),
    );

    // ── Center emblem ────────────────────────────────────────────────────────
    final emblemCenter = Offset(w * 0.5, bodyTop + bodyH * 0.44);
    final emblemR = w * 0.2;
    if (isSuper) {
      _drawDiamond(canvas, emblemCenter, emblemR);
    } else {
      _drawStar(canvas, emblemCenter, emblemR, emblemR * 0.42, 5);
    }

    // ── Dollar sign below emblem ─────────────────────────────────────────────
    final dollarPainter = TextPainter(
      text: TextSpan(
        text: '\$',
        style: TextStyle(
          color: const Color(0xFFFFE066).withValues(alpha: 0.9),
          fontSize: w * 0.22,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: const Color(0xFFD4A500).withValues(alpha: 0.8),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    dollarPainter.paint(
      canvas,
      Offset(w * 0.5 - dollarPainter.width / 2, bodyTop + bodyH * 0.64),
    );

    // ── Gold handles ─────────────────────────────────────────────────────────
    final handlePaint = Paint()
      ..color = const Color(0xFFD4A500)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.058
      ..strokeCap = StrokeCap.round;

    // Left handle
    final leftH = Path()
      ..moveTo(w * 0.265, bodyTop + 1.5)
      ..quadraticBezierTo(w * 0.20, 0, w * 0.5, 0);
    canvas.drawPath(leftH, handlePaint);

    // Right handle
    final rightH = Path()
      ..moveTo(w * 0.735, bodyTop + 1.5)
      ..quadraticBezierTo(w * 0.80, 0, w * 0.5, 0);
    canvas.drawPath(rightH, handlePaint);

    // Handle inner highlight
    final handleHighlight = Paint()
      ..color = const Color(0xFFFFE280).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(leftH, handleHighlight);
    canvas.drawPath(rightH, handleHighlight);

    // ── Knot / tie point ─────────────────────────────────────────────────────
    final knotR = w * 0.062;
    canvas.drawCircle(
      Offset(w * 0.5, 0),
      knotR,
      Paint()
        ..shader =
            RadialGradient(
              colors: [const Color(0xFFFFE066), const Color(0xFFC8850A)],
            ).createShader(
              Rect.fromCircle(center: Offset(w * 0.5, 0), radius: knotR),
            ),
    );
    canvas.drawCircle(
      Offset(w * 0.5, 0),
      knotR,
      Paint()
        ..color = const Color(0xFFA06800).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Body-attach dots
    for (final x in [w * 0.265, w * 0.735]) {
      canvas.drawCircle(
        Offset(x, bodyTop + 1.5),
        w * 0.032,
        Paint()
          ..shader =
              RadialGradient(
                colors: [const Color(0xFFFFE066), const Color(0xFFC8850A)],
              ).createShader(
                Rect.fromCircle(
                  center: Offset(x, bodyTop + 1.5),
                  radius: w * 0.032,
                ),
              ),
      );
    }
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double outerR,
    double innerR,
    int points,
  ) {
    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = (i * math.pi / points) - math.pi / 2;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFFFE880), const Color(0xFFD4A500)],
        ).createShader(Rect.fromCircle(center: center, radius: outerR))
        ..style = PaintingStyle.fill,
    );
    // Star inner glow dot
    canvas.drawCircle(
      center,
      outerR * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _drawDiamond(Canvas canvas, Offset center, double r) {
    final outerPath = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r * 0.68, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - r * 0.68, center.dy)
      ..close();
    canvas.drawPath(
      outerPath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFFFFE880), const Color(0xFFD4A500)],
            ).createShader(
              Rect.fromLTWH(center.dx - r, center.dy - r, r * 2, r * 2),
            ),
    );
    // Inner facet
    final innerPath = Path()
      ..moveTo(center.dx, center.dy - r * 0.5)
      ..lineTo(center.dx + r * 0.38, center.dy)
      ..lineTo(center.dx, center.dy + r * 0.5)
      ..lineTo(center.dx - r * 0.38, center.dy)
      ..close();
    canvas.drawPath(
      innerPath,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_LuxuryBagPainter old) => old.isSuper != isSuper;
}

// ─────────────────────────────────────────────────────────────────────────────
// Rules sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LuckyBagRulesSheet extends StatelessWidget {
  const _LuckyBagRulesSheet({required this.isArabic});
  final bool isArabic;

  String _t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    final rules = isArabic
        ? const [
            ('🎁', 'يمكن لأي شخص في الغرفة فتح الحقيبة بما فيهم المُرسِل'),
            ('🎲', 'توزَّع العملات بشكل عشوائي — كل فتحة تختلف عن الأخرى'),
            ('⏱️', 'تنتهي صلاحية الحقيبة تلقائياً بعد 5 دقائق من الإرسال'),
            ('🔒', 'يمكن لكل شخص فتح حقيبة واحدة فقط في كل مرة'),
            ('✨', 'الحقيبة الكبرى تحمل عملات أكبر وتأثيراً بصرياً مميزاً'),
            ('💡', 'يظهر رصيدك فوراً بعد الفتح'),
          ]
        : const [
            (
              '🎁',
              'Anyone in the room — including the sender — can open a bag',
            ),
            (
              '🎲',
              'Coins are distributed randomly; each claim gets a different amount',
            ),
            ('⏱️', 'Bags expire automatically 5 minutes after being sent'),
            ('🔒', 'Each person can only claim once per bag'),
            (
              '✨',
              'Super Lucky Bags carry larger coin amounts and premium effects',
            ),
            ('💡', 'Your balance updates instantly the moment you claim'),
          ];

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A0A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFF0C15A),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _t('قواعد حقيبة الحظ', 'Lucky Bag Rules'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...rules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Directionality(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LuckyBagHistorySheet extends StatefulWidget {
  const _LuckyBagHistorySheet({required this.roomId, required this.isArabic});
  final String roomId;
  final bool isArabic;

  @override
  State<_LuckyBagHistorySheet> createState() => _LuckyBagHistorySheetState();
}

class _LuckyBagHistorySheetState extends State<_LuckyBagHistorySheet> {
  List<_ClaimRow> _claims = [];
  bool _loading = true;
  String? _error;

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;

      // Fetch recent envelopes for this room
      final envelopesRaw = await client
          .from('red_envelopes')
          .select(
            'id, total_coins, envelope_count, claimed_count, is_super, sender_id, created_at',
          )
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: false)
          .limit(10);

      final envelopes = List<Map<String, dynamic>>.from(envelopesRaw as List);
      if (envelopes.isEmpty) {
        if (mounted) {
          setState(() {
            _claims = [];
            _loading = false;
          });
        }
        return;
      }

      final envIds = envelopes.map((e) => e['id'] as String).toList();

      // Fetch claims for those envelopes with claimer profiles
      final claimsRaw = await client
          .from('red_envelope_claims')
          .select(
            'envelope_id, claimer_id, coins_received, claimed_at, profiles!claimer_id(display_name, avatar_url)',
          )
          .inFilter('envelope_id', envIds)
          .order('claimed_at', ascending: false)
          .limit(50);

      final claimsData = List<Map<String, dynamic>>.from(claimsRaw as List);

      // Map envelope_id → envelope info
      final envMap = {for (final e in envelopes) e['id'] as String: e};

      final rows = claimsData.map((c) {
        final env =
            envMap[c['envelope_id'] as String?] ?? const <String, dynamic>{};
        final profile = c['profiles'] as Map<String, dynamic>? ?? {};
        return _ClaimRow(
          claimerName: (profile['display_name'] as String?) ?? '—',
          avatarUrl: profile['avatar_url'] as String?,
          coinsReceived: (c['coins_received'] as num?)?.toInt() ?? 0,
          claimedAt:
              DateTime.tryParse(c['claimed_at'] as String? ?? '') ??
              DateTime.now(),
          isSuper: env['is_super'] == true,
          bagTotal: (env['total_coins'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _claims = rows;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[LuckyBag] history load error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF160830),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      color: Color(0xFFF0C15A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _t('سجل الفتح', 'Claim History'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _load,
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Body
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFD700),
                      strokeWidth: 2,
                    ),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      _t('حدث خطأ', 'Error loading history'),
                      style: const TextStyle(color: Colors.white38),
                    ),
                  )
                : _claims.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inbox_rounded,
                          size: 42,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _t('لا توجد فتحات بعد', 'No claims yet'),
                          style: const TextStyle(color: Colors.white38),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
                    itemCount: _claims.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) {
                      final row = _claims[i];
                      return _HistoryTile(row: row, isArabic: widget.isArabic);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ClaimRow {
  const _ClaimRow({
    required this.claimerName,
    required this.coinsReceived,
    required this.claimedAt,
    required this.isSuper,
    required this.bagTotal,
    this.avatarUrl,
  });
  final String claimerName;
  final String? avatarUrl;
  final int coinsReceived;
  final DateTime claimedAt;
  final bool isSuper;
  final int bagTotal;
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row, required this.isArabic});
  final _ClaimRow row;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final local = row.claimedAt.toLocal();
    final timeStr =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF2A1050),
            backgroundImage: row.avatarUrl != null
                ? NetworkImage(row.avatarUrl!)
                : null,
            child: row.avatarUrl == null
                ? Text(
                    row.claimerName.isNotEmpty
                        ? row.claimerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Color(0xFFF0C15A),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Name + time
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  row.claimerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: 11,
                      ),
                    ),
                    if (row.isSuper) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD4380D), Color(0xFFFF6B00)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'SUPER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Coins badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3D2200), Color(0xFF2A1500)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  size: 13,
                  color: Color(0xFFF0C15A),
                ),
                const SizedBox(width: 4),
                Text(
                  '+${row.coinsReceived}',
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
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

// ─────────────────────────────────────────────────────────────────────────────

class _BagSectionLabel extends StatelessWidget {
  const _BagSectionLabel(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _BagPresetChip extends StatelessWidget {
  const _BagPresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.selectedBg,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color selectedBg;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 44,
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? selectedColor.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.1),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? selectedColor : Colors.white54,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------
// Game Center sheet
// --------------------

class _GameCenterSheet extends StatelessWidget {
  const _GameCenterSheet({required this.isArabic, required this.roomId});

  final bool isArabic;
  final String roomId;

  String get _title => isArabic ? 'مركز الألعاب' : 'Game Center';

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final games = [
      _GameEntry(
        icon: Icons.casino_rounded,
        labelAr: 'عجلة الحظ',
        labelEn: 'Spin Wheel',
        accent: const Color(0xFFF0C15A),
        screen: SpinWheelScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.rocket_launch_rounded,
        labelAr: 'صاروخ سرود',
        labelEn: 'Srood Rocket',
        accent: const Color(0xFF28C7FA),
        screen: CrashRocketV2Screen(isArabic: isArabic, roomId: roomId),
      ),
      _GameEntry(
        icon: Icons.pets_rounded,
        labelAr: 'القط الجائع',
        labelEn: 'Hungry Cat',
        accent: const Color(0xFF4ADE80),
        screen: HungryCatWebviewScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.sports_soccer_rounded,
        labelAr: 'ماجيك سرود',
        labelEn: 'Magic Srood',
        accent: const Color(0xFFFFCC00),
        screen: MagicSroodScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.stairs_rounded,
        labelAr: 'السلم الذهبي',
        labelEn: 'Gold Ladder',
        accent: const Color(0xFFFFD978),
        screen: GoldLadderQuizScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.grain_rounded,
        labelAr: 'سحب سرود',
        labelEn: 'Srood Draw',
        accent: const Color(0xFFF0C15A),
        screen: SroodLotoScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.inventory_2_rounded,
        labelAr: 'كنز سرود',
        labelEn: 'Srood Treasure',
        accent: const Color(0xFFF0C15A),
        screen: SroodTreasureScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.emoji_events_rounded,
        labelAr: 'تحدي الكاريزما',
        labelEn: 'Charisma Challenge',
        accent: const Color(0xFFFFD700),
        screen: CharismaChallengeScreen(isArabic: isArabic),
      ),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F1040), Color(0xFF0D0820)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          ...games.map(
            (g) => _GameRow(
              game: g,
              isArabic: isArabic,
              onTap: () {
                // Capture root navigator BEFORE popping this sheet.
                // After pop(), this widget's context is defunct; any
                // Navigator.of(context) call on it crashes with
                // "widget has been unmounted".
                final rootNav = Navigator.of(context, rootNavigator: true);
                Navigator.of(context).pop(); // close game-center sheet
                rootNav.push(MaterialPageRoute<void>(builder: (_) => g.screen));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GameEntry {
  const _GameEntry({
    required this.icon,
    required this.labelAr,
    required this.labelEn,
    required this.accent,
    required this.screen,
  });

  final IconData icon;
  final String labelAr;
  final String labelEn;
  final Color accent;
  final Widget screen;
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.game,
    required this.isArabic,
    required this.onTap,
  });

  final _GameEntry game;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: game.accent.withValues(alpha: 0.08),
              border: Border.all(color: game.accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: game.accent.withValues(alpha: 0.15),
                    border: Border.all(
                      color: game.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(game.icon, color: game.accent, size: 20),
                ),
                const SizedBox(width: 14),
                Text(
                  isArabic ? game.labelAr : game.labelEn,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(
                  isArabic
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: game.accent,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
