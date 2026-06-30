import 'dart:async';
import 'package:srood_live/shared/utils/error_utils.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/discovery/screens/discovery_screen.dart';
import '../../../features/gamification/screens/vip_center_screen.dart';
import '../../../features/gifts/screens/gift_catalog_screen.dart';
import '../../../features/notifications/screens/notifications_screen.dart';
import '../../../features/search/screens/search_screen.dart';
import '../../../features/social/screens/leaderboard_screen.dart';
import '../../../features/profile/widgets/country_picker_sheet.dart';
import '../models/room.dart';
import '../services/rooms_service.dart';
import '../widgets/vault_pin_sheet.dart';
import 'room_details_screen.dart';
import 'room_schedule_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final RoomsService _roomsService = const RoomsService();

  List<Room> _rooms = [];
  Map<String, int> _activeCounts = {};
  bool _loading = true;
  bool _openingMyRoom = false;
  String? _error;
  String? _selectedCountryCode;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Close stale empty rooms before fetching the list.
      unawaited(_roomsService.closeEmptyRooms());

      // Pass the selected country code so Supabase filters server-side.
      // null = all countries.
      final rooms = await _roomsService.getRooms(
        countryCode: _selectedCountryCode,
      );

      // Active counts are optional — a failure here must not hide the room list.
      Map<String, int> activeCounts = {};
      try {
        activeCounts = await _roomsService.getActiveMemberCounts(
          rooms.map((r) => r.id).toList(),
        );
      } catch (e, st) {
        debugError('RoomsScreen._loadRooms activeCounts', e, st);
      }

      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _activeCounts = activeCounts;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openMyRoom() async {
    if (_openingMyRoom) return;
    setState(() {
      _openingMyRoom = true;
      _error = null;
    });

    try {
      var room = await _roomsService.getOrCreateMyRoom();

      if (!mounted) return;

      if (room.id.isEmpty) {
        throw StateError('Could not load your room — please try again.');
      }

      // If the personal room was closed by the owner, reopen it.
      if (room.isClosed) {
        room = await _roomsService.reopenMyRoom();
        if (!mounted) return;
      }

      // Join as a member (adds owner to room_members so seat logic works).
      await _roomsService.joinRoom(room.id);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RoomDetailsScreen(room: room, isArabic: context.isArabic),
        ),
      );

      await _loadRooms();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _openingMyRoom = false);
    }
  }

  // Server already filtered by country_code. This guard is a safety net for
  // any rooms that slipped through (e.g. legacy rows with no country_code that
  // Supabase returned before the migration ran).
  List<Room> get _filteredRooms {
    final code = _selectedCountryCode;
    if (code == null) return _rooms;
    return _rooms.where((r) {
      final rc = r.countryCode;
      if (rc == null || rc.isEmpty) return false; // hide unknown when filtered
      return rc == code;
    }).toList();
  }

  Future<void> _pickCountry() async {
    final current = countryFromStored(_selectedCountryCode);
    final picked = await showCountryPicker(
      context,
      selected: current,
      isArabic: context.isArabic,
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _selectedCountryCode = picked.code);
      // Reload with the new server-side filter immediately.
      unawaited(_loadRooms());
    }
  }

  Future<void> _openVipCenter() async {
    // Fetch the current user's VIP fields from their profile row so the VIP
    // Center receives accurate level + expiry data, same as the profile screen.
    int vipLevel = 0;
    DateTime? vipExpiresAt;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('vip_level, vip_expires_at')
            .eq('id', uid)
            .maybeSingle();
        if (row != null) {
          vipLevel = (row['vip_level'] as int?) ?? 0;
          final expiresRaw = row['vip_expires_at'];
          if (expiresRaw != null) {
            vipExpiresAt = DateTime.tryParse(expiresRaw.toString());
          }
          // Treat expired VIP as level 0
          if (vipExpiresAt != null && vipExpiresAt.isBefore(DateTime.now())) {
            vipLevel = 0;
          }
        }
      }
    } catch (e, st) {
      debugError('RoomsScreen._openRoom', e, st);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VipCenterScreen(
          isArabic: context.isArabic,
          currentVipLevel: vipLevel,
          vipExpiresAt: vipExpiresAt,
        ),
      ),
    );
  }

  Future<void> _joinRoom(Room room) async {
    // If the room is locked, ask for a PIN via the vault sheet first.
    String? password;
    if (room.isLocked) {
      password = await showVaultPinSheet(
        context,
        title: context.isArabic ? 'غرفة مقفلة' : 'Locked Room',
        subtitle: context.isArabic
            ? 'أدخل كلمة المرور للانضمام.'
            : 'Enter the password to join.',
        requirePin: true,
      );
      if (password == null || !mounted) return;
    }
    try {
      await _roomsService.joinRoom(room.id, password: password);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RoomDetailsScreen(room: room, isArabic: context.isArabic),
        ),
      );

      await _loadRooms();
    } catch (error) {
      if (!mounted) return;

      final message = error is LockedRoomException
          ? (context.isArabic
                ? '\u0627\u0644\u063a\u0631\u0641\u0629 \u0645\u0642\u0641\u0644\u0629 \u0645\u0646 \u0627\u0644\u0645\u0636\u064a\u0641.'
                : 'This room is locked by the host.')
          : error is ClosedRoomException
          ? (context.isArabic
                ? '\u062a\u0645 \u0625\u063a\u0644\u0627\u0642 \u0647\u0630\u0647 \u0627\u0644\u063a\u0631\u0641\u0629.'
                : 'This room is closed.')
          : error.toString();

      SroodToast.show(context, message, type: SroodToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textAlign = context.isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = context.isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final screenW = MediaQuery.of(context).size.width;
    final isCompact = screenW < 380;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRooms,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 14 : 22,
              isCompact ? 14 : 22,
              isCompact ? 14 : 22,
              110,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.isArabic
                          ? (isCompact
                                ? '\u063a\u0631\u0641'
                                : '\u063a\u0631\u0641 \u0645\u0628\u0627\u0634\u0631\u0629')
                          : (isCompact ? 'Rooms' : 'Live Rooms'),
                      textAlign: textAlign,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isCompact ? 22.0 : 34.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SearchScreen(
                          isArabic: context.isArabic,
                          countryCode: _selectedCountryCode,
                        ),
                      ),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: isCompact ? 36 : 40,
                      minHeight: isCompact ? 36 : 40,
                    ),
                    icon: Icon(
                      Icons.search_rounded,
                      color: const Color(0xFFBCAED6),
                      size: isCompact ? 22 : 26,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            LeaderboardScreen(isArabic: context.isArabic),
                      ),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: isCompact ? 36 : 40,
                      minHeight: isCompact ? 36 : 40,
                    ),
                    icon: Icon(
                      Icons.emoji_events_rounded,
                      color: const Color(0xFFF0C15A),
                      size: isCompact ? 20 : 24,
                    ),
                  ),
                  if (isCompact)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Color(0xFFBCAED6),
                        size: 22,
                      ),
                      color: const Color(0xFF201033),
                      onSelected: (v) {
                        if (v == 'schedule') {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  RoomScheduleScreen(isArabic: context.isArabic),
                            ),
                          );
                        } else if (v == 'notifications') {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  NotificationsScreen(isArabic: context.isArabic),
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'schedule',
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_rounded,
                                  color: Color(0xFFBCAED6), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                context.isArabic ? '\u0627\u0644\u062c\u062f\u0648\u0644' : 'Schedule',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFE8DFFF)),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'notifications',
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_outlined,
                                  color: Color(0xFFBCAED6), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                context.isArabic ? '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a' : 'Notifications',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFE8DFFF)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RoomScheduleScreen(isArabic: context.isArabic),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: const Icon(
                        Icons.calendar_month_rounded,
                        color: Color(0xFFBCAED6),
                        size: 24,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              NotificationsScreen(isArabic: context.isArabic),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Color(0xFFBCAED6),
                        size: 26,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Tooltip(
                    message: context.isArabic ? 'غرفتي' : 'My Room',
                    child: GestureDetector(
                      onTap: _openingMyRoom ? null : _openMyRoom,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: _openingMyRoom
                              ? const Color(0xFF3A1A6A)
                              : const Color(0xFF2A1050),
                          border: Border.all(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.55),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B26D9).withValues(
                                alpha: _openingMyRoom ? 0.45 : 0.22,
                              ),
                              blurRadius: _openingMyRoom ? 18 : 10,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: _openingMyRoom
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFF0C15A),
                                  ),
                                )
                              : const Icon(
                                  Icons.other_houses_rounded,
                                  color: Color(0xFFF0C15A),
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                context.isArabic
                    ? '\u0627\u062f\u062e\u0644 \u063a\u0631\u0641\u0629 \u0635\u0648\u062a\u064a\u0629\u060c \u0627\u0633\u0645\u0639\u060c \u0634\u0627\u0631\u0643\u060c \u0623\u0648 \u0627\u0628\u062f\u0623 \u0633\u0647\u0631\u0629 \u062c\u062f\u064a\u062f\u0629.'
                    : 'Join a voice room, listen, talk, or start a new SrOOd.',
                textAlign: textAlign,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: Color(0xFFD8CFEA),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              _RoomsHeroBanner(
                isArabic: context.isArabic,
                onCta: (route) {
                  switch (route) {
                    case 'discovery':
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              DiscoveryScreen(isArabic: context.isArabic),
                        ),
                      );
                    case 'gifts':
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              GiftCatalogScreen(isArabic: context.isArabic),
                        ),
                      );
                    case 'vip':
                      _openVipCenter();
                  }
                },
              ),
              const SizedBox(height: 16),
              // Country filter — all 22 Arab countries as quick chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < _kArabCountries.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _QuickCountryChip(
                        code: _kArabCountries[i].code,
                        flag: _kArabCountries[i].flag,
                        label: context.isArabic
                            ? _kArabCountries[i].ar
                            : _kArabCountries[i].en,
                        isSelected: _selectedCountryCode == _kArabCountries[i].code,
                        isCompact: isCompact,
                        onTap: () {
                          final c = _kArabCountries[i].code;
                          final next = _selectedCountryCode == c ? null : c;
                          setState(() => _selectedCountryCode = next);
                          unawaited(_loadRooms());
                        },
                      ),
                    ],
                    const SizedBox(width: 8),
                    // Full picker for countries outside the Arab list
                    _CountryFilterChip(
                      selectedCode: _kArabCountries.any(
                              (c) => c.code == _selectedCountryCode)
                          ? null
                          : _selectedCountryCode,
                      isArabic: context.isArabic,
                      isCompact: isCompact,
                      onPick: _pickCountry,
                      onClear: () {
                        setState(() => _selectedCountryCode = null);
                        unawaited(_loadRooms());
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                _RoomsMessageCard(
                  title: context.isArabic
                      ? '\u0635\u0627\u0631 \u062e\u0637\u0623'
                      : 'Something went wrong',
                  message: _error!,
                  icon: Icons.error_outline_rounded,
                  crossAxisAlignment: crossAxisAlignment,
                  textAlign: textAlign,
                )
              else if (_filteredRooms.isEmpty)
                _RoomsMessageCard(
                  title: _selectedCountryCode != null
                      ? (context.isArabic
                          ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u063a\u0631\u0641 \u0645\u0646 \u0647\u0630\u0627 \u0627\u0644\u0628\u0644\u062f'
                          : 'No rooms from this country')
                      : (context.isArabic
                          ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u063a\u0631\u0641 \u0628\u0639\u062f'
                          : 'No rooms yet'),
                  message: _selectedCountryCode != null
                      ? (context.isArabic
                          ? '\u062c\u0631\u0651\u0628 \u0627\u062e\u062a\u064a\u0627\u0631 \u0628\u0644\u062f \u0622\u062e\u0631 \u0623\u0648 \u0639\u0631\u0636 \u0627\u0644\u0643\u0644.'
                          : 'Try a different country or view all.')
                      : (context.isArabic
                          ? '\u0627\u0636\u063a\u0637 \u0639\u0644\u0649 \u0632\u0631 + \u0644\u0625\u0646\u0634\u0627\u0621 \u0623\u0648\u0644 \u063a\u0631\u0641\u0629.'
                          : 'Tap + to create the first room.'),
                  icon: _selectedCountryCode != null
                      ? Icons.public_off_rounded
                      : Icons.meeting_room_outlined,
                  crossAxisAlignment: crossAxisAlignment,
                  textAlign: textAlign,
                )
              else
                ..._filteredRooms.map(
                  (room) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _RoomCard(
                      room: room,
                      activeCount: _activeCounts[room.id] ?? 0,
                      isArabic: context.isArabic,
                      onJoin: () => _joinRoom(room),
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


// Promotional carousel banner

// All 22 Arab League member states shown as quick-select chips.
typedef _ArabCountry = ({String code, String flag, String ar, String en});

const List<_ArabCountry> _kArabCountries = [
  (code: 'SA', flag: '\u{1F1F8}\u{1F1E6}', ar: 'السعودية',   en: 'Saudi Arabia'),
  (code: 'EG', flag: '\u{1F1EA}\u{1F1EC}', ar: 'مصر',         en: 'Egypt'),
  (code: 'IQ', flag: '\u{1F1EE}\u{1F1F6}', ar: 'العراق',      en: 'Iraq'),
  (code: 'SY', flag: '\u{1F1F8}\u{1F1FE}', ar: 'سوريا',       en: 'Syria'),
  (code: 'JO', flag: '\u{1F1EF}\u{1F1F4}', ar: 'الأردن',      en: 'Jordan'),
  (code: 'LB', flag: '\u{1F1F1}\u{1F1E7}', ar: 'لبنان',       en: 'Lebanon'),
  (code: 'KW', flag: '\u{1F1F0}\u{1F1FC}', ar: 'الكويت',      en: 'Kuwait'),
  (code: 'AE', flag: '\u{1F1E6}\u{1F1EA}', ar: 'الإمارات',    en: 'UAE'),
  (code: 'QA', flag: '\u{1F1F6}\u{1F1E6}', ar: 'قطر',         en: 'Qatar'),
  (code: 'BH', flag: '\u{1F1E7}\u{1F1ED}', ar: 'البحرين',     en: 'Bahrain'),
  (code: 'OM', flag: '\u{1F1F4}\u{1F1F2}', ar: 'عُمان',        en: 'Oman'),
  (code: 'YE', flag: '\u{1F1FE}\u{1F1EA}', ar: 'اليمن',       en: 'Yemen'),
  (code: 'LY', flag: '\u{1F1F1}\u{1F1FE}', ar: 'ليبيا',       en: 'Libya'),
  (code: 'TN', flag: '\u{1F1F9}\u{1F1F3}', ar: 'تونس',        en: 'Tunisia'),
  (code: 'DZ', flag: '\u{1F1E9}\u{1F1FF}', ar: 'الجزائر',     en: 'Algeria'),
  (code: 'MA', flag: '\u{1F1F2}\u{1F1E6}', ar: 'المغرب',      en: 'Morocco'),
  (code: 'SD', flag: '\u{1F1F8}\u{1F1E9}', ar: 'السودان',     en: 'Sudan'),
  (code: 'SO', flag: '\u{1F1F8}\u{1F1F4}', ar: 'الصومال',     en: 'Somalia'),
  (code: 'MR', flag: '\u{1F1F2}\u{1F1F7}', ar: 'موريتانيا',   en: 'Mauritania'),
  (code: 'DJ', flag: '\u{1F1E9}\u{1F1EF}', ar: 'جيبوتي',      en: 'Djibouti'),
  (code: 'KM', flag: '\u{1F1F0}\u{1F1F2}', ar: 'جزر القمر',   en: 'Comoros'),
  (code: 'PS', flag: '\u{1F1F5}\u{1F1F8}', ar: 'فلسطين',      en: 'Palestine'),
];

class _QuickCountryChip extends StatelessWidget {
  const _QuickCountryChip({
    required this.code,
    required this.flag,
    required this.label,
    required this.isSelected,
    required this.isCompact,
    required this.onTap,
  });

  final String code;
  final String flag;
  final String label;
  final bool isSelected;
  final bool isCompact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: isCompact ? 36.0 : 40.0,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF3A1070), Color(0xFF5B1A9A)],
                )
              : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF0C15A).withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.16),
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//  Country filter chip

