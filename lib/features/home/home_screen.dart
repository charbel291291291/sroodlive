import 'package:flutter/material.dart';
import '../../main.dart';
import '../profile/profile_screen.dart';

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
      RoomsTab(isArabic: isArabic),
      WalletTab(isArabic: isArabic),
      ProfileScreen(isArabic: isArabic),
    ];

    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.meeting_room_rounded),
            label: isArabic ? 'الغرف' : 'Rooms',
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_rounded),
            label: isArabic ? 'المحفظة' : 'Wallet',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_rounded),
            label: isArabic ? 'الملف' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class RoomsTab extends StatelessWidget {
  const RoomsTab({
    required this.isArabic,
    super.key,
  });

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment:
              isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الغرف المباشرة' : 'Live Rooms',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'الغرف الصوتية ستظهر هنا بعد ربط Supabase.'
                  : 'Voice rooms will appear here after Supabase setup.',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFB8B8C7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletTab extends StatelessWidget {
  const WalletTab({
    required this.isArabic,
    super.key,
  });

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment:
              isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'المحفظة' : 'Wallet',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'العملات الهدايا وسجل الشحن سيظهرون هنا.'
                  : 'Coins, gifts, and recharge history will appear here.',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFB8B8C7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
