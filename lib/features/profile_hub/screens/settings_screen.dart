import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../main.dart';
import '../../calls/screens/call_history_screen.dart';
import '../../discovery/screens/discovery_screen.dart';
import '../../gifts/screens/gift_catalog_screen.dart';
import '../../games/screens/spin_wheel_screen.dart';
import '../../gifts/screens/gift_history_screen.dart';
import '../../rooms/screens/room_schedule_screen.dart';
import '../../social/screens/leaderboard_screen.dart';
import 'agency_management_screen.dart';
import '../../host/screens/availability_screen.dart';
import '../../host/screens/host_registration_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../onboarding/onboarding_screen.dart';
import '../../social/screens/block_user_screen.dart';
import '../../wallet/screens/transaction_history_screen.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../wallet/screens/withdrawal_screen.dart';
import '../models/profile_hub_models.dart';
import '../services/settings_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'policy_screen.dart';
import 'preferences_screen.dart';

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
                  title: isArabic
                      ? 'إشعارات الدفع'
                      : 'Push notifications',
                  subtitle: isArabic
                      ? 'تفعيل إشعارات الجهاز'
                      : 'System-level notification alerts',
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
                // ── 1. Discover & Activity ──────────────────────────────
                ProfileSectionTitle(
                  title: isArabic
                      ? 'الاستكشاف والنشاط'
                      : 'Discover & Activity',
                  subtitle: isArabic
                      ? 'تصفح، إشعارات، مكالمات'
                      : 'Browse, notifications, call log',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.explore_rounded,
                  title: isArabic ? 'الاستكشاف' : 'Discover',
                  subtitle: isArabic
                      ? 'غرف ومستخدمون مقترحون'
                      : 'Trending rooms and people',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DiscoveryScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.notifications_rounded,
                  title: isArabic ? 'الإشعارات' : 'Notifications',
                  subtitle: isArabic
                      ? 'متابعات، هدايا، أحداث'
                      : 'Follows, gifts, room events',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NotificationsScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.call_rounded,
                  title: isArabic ? 'سجل المكالمات' : 'Call history',
                  subtitle: isArabic
                      ? 'جميع مكالماتك الصوتية'
                      : 'All your audio calls',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CallHistoryScreen(isArabic: isArabic),
                    ),
                  ),
                ),

                // ── 2. Rooms & Live ──────────────────────────────────────
                ProfileSectionTitle(
                  title: isArabic
                      ? 'الغرف والبث المباشر'
                      : 'Rooms & Live',
                  subtitle: isArabic
                      ? 'جدولة الغرف وأوقات التوفر'
                      : 'Room scheduling and availability',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.event_rounded,
                  title: isArabic ? 'جدولة الغرف' : 'Room scheduler',
                  subtitle: isArabic
                      ? 'ابدأ برمجة غرفك مسبقاً'
                      : 'Plan upcoming rooms in advance',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RoomScheduleScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.schedule_rounded,
                  title: isArabic ? 'جدول الإتاحة' : 'Availability schedule',
                  subtitle: isArabic
                      ? 'حدد أوقات بثك كمضيف'
                      : 'Set when you are live as a host',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AvailabilityScreen(isArabic: isArabic),
                    ),
                  ),
                ),

                // ── 3. Games & Gifts ─────────────────────────────────────
                ProfileSectionTitle(
                  title: isArabic
                      ? 'الألعاب والهدايا'
                      : 'Games & Gifts',
                  subtitle: isArabic
                      ? 'عجلة الحظ، متجر الهدايا، سجل الإرسال'
                      : 'Spin wheel, gift catalog, send history',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.casino_rounded,
                  title: isArabic ? 'عجلة الحظ' : 'Spin the wheel',
                  subtitle: isArabic
                      ? 'ادفع عملات واربح جوائز'
                      : 'Spend coins and win prizes',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SpinWheelScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.card_giftcard_rounded,
                  title: isArabic ? 'متجر الهدايا' : 'Gift catalog',
                  subtitle: isArabic
                      ? 'تصفح جميع الهدايا المتاحة'
                      : 'Browse all available gifts',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GiftCatalogScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.redeem_rounded,
                  title: isArabic ? 'سجل الهدايا' : 'Gift history',
                  subtitle: isArabic
                      ? 'الهدايا المرسلة والمستلمة'
                      : 'Sent and received gifts log',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GiftHistoryScreen(isArabic: isArabic),
                    ),
                  ),
                ),

                // ── 4. Wallet & Earnings ─────────────────────────────────
                ProfileSectionTitle(
                  title: isArabic
                      ? 'المحفظة والأرباح'
                      : 'Wallet & Earnings',
                  subtitle: isArabic
                      ? 'شحن، معاملات، سحب'
                      : 'Top up, transactions, cashout',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.monetization_on_rounded,
                  title: isArabic ? 'شراء عملات' : 'Buy coins',
                  subtitle: isArabic
                      ? 'اشحن رصيدك للعب والهدايا'
                      : 'Top up your play balance',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WalletScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.receipt_long_rounded,
                  title: isArabic ? 'سجل المعاملات' : 'Transaction history',
                  subtitle: isArabic
                      ? 'جميع عمليات الشحن والصرف'
                      : 'All recharge and spend activity',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TransactionHistoryScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.payments_rounded,
                  title: isArabic ? 'طلب سحب' : 'Withdraw earnings',
                  subtitle: isArabic
                      ? 'حوّل الألماس إلى دخل حقيقي'
                      : 'Convert diamonds to real income',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WithdrawalScreen(isArabic: isArabic),
                    ),
                  ),
                ),

                // ── 5. Host & Agency ─────────────────────────────────────
                ProfileSectionTitle(
                  title: isArabic
                      ? 'المضيف والوكالة'
                      : 'Host & Agency',
                  subtitle: isArabic
                      ? 'التسجيل، الإدارة، برنامج المضيف'
                      : 'Register, manage, host program',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.live_tv_rounded,
                  title: isArabic ? 'التسجيل كمضيف' : 'Become a host',
                  subtitle: isArabic
                      ? 'انضم لبرنامج المضيفين'
                      : 'Join the host program',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          HostRegistrationScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.groups_rounded,
                  title: isArabic ? 'إدارة الوكالة' : 'Manage agency',
                  subtitle: isArabic
                      ? 'أعضاء الوكالة، الأهداف، الأداء'
                      : 'Agency members, targets, performance',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AgencyManagementScreen(isArabic: isArabic),
                    ),
                  ),
                ),

                // ── 6. Social ────────────────────────────────────────────
                ProfileSectionTitle(
                  title: isArabic
                      ? 'التواصل والخصوصية'
                      : 'Social & Privacy',
                  subtitle: isArabic
                      ? 'متصدرون، محظورون'
                      : 'Leaderboard, blocked users',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.emoji_events_rounded,
                  title: isArabic ? 'المتصدرون' : 'Leaderboard',
                  subtitle: isArabic
                      ? 'أفضل المستخدمين هذا الشهر'
                      : 'Top users this month',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LeaderboardScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.block_rounded,
                  title: isArabic
                      ? 'المستخدمون المحظورون'
                      : 'Blocked users',
                  subtitle: isArabic
                      ? 'عرض وإدارة قائمة الحظر'
                      : 'View and manage your block list',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BlockUserScreen(isArabic: isArabic),
                    ),
                  ),
                ),

                // ── 7. Preferences ───────────────────────────────────────
                ProfileSectionTitle(
                  title: isArabic
                      ? 'التفضيلات'
                      : 'Preferences',
                  subtitle: isArabic
                      ? 'المظهر، الصوت، الخصوصية'
                      : 'Appearance, sounds, privacy',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.tune_rounded,
                  title: isArabic ? 'التفضيلات' : 'Preferences',
                  subtitle: isArabic
                      ? 'خصص تجربتك داخل التطبيق'
                      : 'Customise your in-app experience',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PreferencesScreen(isArabic: isArabic),
                    ),
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
