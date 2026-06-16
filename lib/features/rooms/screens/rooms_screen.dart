import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/discovery/screens/discovery_screen.dart';
import '../../../features/gamification/screens/vip_center_screen.dart';
import '../../../features/gifts/screens/gift_catalog_screen.dart';
import '../../../features/notifications/screens/notifications_screen.dart';
import '../../../features/search/screens/search_screen.dart';
import '../../../features/social/screens/leaderboard_screen.dart';
import '../models/room.dart';
import '../services/rooms_service.dart';
import '../widgets/vault_pin_sheet.dart';
import 'room_details_screen.dart';
import 'room_schedule_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

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

      final rooms = await _roomsService.getRooms();
      final activeCounts = await _roomsService.getActiveMemberCounts();

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

      // If the personal room was closed by the owner, reopen it.
      if (room.isClosed) {
        room = await _roomsService.reopenMyRoom();
        if (!mounted) return;
      }

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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
                        builder: (_) => SearchScreen(isArabic: context.isArabic),
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
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD978), Color(0xFFD99A2B)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFF0C15A,
                          ).withValues(alpha: 0.28),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _openingMyRoom ? null : _openMyRoom,
                      color: const Color(0xFF12061F),
                      icon: _openingMyRoom
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.other_houses_rounded),
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
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              VipCenterScreen(isArabic: context.isArabic),
                        ),
                      );
                  }
                },
              ),
              const SizedBox(height: 22),
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
              else if (_rooms.isEmpty)
                _RoomsMessageCard(
                  title: context.isArabic
                      ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u063a\u0631\u0641 \u0628\u0639\u062f'
                      : 'No rooms yet',
                  message: context.isArabic
                      ? '\u0627\u0636\u063a\u0637 \u0639\u0644\u0649 \u0632\u0631 + \u0644\u0625\u0646\u0634\u0627\u0621 \u0623\u0648\u0644 \u063a\u0631\u0641\u0629.'
                      : 'Tap + to create the first room.',
                  icon: Icons.meeting_room_outlined,
                  crossAxisAlignment: crossAxisAlignment,
                  textAlign: textAlign,
                )
              else
                ..._rooms.map(
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

// \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
// Promotional carousel banner
// \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

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

  static _SlideData fromJson(Map<String, dynamic> j) {
    Color hex(String? h, Color fb) {
      if (h == null || h.isEmpty) return fb;
      try {
        return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
      } catch (_) {
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
    } catch (_) {
      // silently fall back to hardcoded slides
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_page + 1) % _slides.length;
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
    final cross = isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = isRtl ? TextAlign.right : TextAlign.left;

    return GestureDetector(
      onTap: onCta,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: slide.gradientColors,
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Icon block
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: slide.iconBgColor.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Icon(slide.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              // Text + CTA
              Expanded(
                child: Column(
                  crossAxisAlignment: cross,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Label pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
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
                    // Title
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
                    // Subtitle
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
                    // CTA pill
                    Align(
                      alignment: isRtl
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
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
                ),
              ),
            ],
          ),
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
            // \u2500\u2500 Background layer \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
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

            // \u2500\u2500 Dark gradient overlay \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
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

            // \u2500\u2500 Content \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
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
