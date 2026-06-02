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
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 120),
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Text(
                isArabic
                    ? '\u0627\u0644\u0645\u062d\u0641\u0638\u0629'
                    : 'Wallet',
                textAlign: textAlign,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? '\u062a\u0627\u0628\u0639 \u0627\u0644\u0639\u0645\u0644\u0627\u062a\u060c \u0627\u0644\u0623\u0644\u0645\u0627\u0633\u060c \u0627\u0644\u062f\u062e\u0644\u060c \u0648\u0637\u0644\u0628\u0627\u062a \u0627\u0644\u0633\u062d\u0628.'
                    : 'Track coins, diamonds, income, and cashout requests.',
                textAlign: textAlign,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: Color(0xFFD8CFEA),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              _WalletHeroCard(isArabic: isArabic),
              const SizedBox(height: 18),
              Row(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Expanded(
                    child: _WalletStatCard(
                      icon: Icons.monetization_on_rounded,
                      title: isArabic
                          ? '\u0639\u0645\u0644\u0627\u062a'
                          : 'Coins',
                      value: '0',
                      subtitle: isArabic
                          ? '\u0631\u0635\u064a\u062f \u0627\u0644\u0644\u0639\u0628'
                          : 'Play balance',
                      highlighted: true,
                      isArabic: isArabic,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _WalletStatCard(
                      icon: Icons.diamond_rounded,
                      title: isArabic
                          ? '\u0623\u0644\u0645\u0627\u0633'
                          : 'Diamonds',
                      value: '0',
                      subtitle: isArabic
                          ? '\u0647\u062f\u0627\u064a\u0627 \u0648\u062f\u0639\u0645'
                          : 'Gifts and support',
                      highlighted: false,
                      isArabic: isArabic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Expanded(
                    child: _WalletStatCard(
                      icon: Icons.account_balance_wallet_rounded,
                      title: isArabic
                          ? '\u0627\u0644\u062f\u062e\u0644'
                          : 'Income',
                      value: '\$0',
                      subtitle: isArabic
                          ? '\u0642\u0627\u0628\u0644 \u0644\u0644\u0633\u062d\u0628 \u0644\u0627\u062d\u0642\u0627\u064b'
                          : 'Cashout later',
                      highlighted: false,
                      isArabic: isArabic,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _WalletStatCard(
                      icon: Icons.groups_rounded,
                      title: isArabic
                          ? '\u0627\u0644\u0648\u0643\u0627\u0644\u0629'
                          : 'Agency',
                      value: '-',
                      subtitle: isArabic
                          ? '\u0646\u0638\u0627\u0645 \u0627\u0644\u0648\u0643\u0627\u0644\u0627\u062a'
                          : 'Agency system',
                      highlighted: false,
                      isArabic: isArabic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _WalletActionPanel(isArabic: isArabic),
              const SizedBox(height: 18),
              _WalletHistoryPanel(isArabic: isArabic),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletHeroCard extends StatelessWidget {
  const _WalletHeroCard({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B168C), Color(0xFF241638), Color(0xFFE0A83A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: isArabic ? null : -8,
            left: isArabic ? -8 : null,
            top: -20,
            child: Icon(
              Icons.account_balance_wallet_rounded,
              size: 110,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Column(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  isArabic
                      ? '\u0645\u062d\u0641\u0638\u0629 \u0633\u0647\u0631\u0648\u062f'
                      : 'SrOOd Wallet',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isArabic
                    ? '\u0631\u0635\u064a\u062f\u0643 \u0648\u0623\u0631\u0628\u0627\u062d\u0643 \u0628\u0645\u0643\u0627\u0646 \u0648\u0627\u062d\u062f'
                    : 'Your balance and earnings in one place',
                textAlign: textAlign,
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? '\u0627\u0644\u0634\u062d\u0646\u060c \u0627\u0644\u0647\u062f\u0627\u064a\u0627\u060c \u0627\u0644\u062f\u062e\u0644\u060c \u0648\u0627\u0644\u0633\u062d\u0628 \u0633\u062a\u0643\u062a\u0645\u0644 \u0628\u0645\u0631\u0627\u062d\u0644 \u0645\u0642\u0628\u0644\u0629.'
                    : 'Top up, gifts, income, and cashout will be completed in upcoming phases.',
                textAlign: textAlign,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletStatCard extends StatelessWidget {
  const _WalletStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.highlighted,
    required this.isArabic,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool highlighted;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlighted
              ? const [Color(0xFF3A174F), Color(0xFF241638)]
              : const [Color(0xFF171125), Color(0xFF12091D)],
        ),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFF0C15A)
              : const Color(0xFF4A3470),
        ),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: highlighted
                ? const Color(0xFFF0C15A)
                : const Color(0xFFD8CFEA),
            size: 28,
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFFD8CFEA),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9E91B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletActionPanel extends StatelessWidget {
  const _WalletActionPanel({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return _WalletPanel(
      title: isArabic
          ? '\u0625\u062c\u0631\u0627\u0621\u0627\u062a \u0633\u0631\u064a\u0639\u0629'
          : 'Quick Actions',
      subtitle: isArabic
          ? '\u0647\u0630\u0647 \u0627\u0644\u0645\u064a\u0632\u0627\u062a \u0633\u062a\u062a\u0641\u0639\u0644 \u0644\u0627\u062d\u0642\u0627\u064b.'
          : 'These features will be enabled later.',
      isArabic: isArabic,
      child: Column(
        children: [
          _WalletActionRow(
            icon: Icons.add_card_rounded,
            title: isArabic
                ? '\u0634\u062d\u0646 \u0639\u0645\u0644\u0627\u062a'
                : 'Top up coins',
            subtitle: isArabic
                ? '\u0634\u062d\u0646 \u0639\u0628\u0631 \u0625\u062f\u0627\u0631\u0629 \u0623\u0648 \u0648\u0643\u0627\u0644\u0629'
                : 'Recharge through admin or agency',
            isArabic: isArabic,
          ),
          _WalletActionRow(
            icon: Icons.payments_rounded,
            title: isArabic
                ? '\u0637\u0644\u0628 \u0633\u062d\u0628'
                : 'Request cashout',
            subtitle: isArabic
                ? '\u0633\u062d\u0628 \u0627\u0644\u062f\u062e\u0644 \u0644\u0627\u062d\u0642\u0627\u064b'
                : 'Withdraw income later',
            isArabic: isArabic,
          ),
          _WalletActionRow(
            icon: Icons.card_giftcard_rounded,
            title: isArabic
                ? '\u0627\u0644\u0647\u062f\u0627\u064a\u0627'
                : 'Gifts',
            subtitle: isArabic
                ? '\u0633\u062c\u0644 \u0627\u0644\u0647\u062f\u0627\u064a\u0627 \u0627\u0644\u0645\u0631\u0633\u0644\u0629 \u0648\u0627\u0644\u0645\u0633\u062a\u0644\u0645\u0629'
                : 'Sent and received gift history',
            isArabic: isArabic,
          ),
        ],
      ),
    );
  }
}

class _WalletHistoryPanel extends StatelessWidget {
  const _WalletHistoryPanel({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return _WalletPanel(
      title: isArabic ? '\u0627\u0644\u0633\u062c\u0644' : 'History',
      subtitle: isArabic
          ? '\u0633\u064a\u0638\u0647\u0631 \u0633\u062c\u0644 \u0627\u0644\u0634\u062d\u0646 \u0648\u0627\u0644\u0647\u062f\u0627\u064a\u0627 \u0647\u0646\u0627.'
          : 'Recharge and gift history will appear here.',
      isArabic: isArabic,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B102B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF4A3470)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFFF0C15A),
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0633\u062c\u0644 \u0628\u0639\u062f'
                  : 'No history yet',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              isArabic
                  ? '\u0633\u0646\u0636\u064a\u0641 \u0633\u062c\u0644 \u0627\u0644\u0639\u0645\u0644\u064a\u0627\u062a \u0639\u0646\u062f \u062a\u0641\u0639\u064a\u0644 \u0627\u0644\u0634\u062d\u0646 \u0648\u0627\u0644\u0647\u062f\u0627\u064a\u0627.'
                  : 'Transaction history will appear after top up and gifts are enabled.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletPanel extends StatelessWidget {
  const _WalletPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.isArabic,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            title,
            textAlign: textAlign,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: textAlign,
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _WalletActionRow extends StatelessWidget {
  const _WalletActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isArabic,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Text(
                  title,
                  textAlign: textAlign,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: textAlign,
                  style: const TextStyle(
                    color: Color(0xFFD8CFEA),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9E91B8)),
        ],
      ),
    );
  }
}
