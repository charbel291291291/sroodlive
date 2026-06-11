import 'package:flutter/material.dart';

import '../../main.dart';
import '../games/screens/crash_game_screen.dart';
import '../messages/screens/messages_screen.dart';
import '../profile/profile_screen.dart';
import '../rooms/screens/rooms_screen.dart';
import '../wallet/screens/wallet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  int _messagesUnread = 0;

  @override
  Widget build(BuildContext context) {
    final isArabic =
        AppLanguageController.of(context).locale.languageCode == 'ar';

    final pages = [
      RoomsScreen(isArabic: isArabic),
      MessagesScreen(
        isArabic: isArabic,
        onUnreadChanged: (count) {
          if (_messagesUnread != count) {
            setState(() => _messagesUnread = count);
          }
        },
      ),
      CrashGameScreen(isArabic: isArabic),
      WalletScreen(isArabic: isArabic),
      ProfileScreen(isArabic: isArabic),
    ];

    return Scaffold(
      extendBody: true,
      body: pages[selectedIndex],
      bottomNavigationBar: _BottomNavBar(
        selectedIndex: selectedIndex,
        isArabic: isArabic,
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
    required this.messagesUnread,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool isArabic;
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
        icon: Icons.rocket_launch_rounded,
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

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        height: 82,
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
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: item.glow.withValues(alpha: 0.60),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 5),
                      ),
                      BoxShadow(
                        color: item.glow.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
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
