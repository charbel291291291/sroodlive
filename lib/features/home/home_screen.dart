import 'dart:async';

import 'package:flutter/material.dart';
import 'package:srood_live/shared/utils/error_utils.dart';

import '../../core/frames/frame_catalog_sync_service.dart';
import '../../core/frames/frames_v2_rendering_flag_service.dart';
import '../../core/update/app_update_dialog.dart';
import '../../core/update/app_update_service.dart';
import '../../main.dart';
import '../daily_reward/daily_reward_popup.dart';
import '../daily_reward/daily_reward_service.dart';
import '../games/screens/game_center_screen.dart';
import '../messages/screens/messages_screen.dart';
import '../profile/profile_screen.dart';
import '../rooms/screens/rooms_screen.dart';
import '../rooms/services/room_read_service.dart';
import '../wallet/screens/wallet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  int _roomsUnread = 0;
  int _messagesUnread = 0;

  // Auto-show the daily reward at most once per widget instance. Non-static so
  // it resets on logout/re-login (which creates a new HomeScreen instance).
  bool _dailyRewardShownThisSession = false;

  @override
  void initState() {
    super.initState();
    RoomReadService.instance.unreadCount.addListener(_onRoomsUnreadChanged);
    _roomsUnread = RoomReadService.instance.unreadCount.value;
    unawaited(RoomReadService.instance.initialize());
    // Fire-and-forget: populates the cached frames_v2_rendering_enabled
    // value for this session. Every SroodAvatarFrame reads the cache
    // synchronously and defaults to false (legacy path) until this
    // resolves, so there is no loading gate to wait on here.
    unawaited(FramesV2RenderingFlagService.instance.load());
    // Same fire-and-forget contract: hydrates FrameRegistry with the live
    // frame_catalog so admin-created frames can render at all. Loaded here
    // rather than in main() because get_frame_catalog_v2 is granted to
    // `authenticated` only. Failure leaves the built-in catalog in place.
    unawaited(FrameCatalogSyncService.instance.load());

    // Run startup checks once per session, after the first frame so the
    // navigator is ready to show dialogs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupChecks();
    });
  }

  void _onRoomsUnreadChanged() {
    if (!mounted) return;
    final count = RoomReadService.instance.unreadCount.value;
    if (_roomsUnread != count) setState(() => _roomsUnread = count);
  }

  @override
  void dispose() {
    RoomReadService.instance.unreadCount.removeListener(_onRoomsUnreadChanged);
    super.dispose();
  }

  Future<void> _runStartupChecks() async {
    await _checkForUpdate();
    await _maybeShowDailyReward();
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final info = await const AppUpdateService().checkForUpdate();
    if (!mounted || info == null) return;
    final isArabic =
        AppLanguageController.of(context).locale.languageCode == 'ar';
    await showAppUpdateDialog(context, info: info, isArabic: isArabic);
  }

  Future<void> _maybeShowDailyReward() async {
    if (_dailyRewardShownThisSession || !mounted) return;
    try {
      final state = await const DailyRewardService().getState();
      if (!mounted) return;
      // Only auto-pop when enabled, popup allowed, and a claim is available.
      if (!state.enabled || !state.popupEnabled || !state.canClaimToday) return;
      _dailyRewardShownThisSession = true;
      final isArabic =
          AppLanguageController.of(context).locale.languageCode == 'ar';
      await showDailyRewardDialog(context, state: state, isArabic: isArabic);
    } catch (e, st) {
      debugError('HomeScreen._maybeTriggerDailyReward', e, st);
    }
  }

  // Cached tab pages. Reusing the identical widget instances lets Flutter
  // skip re-building the visible page when only the nav bar state changes
  // (unread badges, selected tab) — the profile page in particular is not
  // re-laid-out by badge updates.
  List<Widget>? _pages;
  bool? _pagesArabic;

  List<Widget> _buildPages(bool isArabic) {
    if (_pages != null && _pagesArabic == isArabic) return _pages!;
    _pagesArabic = isArabic;
    return _pages = [
      RoomsScreen(isArabic: isArabic),
      MessagesScreen(
        isArabic: isArabic,
        onUnreadChanged: (count) {
          if (_messagesUnread != count) {
            setState(() => _messagesUnread = count);
          }
        },
      ),
      GameCenterScreen(isArabic: isArabic),
      WalletScreen(isArabic: isArabic),
      ProfileScreen(isArabic: isArabic),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isArabic =
        AppLanguageController.of(context).locale.languageCode == 'ar';

    final pages = _buildPages(isArabic);

    return Scaffold(
      extendBody: true,
      body: pages[selectedIndex],
      bottomNavigationBar: _BottomNavBar(
        selectedIndex: selectedIndex,
        isArabic: isArabic,
        roomsUnread: _roomsUnread,
        messagesUnread: _messagesUnread,
        onSelected: (i) => setState(() => selectedIndex = i),
      ),
    );
  }
}

