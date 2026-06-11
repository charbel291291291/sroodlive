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
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xFF241638), Color(0xFF130A20)],
            ),
            border: Border.all(color: const Color(0xFF5A3A86)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B26D9).withValues(alpha: 0.28),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              height: 66,
              backgroundColor: Colors.transparent,
              elevation: 0,
              indicatorColor: const Color(0xFFF0C15A).withValues(alpha: 0.18),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);

                return TextStyle(
                  color: selected
                      ? const Color(0xFFF0C15A)
                      : const Color(0xFFD8CFEA),
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 12,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);

                return IconThemeData(
                  color: selected
                      ? const Color(0xFFF0C15A)
                      : const Color(0xFFD8CFEA),
                  size: selected ? 28 : 24,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  selectedIndex = index;
                });
              },
              destinations: [
                NavigationDestination(
                  selectedIcon: const Icon(Icons.meeting_room_rounded),
                  icon: const Icon(Icons.meeting_room_outlined),
                  label: isArabic ? 'الغرف' : 'Rooms',
                ),
                NavigationDestination(
                  selectedIcon: Badge(
                    isLabelVisible: _messagesUnread > 0,
                    label: Text(_messagesUnread > 99
                        ? '99+'
                        : '$_messagesUnread'),
                    backgroundColor: const Color(0xFFFF4D6D),
                    child: const Icon(Icons.chat_bubble_rounded),
                  ),
                  icon: Badge(
                    isLabelVisible: _messagesUnread > 0,
                    label: Text(_messagesUnread > 99
                        ? '99+'
                        : '$_messagesUnread'),
                    backgroundColor: const Color(0xFFFF4D6D),
                    child: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  label: isArabic ? 'رسائل' : 'Messages',
                ),
                NavigationDestination(
                  selectedIcon: const Icon(Icons.rocket_launch_rounded),
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: isArabic ? 'الألعاب' : 'Games',
                ),
                NavigationDestination(
                  selectedIcon: const Icon(
                    Icons.account_balance_wallet_rounded,
                  ),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: isArabic ? 'المحفظة' : 'Wallet',
                ),
                NavigationDestination(
                  selectedIcon: const Icon(Icons.person_rounded),
                  icon: const Icon(Icons.person_outline_rounded),
                  label: isArabic ? 'الملف' : 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