class _CountryFilterChip extends StatelessWidget {
  const _CountryFilterChip({
    required this.selectedCode,
    required this.isArabic,
    required this.isCompact,
    required this.onPick,
    required this.onClear,
  });

  final String? selectedCode;
  final bool isArabic;
  final bool isCompact;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final selected = countryFromStored(selectedCode);
    final hasFilter = selected != null;

    return GestureDetector(
      onTap: onPick,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: isCompact ? 36.0 : 40.0,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: hasFilter
              ? const LinearGradient(
                  colors: [Color(0xFF3A1070), Color(0xFF5B1A9A)],
                )
              : null,
          color: hasFilter ? null : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: hasFilter
                ? const Color(0xFFF0C15A).withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.16),
            width: 1.0,
          ),
          boxShadow: hasFilter
              ? [
                  BoxShadow(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.public_rounded,
                size: 16,
                color: hasFilter
                    ? const Color(0xFFF0C15A)
                    : Colors.white.withValues(alpha: 0.50),
              ),
              const SizedBox(width: 8),
              Text(
                hasFilter
                    ? '${selected.flag}  ${selected.name}'
                    : (isArabic ? 'كل الدول' : 'All Countries'),
                style: TextStyle(
                  color: hasFilter
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight:
                      hasFilter ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              if (hasFilter)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                )
              else
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.40),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

//
// Promotional carousel banner
//

class _SlideData {
  const _SlideData({
    required this.labelAr,
    required this.labelEn,
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.ctaAr,
    required this.ctaEn,
    required this.icon,
    required this.gradientColors,
    required this.iconBgColor,
    this.targetRoute,
    this.imageUrl,
    this.updatedAt,
  });

  final String labelAr;
  final String labelEn;
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final String ctaAr;
  final String ctaEn;
  final IconData icon;
  final List<Color> gradientColors;
  final Color iconBgColor;
  final String? targetRoute;
  /// Optional banner image from Supabase Storage. When non-null it is shown as
  /// a full-cover background replacing the gradient+icon layout.
  final String? imageUrl;
  /// Used to build a cache-busting URL so the app re-fetches the image after
  /// an admin edit without needing to clear Flutter's image cache manually.
  final DateTime? updatedAt;

  /// Returns the image URL with an `?v=` cache-buster derived from updatedAt.
  /// When updatedAt is absent the raw URL is returned unchanged so Flutter's
  /// image cache can reuse the decoded image across rebuilds.
  String? get cachedImageUrl {
    final url = imageUrl;
    if (url == null || url.isEmpty) return null;
    if (updatedAt == null) return url;
    final v = updatedAt!.millisecondsSinceEpoch;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}v=$v';
  }

  static _SlideData fromJson(Map<String, dynamic> j) {
    Color hex(String? h, Color fb) {
      if (h == null || h.isEmpty) return fb;
      try {
        return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
      } catch (e) {
        return fb;
      }
    }

    final g1 = hex(j['gradient_start'] as String?, const Color(0xFF2D0D5E));
    final g2 = hex(j['gradient_mid'] as String?, const Color(0xFF5B1A9A));
    final g3 = hex(j['gradient_end'] as String?, const Color(0xFF8B26D9));
    final bg = hex(j['icon_bg_color'] as String?, const Color(0xFF6E14B8));

    const iconMap = <String, IconData>{
      'mic_rounded': Icons.mic_rounded,
      'card_giftcard_rounded': Icons.card_giftcard_rounded,
      'workspace_premium_rounded': Icons.workspace_premium_rounded,
      'star_rounded': Icons.star_rounded,
      'celebration_rounded': Icons.celebration_rounded,
      'favorite_rounded': Icons.favorite_rounded,
    };
    final iconKey = j['icon_name'] as String? ?? 'mic_rounded';
    final icon = iconMap[iconKey] ?? Icons.mic_rounded;

    final rawUrl = j['image_url'] as String?;
    final imageUrl = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : null;

    DateTime? updatedAt;
    final rawTs = j['updated_at'];
    if (rawTs != null) updatedAt = DateTime.tryParse(rawTs.toString());

    return _SlideData(
      labelAr: j['label_ar'] as String? ?? '',
      labelEn: j['label_en'] as String? ?? '',
      titleAr: j['title_ar'] as String? ?? '',
      titleEn: j['title_en'] as String? ?? '',
      subtitleAr: j['subtitle_ar'] as String? ?? '',
      subtitleEn: j['subtitle_en'] as String? ?? '',
      ctaAr: j['cta_ar'] as String? ?? '',
      ctaEn: j['cta_en'] as String? ?? '',
      icon: icon,
      gradientColors: [g1, g2, g3],
      iconBgColor: bg,
      targetRoute: j['target_route'] as String?,
      imageUrl: imageUrl,
      updatedAt: updatedAt,
    );
  }
}

