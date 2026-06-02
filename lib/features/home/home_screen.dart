import 'package:flutter/material.dart';
import '../../core/supabase/supabase_service.dart';
import '../../main.dart';
import '../profile/profile_screen.dart';
import '../rooms/screens/rooms_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isArabic =
        AppLanguageController.of(context).locale.languageCode == 'ar';

    final pages = [
      RoomsScreen(isArabic: isArabic),
      WalletTab(isArabic: isArabic),
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

class RoomsTab extends StatelessWidget {
  const RoomsTab({required this.isArabic, super.key});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final isSupabaseReady = SupabaseService.isConfigured;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: isArabic
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الغرف المباشرة' : 'Live Rooms',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'الغرف الصوتية ستظهر هنا بعد ربط قاعدة البيانات.'
                  : 'Voice rooms will appear here after database setup.',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontSize: 16, color: Color(0xFFB8B8C7)),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF14141F),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSupabaseReady
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFFD6A84F),
                ),
              ),
              child: Text(
                isSupabaseReady
                    ? (isArabic ? 'Supabase متصل' : 'Supabase connected')
                    : (isArabic
                          ? 'Supabase غير مفعل'
                          : 'Supabase not configured'),
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  color: isSupabaseReady
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFFD6A84F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletTab extends StatelessWidget {
  const WalletTab({required this.isArabic, super.key});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: isArabic
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'المحفظة' : 'Wallet',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'العملات الهدايا وسجل الشحن سيظهرون هنا.'
                  : 'Coins, gifts, and recharge history will appear here.',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontSize: 16, color: Color(0xFFB8B8C7)),
            ),
          ],
        ),
      ),
    );
  }
}
