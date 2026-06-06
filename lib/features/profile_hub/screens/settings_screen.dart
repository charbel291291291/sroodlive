import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../main.dart';
import '../../onboarding/onboarding_screen.dart';
import '../models/profile_hub_models.dart';
import '../services/settings_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _service = const SettingsService();
  late Future<UserSettings> _future;
  UserSettings? _settings;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<UserSettings> _load() async {
    final settings = await _service.getMySettings();
    _settings = settings;
    return settings;
  }

  void _retry() => setState(() => _future = _load());

  Future<void> _update(Map<String, dynamic> values) async {
    final settings = await _service.updateSettings(values);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _future = Future.value(settings);
    });
  }

  Future<void> _logout() async {
    await SupabaseService.requiredClient.auth.signOut(
      scope: SignOutScope.local,
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (_) => false,
    );
  }

  void _openPolicy(String key, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PolicyScreen(
          title: title,
          body: policyBody(key, widget.isArabic),
          isArabic: widget.isArabic,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    return ProfileHubScaffold(
      title: isArabic ? 'الإعدادات' : 'Settings',
      isArabic: isArabic,
      children: [
        FutureBuilder<UserSettings>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError && _settings == null) {
              return ProfileErrorState(
                message: snapshot.error.toString(),
                onRetry: _retry,
                isArabic: isArabic,
              );
            }

            final settings = _settings ?? snapshot.data!;
            final language = AppLanguageController.of(context);

            return Column(
              children: [
                ProfileSectionTitle(
                  title: isArabic ? 'الحساب' : 'Account',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.language_rounded,
                  title: isArabic ? 'اللغة' : 'Language',
                  subtitle: settings.language == 'ar' ? 'العربية' : 'English',
                  isArabic: isArabic,
                  onTap: () {
                    final next = settings.language == 'ar' ? 'en' : 'ar';
                    language.setLocale(Locale(next));
                    _update({'language': next});
                  },
                ),
                SettingsToggleTile(
                  title: isArabic ? 'الإشعارات' : 'Notifications',
                  value: settings.notificationsEnabled,
                  isArabic: isArabic,
                  onChanged: (value) =>
                      _update({'notifications_enabled': value}),
                ),
                SettingsToggleTile(
                  title: isArabic ? 'دعوات الغرف' : 'Room invites',
                  value: settings.roomInvitesEnabled,
                  isArabic: isArabic,
                  onChanged: (value) =>
                      _update({'room_invites_enabled': value}),
                ),
                SettingsToggleTile(
                  title: isArabic ? 'إشعارات الهدايا' : 'Gift notifications',
                  value: settings.giftNotificationsEnabled,
                  isArabic: isArabic,
                  onChanged: (value) =>
                      _update({'gift_notifications_enabled': value}),
                ),
                SettingsToggleTile(
                  title: isArabic ? 'إظهار الحالة' : 'Show online status',
                  value: settings.privacyShowOnline,
                  isArabic: isArabic,
                  onChanged: (value) => _update({'privacy_show_online': value}),
                ),
                ProfileMenuItem(
                  icon: Icons.visibility_rounded,
                  title: isArabic ? 'ظهور الملف' : 'Profile visibility',
                  subtitle: settings.privacyProfileVisibility,
                  isArabic: isArabic,
                  onTap: () {
                    final next = switch (settings.privacyProfileVisibility) {
                      'public' => 'friends',
                      'friends' => 'private',
                      _ => 'public',
                    };
                    _update({'privacy_profile_visibility': next});
                  },
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'السياسات' : 'Policies',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.rule_rounded,
                  title: isArabic ? 'قواعد المجتمع' : 'Community Rules',
                  isArabic: isArabic,
                  onTap: () => _openPolicy(
                    'community',
                    isArabic ? 'قواعد المجتمع' : 'Community Rules',
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.monetization_on_rounded,
                  title: isArabic ? 'سياسة العملات' : 'Coin Policy',
                  isArabic: isArabic,
                  onTap: () => _openPolicy(
                    'coin',
                    isArabic ? 'سياسة العملات' : 'Coin Policy',
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.workspace_premium_rounded,
                  title: isArabic ? 'سياسة VIP' : 'VIP Policy',
                  isArabic: isArabic,
                  onTap: () =>
                      _openPolicy('vip', isArabic ? 'سياسة VIP' : 'VIP Policy'),
                ),
                ProfileMenuItem(
                  icon: Icons.card_giftcard_rounded,
                  title: isArabic ? 'سياسة الهدايا' : 'Gift Policy',
                  isArabic: isArabic,
                  onTap: () => _openPolicy(
                    'gift',
                    isArabic ? 'سياسة الهدايا' : 'Gift Policy',
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.groups_rounded,
                  title: isArabic ? 'سياسة الوكالات' : 'Agency Policy',
                  isArabic: isArabic,
                  onTap: () => _openPolicy(
                    'agency',
                    isArabic ? 'سياسة الوكالات' : 'Agency Policy',
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.payments_rounded,
                  title: isArabic
                      ? 'سياسة الدخل والسحب'
                      : 'Income and Payout Policy',
                  isArabic: isArabic,
                  onTap: () => _openPolicy(
                    'income',
                    isArabic
                        ? 'سياسة الدخل والسحب'
                        : 'Income and Payout Policy',
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.privacy_tip_rounded,
                  title: isArabic ? 'سياسة الخصوصية' : 'Privacy Policy',
                  isArabic: isArabic,
                  onTap: () => _openPolicy(
                    'privacy',
                    isArabic ? 'سياسة الخصوصية' : 'Privacy Policy',
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.description_rounded,
                  title: isArabic ? 'شروط الاستخدام' : 'Terms of Use',
                  isArabic: isArabic,
                  onTap: () => _openPolicy(
                    'terms',
                    isArabic ? 'شروط الاستخدام' : 'Terms of Use',
                  ),
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'الخروج' : 'Session',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.logout_rounded,
                  title: isArabic ? 'تسجيل الخروج' : 'Logout',
                  isArabic: isArabic,
                  onTap: _logout,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