const _kSlides = [
  _SlideData(
    labelAr: '\u0633\u0647\u0631\u0648\u062f \u0644\u0627\u064a\u0641',
    labelEn: 'Srood Live',
    titleAr:
        '\u0627\u062e\u062a\u0631 \u063a\u0631\u0641\u0629 \u0648\u0627\u0628\u062f\u0623 \u0627\u0644\u0633\u0647\u0631\u0629',
    titleEn: 'Choose a room,\nstart the night',
    subtitleAr:
        '\u063a\u0631\u0641 \u0635\u0648\u062a\u064a\u0629\u060c \u0645\u0636\u064a\u0641\u064a\u0646\u060c \u0648\u0623\u062c\u0648\u0627\u0621 \u062d\u064a\u0629 \u0641\u062e\u0645\u0629.',
    subtitleEn: 'Voice rooms, hosts & a premium live vibe.',
    ctaAr:
        '\u0627\u0633\u062a\u0643\u0634\u0641 \u0627\u0644\u063a\u0631\u0641',
    ctaEn: 'Explore Rooms',
    icon: Icons.mic_rounded,
    gradientColors: [Color(0xFF2D0D5E), Color(0xFF5B1A9A), Color(0xFF8B26D9)],
    iconBgColor: Color(0xFF6E14B8),
    targetRoute: 'discovery',
  ),
  _SlideData(
    labelAr: '\u0627\u0644\u0645\u0643\u0627\u0641\u0622\u062a',
    labelEn: 'Rewards',
    titleAr:
        '\u0623\u0631\u0633\u0644 \u0647\u062f\u0627\u064a\u0627 \u0648\u0627\u0631\u062a\u0642\u0650',
    titleEn: 'Send gifts,\nrise faster',
    subtitleAr:
        '\u0627\u062f\u0639\u0645 \u0645\u0636\u064a\u0641\u064a\u0646\u0643 \u0648\u0627\u0643\u0633\u0628 \u0645\u0643\u0627\u0646\u0629 \u0623\u0639\u0644\u0649.',
    subtitleEn: 'Support hosts, earn status & unlock rewards.',
    ctaAr: '\u0639\u0631\u0636 \u0627\u0644\u0647\u062f\u0627\u064a\u0627',
    ctaEn: 'View Gifts',
    icon: Icons.card_giftcard_rounded,
    gradientColors: [Color(0xFF1A0A3A), Color(0xFF6B2396), Color(0xFFB8406A)],
    iconBgColor: Color(0xFF8E2058),
    targetRoute: 'gifts',
  ),
  _SlideData(
    labelAr: '\u0627\u0644\u0646\u062e\u0628\u0629',
    labelEn: 'VIP',
    titleAr:
        '\u0627\u0641\u062a\u062d \u0645\u0632\u0627\u064a\u0627 \u0627\u0644\u0646\u062e\u0628\u0629',
    titleEn: 'Unlock VIP\nperks',
    subtitleAr:
        '\u0634\u0627\u0631\u0627\u062a\u060c \u0623\u0633\u0644\u0648\u0628 \u0645\u0644\u0641\u060c \u062d\u0636\u0648\u0631 \u0645\u0645\u064a\u0632 \u0648\u0645\u0632\u064a\u062f.',
    subtitleEn: 'Badges, profile style, premium presence & more.',
    ctaAr: '\u0645\u0631\u0643\u0632 VIP',
    ctaEn: 'VIP Center',
    icon: Icons.workspace_premium_rounded,
    gradientColors: [Color(0xFF1C1000), Color(0xFF5C3A00), Color(0xFF9E6A00)],
    iconBgColor: Color(0xFF7A4E00),
    targetRoute: 'vip',
  ),
];

