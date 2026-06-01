import 'package:flutter/material.dart';
import '../../core/supabase/supabase_service.dart';
import '../onboarding/onboarding_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.isArabic,
    super.key,
  });

  final bool isArabic;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;

      if (user == null) {
        setState(() {
          isLoading = false;
          errorMessage = widget.isArabic
              ? 'لا يوجد مستخدم مسجل.'
              : 'No logged-in user found.';
        });
        return;
      }

      final data = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      setState(() {
        profile = data;
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
        errorMessage = widget.isArabic
            ? 'فشل تحميل الملف الشخصي: $error'
            : 'Failed to load profile: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    if (isLoading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final username = profile?['username']?.toString() ?? '-';
    final email = profile?['email']?.toString() ?? '-';
    final role = profile?['role']?.toString() ?? 'user';
    final coins = profile?['coins_balance']?.toString() ?? '0';
    final vipLevel = profile?['vip_level']?.toString() ?? '0';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment:
              isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الملف الشخصي' : 'Profile',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'بياناتك الأساسية من Supabase.'
                  : 'Your basic data from Supabase.',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFB8B8C7),
              ),
            ),
            const SizedBox(height: 24),
            if (errorMessage != null)
              Text(
                errorMessage!,
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  color: Color(0xFFD6A84F),
                  fontWeight: FontWeight.w700,
                ),
              )
            else ...[
              _ProfileCard(
                label: isArabic ? 'اسم المستخدم' : 'Username',
                value: username,
                isArabic: isArabic,
              ),
              _ProfileCard(
                label: isArabic ? 'البريد' : 'Email',
                value: email,
                isArabic: isArabic,
              ),
              _ProfileCard(
                label: isArabic ? 'الدور' : 'Role',
                value: role,
                isArabic: isArabic,
              ),
              _ProfileCard(
                label: isArabic ? 'العملات' : 'Coins',
                value: coins,
                isArabic: isArabic,
              ),
              _ProfileCard(
                label: isArabic ? 'مستوى VIP' : 'VIP Level',
                value: vipLevel,
                isArabic: isArabic,
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await SupabaseService.requiredClient.auth.signOut();

                  if (!context.mounted) return;

                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const OnboardingScreen(),
                    ),
                    (_) => false,
                  );
                },
                icon: const Icon(Icons.logout_rounded),
                label: Text(isArabic ? 'تسجيل الخروج' : 'Logout'),
              ),
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.label,
    required this.value,
    required this.isArabic,
  });

  final String label;
  final String value;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14141F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF2B2B3A),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFFB8B8C7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