// ── Custom 3D bottom navigation bar ──────────────────────────────────────────

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.selectedIndex,
    required this.isArabic,
    required this.roomsUnread,
    required this.messagesUnread,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool isArabic;
  final int roomsUnread;
  final int messagesUnread;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(
        icon: Icons.spatial_audio_rounded,
        labelEn: 'Rooms',
        labelAr: 'الغرف',
        gradTop: const Color(0xFF9B59F5),
        gradBot: const Color(0xFF4C1D95),
        glow: const Color(0xFF8B5CF6),
        badge: roomsUnread,
      ),
      _NavItem(
        icon: Icons.chat_bubble_rounded,
        labelEn: 'Messages',
        labelAr: 'رسائل',
        gradTop: const Color(0xFF3B82F6),
        gradBot: const Color(0xFF1E3A8A),
        glow: const Color(0xFF60A5FA),
        badge: messagesUnread,
      ),
      _NavItem(
        icon: Icons.sports_esports_rounded,
        labelEn: 'Games',
        labelAr: 'الألعاب',
        gradTop: const Color(0xFFF97316),
        gradBot: const Color(0xFF7C2D12),
        glow: const Color(0xFFFB923C),
      ),
      _NavItem(
        icon: Icons.account_balance_wallet_rounded,
        labelEn: 'Wallet',
        labelAr: 'المحفظة',
        gradTop: const Color(0xFF10B981),
        gradBot: const Color(0xFF064E3B),
        glow: const Color(0xFF34D399),
      ),
      _NavItem(
        icon: Icons.person_rounded,
        labelEn: 'Me',
        labelAr: 'أنا',
        gradTop: const Color(0xFFF0C15A),
        gradBot: const Color(0xFF92400E),
        glow: const Color(0xFFFBBF24),
      ),
    ];

    // Adaptive height: the bar hugs its content instead of a fixed 82px box,
    // so it never overflows on shorter usable heights, Arabic line metrics, or
    // larger system font scales. Text scaling is clamped so accessibility font
    // sizes can't blow out the layout. SafeArea keeps it clear of the system
    // navigation bar (3-button or gesture).
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF241638), Color(0xFF130A20)],
            ),
            border: Border.all(color: const Color(0xFF5A3A86)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B26D9).withValues(alpha: 0.30),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelected(i),
                    behavior: HitTestBehavior.opaque,
                    child: _NavTile(
                      item: items[i],
                      isArabic: isArabic,
                      selected: selectedIndex == i,
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

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.labelEn,
    required this.labelAr,
    required this.gradTop,
    required this.gradBot,
    required this.glow,
    this.badge = 0,
  });

  final IconData icon;
  final String labelEn;
  final String labelAr;
  final Color gradTop;
  final Color gradBot;
  final Color glow;
  final int badge;
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.isArabic,
    required this.selected,
  });

  final _NavItem item;
  final bool isArabic;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final label = isArabic ? item.labelAr : item.labelEn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: selected ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.elasticOut,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? [item.gradTop, item.gradBot]
                    : [
                        item.gradTop.withValues(alpha: 0.18),
                        item.gradBot.withValues(alpha: 0.10),
                      ],
              ),
              // Single restrained glow — the selected tab reads clearly
              // without dominating the page content above it.
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: item.glow.withValues(alpha: 0.38),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.06),
                width: selected ? 1.0 : 0.6,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 3D shine highlight — top-left arc
                if (selected)
                  Positioned(
                    top: 4,
                    left: 5,
                    child: Container(
                      width: 18,
                      height: 7,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.38),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                // bottom-right inner shadow for depth
                if (selected)
                  Positioned(
                    bottom: 3,
                    right: 4,
                    child: Container(
                      width: 14,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.0),
                            Colors.black.withValues(alpha: 0.22),
                          ],
                        ),
                      ),
                    ),
                  ),
                // unread badge
                if (item.badge > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4D6D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF130A20),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        item.badge > 99 ? '99+' : '${item.badge}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                Icon(
                  item.icon,
                  size: 22,
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.40),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: selected
                ? const Color(0xFFF0C15A)
                : Colors.white.withValues(alpha: 0.38),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 11,
            letterSpacing: selected ? 0.2 : 0.0,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