class _RoomsHeroBanner extends StatefulWidget {
  const _RoomsHeroBanner({required this.isArabic, required this.onCta});

  final bool isArabic;
  final void Function(String? route) onCta;

  @override
  State<_RoomsHeroBanner> createState() => _RoomsHeroBannerState();
}

class _RoomsHeroBannerState extends State<_RoomsHeroBanner> {
  late final PageController _pageCtrl;
  Timer? _timer;
  int _page = 0;
  List<_SlideData> _slides = _kSlides;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _startTimer();
    _fetchSlides();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchSlides() async {
    try {
      final data = await Supabase.instance.client
          .from('promo_banners')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      final rows = data as List<dynamic>;
      if (rows.isEmpty) return;
      final parsed = rows
          .map((e) => _SlideData.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _slides = parsed;
        _page = 0;
      });
      // Warm Flutter's image cache so banners appear instantly on first display.
      for (final slide in _slides) {
        final url = slide.cachedImageUrl;
        if (url != null && mounted) {
          unawaited(precacheImage(NetworkImage(url), context));
        }
      }
    } catch (e, st) {
      debugError('RoomsScreen._loadPromoSlides', e, st);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _slides.isEmpty) return;
      final next = (_page + 1) % _slides.length;
      if (next >= _slides.length) return;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 162,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _BannerSlide(
              slide: _slides[i],
              isArabic: context.isArabic,
              onCta: () => widget.onCta(_slides[i].targetRoute),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: active
                    ? const Color(0xFFF0C15A)
                    : const Color(0xFF3A2460),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _BannerSlide extends StatelessWidget {
  const _BannerSlide({
    required this.slide,
    required this.isArabic,
    required this.onCta,
  });

  final _SlideData slide;
  final bool isArabic;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final isRtl = isArabic;
    final align = isRtl ? TextAlign.right : TextAlign.left;

    final imageUrl = slide.cachedImageUrl;

    //  Determine inner content based on whether an image URL is set
    Widget innerContent;
    if (imageUrl != null) {
      // Image banner: full-cover photo. The container behind it provides a
      // purple gradient placeholder that shows while the image loads.
      innerContent = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          // Gradient from the container shows through; just add a soft indicator.
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFF0C15A),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white.withValues(alpha: 0.30),
                size: 28,
              ),
            ],
          ),
        ),
      );
    } else {
      // Gradient + icon banner (fallback when no image uploaded).
      final cross2 = isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;
      final textBlock = Column(
        crossAxisAlignment: cross2,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isArabic ? slide.labelAr : slide.labelEn,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic ? slide.titleAr : slide.titleEn,
            textAlign: align,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isArabic ? slide.subtitleAr : slide.subtitleEn,
            textAlign: align,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Text(
                isArabic ? slide.ctaAr : slide.ctaEn,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      );
      innerContent = Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: slide.iconBgColor.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Icon(slide.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: textBlock),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onCta,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: imageUrl != null
                  ? const [Color(0xFF1A0533), Color(0xFF2D0D5E), Color(0xFF4A1280)]
                  : slide.gradientColors,
            ),
          boxShadow: [
            BoxShadow(
              color: slide.gradientColors.last.withValues(alpha: 0.32),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: innerContent,
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.activeCount,
    required this.isArabic,
    required this.onJoin,
  });

  final Room room;
  final int activeCount;
  final bool isArabic;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final hasCover  = room.coverUrl?.isNotEmpty == true;
    final hasAvatar = room.avatarUrl?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF0C15A).withValues(alpha: 0.65),
            const Color(0xFF8B26D9).withValues(alpha: 0.58),
            const Color(0xFF4A3470).withValues(alpha: 0.34),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          children: [
            //  Background layer
            if (hasCover)
              Positioned.fill(
                child: Image.network(
                  room.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => const _RoomCardDefaultBg(),
                ),
              )
            else
              const Positioned.fill(child: _RoomCardDefaultBg()),

            //  Dark gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: hasCover
                        ? [
                            Colors.black.withValues(alpha: 0.38),
                            Colors.black.withValues(alpha: 0.72),
                          ]
                        : [Colors.transparent, Colors.transparent],
                  ),
                ),
              ),
            ),

            //  Content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: crossAxisAlignment,
                children: [
                  Row(
                    textDirection:
                        isArabic ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      // Room avatar / icon
                      Container(
                        width: 58,
                        height: 58,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: hasAvatar
                              ? null
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF4A2A1D),
                                    Color(0xFF2E2238),
                                  ],
                                ),
                          border: Border.all(
                            color: const Color(0xFFF0C15A)
                                .withValues(alpha: 0.30),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.30),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: hasAvatar
                            ? Image.network(
                                room.avatarUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (_, child, progress) =>
                                    progress == null
                                        ? child
                                        : const ColoredBox(
                                            color: Color(0xFF2D2040),
                                          ),
                                errorBuilder: (_, e, s) => const Icon(
                                  Icons.mic_rounded,
                                  color: Color(0xFFF0C15A),
                                  size: 30,
                                ),
                              )
                            : const Icon(
                                Icons.mic_rounded,
                                color: Color(0xFFF0C15A),
                                size: 30,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: crossAxisAlignment,
                          children: [
                            Text(
                              room.name,
                              textAlign: textAlign,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                color: Colors.white,
                                shadows: hasCover
                                    ? [
                                        const Shadow(
                                          blurRadius: 6,
                                          color: Colors.black54,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              room.description?.isNotEmpty == true
                                  ? room.description!
                                  : (isArabic ? '\u0628\u062f\u0648\u0646 \u0648\u0635\u0641' : 'No description'),
                              textAlign: textAlign,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: hasCover
                                    ? Colors.white.withValues(alpha: 0.82)
                                    : const Color(0xFFD8CFEA),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    textDirection:
                        isArabic ? TextDirection.rtl : TextDirection.ltr,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          textDirection:
                              isArabic ? TextDirection.rtl : TextDirection.ltr,
                          children: [
                            _RoomPill(
                              icon: Icons.language_rounded,
                              label: room.language.toUpperCase(),
                              hasCover: hasCover,
                            ),
                            _RoomPill(
                              icon: Icons.people_rounded,
                              label: '$activeCount/${room.maxSeats}',
                              hasCover: hasCover,
                            ),
                            if (room.isLocked)
                              _RoomPill(
                                icon: Icons.lock_rounded,
                                label: isArabic ? '\u0645\u0642\u0641\u0644\u0629' : 'Locked',
                                hasCover: hasCover,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF0C15A)
                                  .withValues(alpha: 0.26),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          onPressed: onJoin,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.login_rounded, size: 16),
                          label: Text(isArabic ? '\u062f\u062e\u0648\u0644' : 'Join'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCardDefaultBg extends StatelessWidget {
  const _RoomCardDefaultBg();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF201033), Color(0xFF171125), Color(0xFF12091D)],
        ),
      ),
    );
  }
}

class _RoomPill extends StatelessWidget {
  const _RoomPill({
    required this.icon,
    required this.label,
    this.hasCover = false,
  });

  final IconData icon;
  final String label;
  final bool hasCover;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: hasCover
            ? Colors.black.withValues(alpha: 0.42)
            : const Color(0xFF241638),
        borderRadius: BorderRadius.circular(999),
        border: hasCover
            ? Border.all(color: Colors.white.withValues(alpha: 0.12))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFF0C15A)),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsMessageCard extends StatelessWidget {
  const _RoomsMessageCard({
    required this.title,
    required this.message,
    required this.icon,
    required this.crossAxisAlignment,
    required this.textAlign,
  });

  final String title;
  final String message;
  final IconData icon;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171125),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: textAlign,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: textAlign,
            style: const TextStyle(color: Color(0xFFD8CFEA)),
          ),
        ],
      ),
    );
  }
}
