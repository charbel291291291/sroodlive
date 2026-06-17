import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../games/screens/crash_game_screen.dart';
import '../../games/screens/gold_ladder_quiz_screen.dart';
import '../../games/screens/hungry_cat_webview_screen.dart';
import '../../games/screens/spin_wheel_screen.dart';
import '../../games/screens/srood_loto_screen.dart';
import '../../games/screens/srood_treasure_screen.dart';
import '../../charisma/screens/charisma_challenge_screen.dart';
import '../services/room_management_service.dart';
import '../models/room_ban.dart';
import '../models/room_member.dart';
import 'pk_start_sheet.dart';
import 'room_settings_sheet.dart';
import '../models/room.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// RoomToolsSheet â€” premium tools bottom sheet for live rooms.
//
// Overflow fix: SafeArea is NOT used as a wrapper. Instead we read
// MediaQuery.viewPadding.bottom (device navigation bar inset) and add it
// explicitly to the scroll content bottom padding. This avoids the 1.1 px
// overflow that happens when SafeArea pads the sheet before the Column
// computes its height.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
  final int moderatorCount;
  final bool isLocked;
  final Future<void> Function() onToggleLock;
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
  final _mgmt = const RoomManagementService();
  bool _soundOn = true;
  bool _visualOn = true;
  bool _lockBusy = false;

  static const _kSoundKey = 'room_pref_sound';
  static const _kVisualKey = 'room_pref_visual';

  bool get _canManage => widget.isOwner || widget.isHost;

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

  // â”€â”€ Permission check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _requirePermission(VoidCallback onGranted) {
    if (_canManage) {
      onGranted();
    } else {
      _snack(
        _t('Ù„ÙŠØ³ Ù„Ø¯ÙŠÙƒ ØµÙ„Ø§Ø­ÙŠØ© Ù„Ø§Ø³ØªØ®Ø¯Ø§Ù… Ù‡Ø°Ù‡ Ø§Ù„Ø£Ø¯Ø§Ø©',
            'You do not have permission to use this tool.'),
        isError: true,
      );
    }
  }

  // â”€â”€ Snack helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor:
            isError ? const Color(0xFF2A0F1A) : const Color(0xFF1A0D2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isError
                ? const Color(0xFFE63946).withValues(alpha: 0.5)
                : const Color(0xFF8B26D9).withValues(alpha: 0.4),
          ),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ));
  }

  // â”€â”€ Coming Soon mini-sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showComingSoon(String featureAr, String featureEn) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComingSoonSheet(
        featureName: context.isArabic ? featureAr : featureEn,
        isArabic: context.isArabic,
      ),
    );
  }

  // â”€â”€ Navigation helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _openSettings() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomSettingsSheet(
        room: widget.room,
        isArabic: context.isArabic,
        isOwner: widget.isOwner,
        moderatorCount: widget.moderatorCount,
        isLocked: widget.isLocked,
        onToggleLock: widget.onToggleLock,
      ),
    );
  }

  void _openGameCenter() {
    HapticFeedback.lightImpact();
    // Capture isArabic before popping â€” context will be defunct afterwards.
    final isArabic = context.isArabic;
    Navigator.of(context).pop(); // close tools sheet
    // useRootNavigator: true so the sheet is anchored to the root navigator,
    // not to the (now-popped) tools sheet context.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => _GameCenterSheet(isArabic: isArabic),
    );
  }

  void _openKickRecord() async {
    HapticFeedback.lightImpact();
    final bans = await _mgmt.getBans(widget.room.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _KickRecordSheet(bans: bans, isArabic: context.isArabic),
    );
  }

  Future<void> _openRedEnvelope() async {
    HapticFeedback.lightImpact();

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LuckyBagSheet(
        roomId: widget.room.id,
        isArabic: context.isArabic,
      ),
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

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic ? 'تم إرسال حقيبة الحظ' : 'Lucky Bag sent!',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFFD4380D),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
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
          _t('Ù…Ø³Ø­ Ø§Ù„Ø¯Ø±Ø¯Ø´Ø©', 'Clear Chat'),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          _t('Ù‡Ù„ Ø£Ù†Øª Ù…ØªØ£ÙƒØ¯ Ø£Ù†Ùƒ ØªØ±ÙŠØ¯ Ù…Ø³Ø­ Ø¬Ù…ÙŠØ¹ Ø±Ø³Ø§Ø¦Ù„ Ø§Ù„Ø¯Ø±Ø¯Ø´Ø©ØŸ',
              'Are you sure you want to clear all chat messages?'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t('Ø¥Ù„ØºØ§Ø¡', 'Cancel'),
                style: const TextStyle(color: Color(0xFF9E91B8))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B26D9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(true);
              Navigator.of(context).pop(); // close tools sheet
              widget.onClearChat();
            },
            child: Text(_t('Ù…Ø³Ø­', 'Clear')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.isArabic
              ? 'Ù„Ø§ ÙŠÙˆØ¬Ø¯ Ø£Ø­Ø¯ Ø¹Ù„Ù‰ Ø§Ù„Ù…Ø§ÙŠÙƒ'
              : 'No one is on mic'),
          backgroundColor: const Color(0xFF231440),
        ),
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

  Future<void> _handleToggleLock() async {
    HapticFeedback.mediumImpact();
    setState(() => _lockBusy = true);
    Navigator.of(context).pop();
    try {
      await widget.onToggleLock();
    } finally {
      // sheet is already dismissed
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
            // Scrollable content â€” bottom padding includes nav-bar inset
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 20 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section A â€“ Interactive
                    _SectionLabel(_t('Ù…ÙŠØ²Ø§Øª ØªÙØ§Ø¹Ù„ÙŠØ©', 'Interactive')),
                    const SizedBox(height: 10),
                    _ToolGrid(
                      isArabic: isArabic,
                      items: [
                        _ToolDef(
                          icon: Icons.groups_2_rounded,
                          labelAr: 'Ø¨ÙŠ ÙƒÙŠ',
                          labelEn: 'Team PK',
                          onTap: _canManage
                              ? _openTeamPk
                              : () => _requirePermission(() {}),
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
                          labelAr: 'Ø£Ù„Ø¹Ø§Ø¨',
                          labelEn: 'Game',
                          accent: const Color(0xFFF0C15A),
                          onTap: _openGameCenter,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section B â€“ Management
                    _SectionLabel(_t('Ø£Ø¯ÙˆØ§Øª Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©', 'Management')),
                    const SizedBox(height: 10),
                    _ToolGrid(
                      isArabic: isArabic,
                      items: [
                        _ToolDef(
                          icon: Icons.cleaning_services_rounded,
                          labelAr: 'Ù…Ø³Ø­',
                          labelEn: 'Clean',
                          onTap: _canManage
                              ? _confirmClearChat
                              : () => _requirePermission(() {}),
                          disabled: !_canManage,
                        ),
                        _ToolDef(
                          icon: Icons.settings_rounded,
                          labelAr: 'Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª',
                          labelEn: 'Settings',
                          onTap: _canManage
                              ? _openSettings
                              : () => _requirePermission(() {}),
                          disabled: !_canManage,
                        ),
                        _ToolDef(
                          icon: Icons.music_note_rounded,
                          labelAr: 'Ù…ÙˆØ³ÙŠÙ‚Ù‰',
                          labelEn: 'Music',
                          accent: const Color(0xFFC875FF),
                          onTap: _openMusic,
                        ),
                        _ToolDef(
                          icon: Icons.graphic_eq_rounded,
                          labelAr: 'ØµÙˆØª',
                          labelEn: 'Voice',
                          onTap: () =>
                              _showComingSoon('Ù…Ø¤Ø«Ø± ØµÙˆØªÙŠ', 'Voice Effect'),
                        ),
                        _ToolDef(
                          icon: widget.isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          labelAr:
                              widget.isLocked ? 'ÙØªØ­' : 'Ù‚ÙÙ„',
                          labelEn: widget.isLocked ? 'Unlock' : 'Lock',
                          accent: widget.isLocked
                              ? const Color(0xFFE63946)
                              : null,
                          isToggled: widget.isLocked,
                          busy: _lockBusy,
                          onTap: _canManage
                              ? _handleToggleLock
                              : () => _requirePermission(() {}),
                          disabled: !_canManage,
                        ),
                        _ToolDef(
                          icon: Icons.mic_rounded,
                          labelAr: 'Ù…ÙŠÙƒØ±ÙˆÙÙˆÙ†',
                          labelEn: 'Mic Mode',
                          onTap: _canManage
                              ? _openMicMode
                              : () => _requirePermission(() {}),
                          disabled: !_canManage,
                        ),
                        _ToolDef(
                          icon: Icons.wallpaper_rounded,
                          labelAr: 'Ø§Ù„Ø®Ù„ÙÙŠØ©',
                          labelEn: 'Background',
                          onTap: _openBackground,
                        ),
                        _ToolDef(
                          icon: Icons.person_off_rounded,
                          labelAr: 'Ø³Ø¬Ù„ Ø§Ù„Ø·Ø±Ø¯',
                          labelEn: 'Kicks',
                          accent: const Color(0xFFE63946),
                          onTap: _canManage
                              ? _openKickRecord
                              : () => _requirePermission(() {}),
                          disabled: !_canManage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section C â€“ Other
                    _SectionLabel(_t('Ø£Ø¯ÙˆØ§Øª Ø£Ø®Ø±Ù‰', 'Other')),
                    const SizedBox(height: 10),
                    _ToolGrid(
                      isArabic: isArabic,
                      items: [
                        _ToolDef(
                          icon: _soundOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          labelAr: _soundOn ? 'Ø§Ù„ØµÙˆØª' : 'ÙƒØªÙ…',
                          labelEn: _soundOn ? 'Sound' : 'Muted',
                          accent: _soundOn
                              ? const Color(0xFF1A8CB0)
                              : null,
                          isToggled: _soundOn,
                          onTap: _toggleSound,
                        ),
                        _ToolDef(
                          icon: _visualOn
                              ? Icons.auto_awesome_rounded
                              : Icons.auto_awesome_outlined,
                          labelAr: _visualOn ? 'Ù…Ø¤Ø«Ø±Ø§Øª' : 'Ø¨Ø¯ÙˆÙ† Ù…Ø¤Ø«Ø±Ø§Øª',
                          labelEn: _visualOn ? 'Visual' : 'Visual Off',
                          accent: _visualOn
                              ? const Color(0xFF8B26D9)
                              : null,
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tool definition data class
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ToolDef {
  const _ToolDef({
    required this.icon,
    required this.labelAr,
    required this.labelEn,
    this.onTap,
    this.accent,
    this.isToggled = false,
    this.disabled = false,
    this.busy = false,
  });

  final IconData icon;
  final String labelAr;
  final String labelEn;
  final VoidCallback? onTap;
  final Color? accent;
  final bool isToggled;
  final bool disabled;
  final bool busy;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tool grid â€” uses Wrap instead of GridView to avoid aspect-ratio overflow.
// Each tile has a fixed 56Ã—56 icon box and a 1-line label below it.
// Total tile height â‰ˆ 56 + 5 + 15 = 76 px, so 5 columns at ~64 px wide each
// never overflows the grid cell.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ToolGrid extends StatelessWidget {
  const _ToolGrid({required this.items, required this.isArabic});

  final List<_ToolDef> items;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // 5 columns with 8 px gaps â†’ each tile width
      const cols = 5;
      const gap = 8.0;
      final tileW = (constraints.maxWidth - gap * (cols - 1)) / cols;

      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: items
            .map((item) => SizedBox(
                  width: tileW,
                  child: _ToolTile(
                    def: item,
                    label: isArabic ? item.labelAr : item.labelEn,
                  ),
                ))
            .toList(),
      );
    });
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Individual tool tile â€” premium nav-footer style
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeInOut),
    );
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
      onTap: def.busy ? null : def.onTap,
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
                child: def.busy
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        ),
                      )
                    : Icon(
                        def.icon,
                        size: 22,
                        color: isActive ? accent : const Color(0xFFCBC4E0),
                      ),
              ),
              const SizedBox(height: 5),
              // Label â€” always 1 line, ellipsis
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Helper sub-widgets
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Coming Soon sheet
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Shown when a PK is already active and host opens the tool again.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PkActiveOptionsSheet extends StatelessWidget {
  const _PkActiveOptionsSheet({
    required this.isArabic,
    required this.onCancel,
  });
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
            t ? 'Ù…Ù†Ø§ÙØ³Ø© Ù†Ø´Ø·Ø©' : 'PK is Live',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t ? 'Ø§Ù„Ù…Ù†Ø§ÙØ³Ø© Ø¬Ø§Ø±ÙŠØ© Ø§Ù„Ø¢Ù†' : 'A battle is currently in progress.',
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
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: onCancel,
              child: Text(
                t ? 'Ø¥Ù„ØºØ§Ø¡ Ø§Ù„Ù…Ù†Ø§ÙØ³Ø©' : 'Cancel PK',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              t ? 'Ø±Ø¬ÙˆØ¹' : 'Go Back',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Mic Mode Sheet â€” picks 6 / 9 / 12 mic seats and updates rooms.max_seats
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    (seats: 6,  ar: 'Ù¦ Ù…Ù‚Ø§Ø¹Ø¯',  en: '6 Seats',  descAr: 'Ù…Ù†Ø§Ø³Ø¨ Ù„Ù„ØºØ±Ù Ø§Ù„ØµØºÙŠØ±Ø©',       descEn: 'Best for small rooms'),
    (seats: 9,  ar: 'Ù© Ù…Ù‚Ø§Ø¹Ø¯',  en: '9 Seats',  descAr: 'ØªÙˆØ§Ø²Ù† Ù…Ø«Ø§Ù„ÙŠ',                descEn: 'Balanced experience'),
    (seats: 12, ar: 'Ù¡Ù¢ Ù…Ù‚Ø¹Ø¯', en: '12 Seats', descAr: 'Ù„Ù„ØºØ±Ù Ø§Ù„ÙƒØ¨ÙŠØ±Ø© ÙˆØ§Ù„Ø­ÙÙ„Ø§Øª',    descEn: 'Large rooms & events'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t('ÙØ´Ù„ ØªØ­Ø¯ÙŠØ« Ø§Ù„Ù…Ù‚Ø§Ø¹Ø¯', 'Failed to update seats')),
          backgroundColor: const Color(0xFF2A0F1A),
        ));
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
            _t('Ø¹Ø¯Ø¯ Ù…Ù‚Ø§Ø¹Ø¯ Ø§Ù„Ù…ÙŠÙƒØ±ÙˆÙÙˆÙ†', 'Mic Seats'),
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _t('ÙŠØ¤Ø«Ø± Ø¹Ù„Ù‰ Ø¬Ù…ÙŠØ¹ Ø§Ù„Ù…Ø´Ø§Ø±ÙƒÙŠÙ† ÙÙŠ Ø§Ù„ØºØ±ÙØ©',
                'Affects all participants in the room'),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFFC875FF), size: 20),
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Background Sheet â€” gradient presets (local) + custom image upload (global)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    (ar: 'Ù„ÙŠÙ„ÙŠ ÙƒÙ„Ø§Ø³ÙŠÙƒÙŠ', en: 'Classic Night', colors: [Color(0xFF231440), Color(0xFF160C2F), Color(0xFF0C0619)]),
    (ar: 'Ø´ÙÙ‚ Ø£Ø±Ø¬ÙˆØ§Ù†ÙŠ', en: 'Purple Dusk',   colors: [Color(0xFF2D1B69), Color(0xFF11998e), Color(0xFF1A0D33)]),
    (ar: 'Ù†Ø§Ø± Ø°Ù‡Ø¨ÙŠØ©',   en: 'Golden Flame',  colors: [Color(0xFF3D1C02), Color(0xFF7B3F00), Color(0xFF1A0900)]),
    (ar: 'Ø³Ù…Ø§Ø¡ Ø²Ø±Ù‚Ø§Ø¡', en: 'Deep Ocean',     colors: [Color(0xFF0A1628), Color(0xFF1A3A5C), Color(0xFF0D1F35)]),
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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _t('ÙØ´Ù„ Ø±ÙØ¹ Ø§Ù„ØµÙˆØ±Ø©', 'Failed to upload image')),
          backgroundColor: const Color(0xFF2A0F1A),
        ));
      }
    }
  }

  Future<void> _removeBackground() async {
    setState(() => _uploading = true);
    try {
      await _mgmt.updateRoom(widget.roomId, clearBackground: true);
      widget.onBackgroundChanged?.call(null);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final hasCustomBg = widget.currentBackgroundUrl != null;
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
            _t('Ø®Ù„ÙÙŠØ© Ø§Ù„ØºØ±ÙØ©', 'Room Background'),
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _t('Ø§Ù„Ø®Ù„ÙÙŠØ© Ø§Ù„Ù…Ø®ØµØµØ© ØªØ¸Ù‡Ø± Ù„Ø¬Ù…ÙŠØ¹ Ø§Ù„Ù…Ø´Ø§Ø±ÙƒÙŠÙ†',
                'Custom image is visible to all participants'),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
          ),
          const SizedBox(height: 20),
          // â”€â”€ Gradient presets â”€â”€
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _t('Ø£Ù„ÙˆØ§Ù†', 'COLORS').toUpperCase(),
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
                            child: const Icon(Icons.check,
                                size: 12, color: Colors.black),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          // â”€â”€ Custom image upload â”€â”€
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _t('ØµÙˆØ±Ø© Ù…Ø®ØµØµØ©', 'CUSTOM IMAGE').toUpperCase(),
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
                      child: const Icon(Icons.broken_image_rounded,
                          color: Colors.white38),
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
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _t('ØµÙˆØ±Ø© Ù…Ø®ØµØµØ© Ù†Ø´Ø·Ø©', 'Custom image active'),
                        style: const TextStyle(
                            color: Color(0xFFF0C15A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
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
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _uploading ? null : _uploadImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFC875FF)),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded, size: 20),
              label: Text(_uploading
                  ? _t('Ø¬Ø§Ø±ÙŠ Ø§Ù„Ø±ÙØ¹...', 'Uploading...')
                  : _t('Ø±ÙØ¹ ØµÙˆØ±Ø© Ù…Ø®ØµØµØ©', 'Upload Custom Image')),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
  static const _coinPresetsSuper  = [9999, 19999, 49999, 99999];
  static const _countPresets      = [9, 19, 29, 49];

  int _selectedCoins = 777;
  int _selectedCount = 9;
  bool _loading = false;
  String? _error;

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) return;
      setState(() {
        _selectedCoins = _tab.index == 0 ? 777 : 9999;
        _error = null;
      });
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<int> get _coinPresets =>
      _tab.index == 0 ? _coinPresetsNormal : _coinPresetsSuper;

  Future<void> _send() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await Supabase.instance.client
          .rpc('create_red_envelope', params: {
        'p_room_id': widget.roomId,
        'p_total_coins': _selectedCoins,
        'p_count': _selectedCount,
      });
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[LuckyBag] send — room=${widget.roomId} '
          'coins=$_selectedCoins count=$_selectedCount err=$e');
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
      setState(() { _error = friendly; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    final coinPresets = _coinPresets;
    final avg = (_selectedCoins / _selectedCount).round();

    return Directionality(
      textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2D0808), Color(0xFF1C0505), Color(0xFF120316)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 44, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Hero bag icon
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFFE066), Color(0xFFC8850A)],
                    radius: 0.75,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🎁', style: TextStyle(fontSize: 38)),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                _t('أرسل حقيبة الحظ', 'Send a Lucky Bag'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  'اضغط على حقيبة الحظ لفرصة الفوز بعملات',
                  'Tap the Lucky Bag for a chance to win Coins',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),

              // Tab selector
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tab,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD4380D), Color(0xFFE63946)],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: [
                    Tab(text: _t('حقيبة الحظ', 'Lucky Bag')),
                    Tab(text: _t('الكبرى', 'Super')),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Coins presets
              _BagSectionLabel(
                _t('عدد العملات', 'Coins'),
                const Color(0xFFF0C15A),
              ),
              const SizedBox(height: 10),
              Row(
                children: coinPresets.map((v) => Expanded(
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
                )).toList(),
              ),
              const SizedBox(height: 18),

              // Quantity presets
              _BagSectionLabel(
                _t('عدد الحقائب', 'Quantity'),
                const Color(0xFFE63946),
              ),
              const SizedBox(height: 10),
              Row(
                children: _countPresets.map((v) => Expanded(
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
                )).toList(),
              ),
              const SizedBox(height: 12),

              // Summary pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        const Color(0xFFF0C15A).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: Color(0xFFF0C15A),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _t(
                        '$_selectedCoins ÷ $_selectedCount ≈ $avg لكل حقيبة',
                        '$_selectedCoins ÷ $_selectedCount ≈ $avg per bag',
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFFFF6B6B), fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),

              // Gold send button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: _loading
                    ? Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFC8850A)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _send,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFFD700),
                                Color(0xFFC8850A)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🎁',
                                  style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Text(
                                _t(
                                    'إرسال حقيبة الحظ', 'Send Lucky Bag'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$_selectedCoins 🪙',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
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
          color: selected
              ? selectedBg
              : Colors.white.withValues(alpha: 0.07),
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


class _ComingSoonSheet extends StatelessWidget {
  const _ComingSoonSheet(
      {required this.featureName, required this.isArabic});

  final String featureName;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF1A0D33),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF8B26D9).withValues(alpha: 0.15),
              border: Border.all(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.rocket_launch_rounded,
                color: Color(0xFFC875FF), size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            featureName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isArabic
                ? 'Ù‡Ø°Ù‡ Ø§Ù„Ù…ÙŠØ²Ø© Ù‚ÙŠØ¯ Ø§Ù„ØªØ·ÙˆÙŠØ± ÙˆØ³ØªÙƒÙˆÙ† Ù…ØªØ§Ø­Ø© Ù‚Ø±ÙŠØ¨Ø§Ù‹.'
                : 'This feature is under development and will be available soon.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.60),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B26D9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(isArabic ? 'Ø­Ø³Ù†Ø§Ù‹' : 'Got it'),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Game Center sheet
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GameCenterSheet extends StatelessWidget {
  const _GameCenterSheet({required this.isArabic});

  final bool isArabic;

  String get _title => isArabic ? 'Ù…Ø±ÙƒØ² Ø§Ù„Ø£Ù„Ø¹Ø§Ø¨' : 'Game Center';

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final games = [
      _GameEntry(
        icon: Icons.rocket_launch_rounded,
        labelAr: 'ØµØ§Ø±ÙˆØ®',
        labelEn: 'Rocket Crash',
        accent: const Color(0xFFE63946),
        screen: CrashGameScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.casino_rounded,
        labelAr: 'Ø¹Ø¬Ù„Ø© Ø§Ù„Ø­Ø¸',
        labelEn: 'Spin Wheel',
        accent: const Color(0xFFF0C15A),
        screen: SpinWheelScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.pets_rounded,
        labelAr: 'Ø§Ù„Ù‚Ø· Ø§Ù„Ø¬Ø§Ø¦Ø¹',
        labelEn: 'Hungry Cat',
        accent: const Color(0xFF4ADE80),
        screen: HungryCatWebviewScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.stairs_rounded,
        labelAr: 'Ø§Ù„Ø³Ù„Ù… Ø§Ù„Ø°Ù‡Ø¨ÙŠ',
        labelEn: 'Gold Ladder',
        accent: const Color(0xFFFFD978),
        screen: GoldLadderQuizScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.grain_rounded,
        labelAr: 'Ø³Ø­Ø¨ Ø³Ø±ÙˆØ¯',
        labelEn: 'Srood Draw',
        accent: const Color(0xFFF0C15A),
        screen: SroodLotoScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.inventory_2_rounded,
        labelAr: 'ÙƒÙ†Ø² Ø³Ø±ÙˆØ¯',
        labelEn: 'Srood Treasure',
        accent: const Color(0xFFF0C15A),
        screen: SroodTreasureScreen(isArabic: isArabic),
      ),
      _GameEntry(
        icon: Icons.emoji_events_rounded,
        labelAr: 'ØªØ­Ø¯ÙŠ Ø§Ù„ÙƒØ§Ø±ÙŠØ²Ù…Ø§',
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
          ...games.map((g) => _GameRow(
                game: g,
                isArabic: isArabic,
                onTap: () {
                  // Capture root navigator BEFORE popping this sheet.
                  // After pop(), this widget's context is defunct; any
                  // Navigator.of(context) call on it crashes with
                  // "widget has been unmounted".
                  final rootNav = Navigator.of(context, rootNavigator: true);
                  Navigator.of(context).pop(); // close game-center sheet
                  rootNav.push(
                    MaterialPageRoute<void>(builder: (_) => g.screen),
                  );
                },
              )),
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
  const _GameRow(
      {required this.game, required this.isArabic, required this.onTap});

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
              border: Border.all(
                  color: game.accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              textDirection:
                  isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: game.accent.withValues(alpha: 0.15),
                    border: Border.all(
                        color: game.accent.withValues(alpha: 0.4)),
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Kick Record sub-sheet
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _KickRecordSheet extends StatelessWidget {
  const _KickRecordSheet({required this.bans, required this.isArabic});

  final List<RoomBan> bans;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    return Directionality(
      textDirection: textDir,
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
                width: 36,
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
                isArabic ? 'Ø³Ø¬Ù„ Ø§Ù„Ø·Ø±Ø¯' : 'Kick Record',
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
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          isArabic ? 'Ù„Ø§ ÙŠÙˆØ¬Ø¯ Ù…Ø·Ø±ÙˆØ¯ÙˆÙ†' : 'No bans yet',
                          style: const TextStyle(
                              color: Color(0xFF9E91B8), fontSize: 14),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
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
    );
  }
}





