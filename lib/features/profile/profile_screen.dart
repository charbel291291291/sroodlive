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
  final usernameController = TextEditingController();
  final displayNameController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  String? successMessage;
  Map<String, dynamic>? profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    usernameController.dispose();
    displayNameController.dispose();
    super.dispose();
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

      usernameController.text = data['username']?.toString() ?? '';
      displayNameController.text = data['display_name']?.toString() ?? '';

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

  Future<void> _saveProfile() async {
    final isArabic = widget.isArabic;
    final username = usernameController.text.trim();
    final displayName = displayNameController.text.trim();

    if (username.length < 3) {
      setState(() {
        successMessage = null;
        errorMessage = isArabic
            ? 'اسم المستخدم يجب أن يكون 3 أحرف أو أكثر.'
            : 'Username must be 3 characters or more.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
      successMessage = null;
    });

    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;

      if (user == null) {
        throw StateError('No logged-in user found.');
      }

      await client.from('profiles').update({
        'username': username,
        'display_name': displayName.isEmpty ? username : displayName,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      await _loadProfile();

      setState(() {
        successMessage = isArabic
            ? 'تم حفظ الملف الشخصي.'
            : 'Profile saved.';
      });
    } catch (error) {
      setState(() {
        errorMessage = isArabic
            ? 'فشل الحفظ: $error'
            : 'Save failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
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
                  ? 'عدل اسمك وبياناتك الأساسية.'
                  : 'Edit your name and basic profile data.',
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFB8B8C7),
              ),
            ),
            const SizedBox(height: 24),
            _ProfileInput(
              controller: usernameController,
              label: isArabic ? 'اسم المستخدم' : 'Username',
              isArabic: isArabic,
            ),
            _ProfileInput(
              controller: displayNameController,
              label: isArabic ? 'الاسم الظاهر' : 'Display name',
              isArabic: isArabic,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: isSaving ? null : _saveProfile,
                icon: const Icon(Icons.save_rounded),
                label: Text(
                  isSaving
                      ? (isArabic ? 'جار الحفظ...' : 'Saving...')
                      : (isArabic ? 'حفظ التغييرات' : 'Save changes'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null)
              Text(
                errorMessage!,
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  color: Color(0xFFD6A84F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (successMessage != null)
              Text(
                successMessage!,
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  color: Color(0xFF2ECC71),
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 18),
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

class _ProfileInput extends StatelessWidget {
  const _ProfileInput({
    required this.controller,
    required this.label,
    required this.isArabic,
  });

  final TextEditingController controller;
  final String label;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
