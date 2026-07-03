import 'package:flutter/material.dart';

import '../../../core/auth/safe_logout.dart';
import '../../../core/update/app_update_dialog.dart';
import '../../../core/update/app_update_service.dart';
import '../../../main.dart';
import '../../calls/screens/call_history_screen.dart';
import '../../discovery/screens/discovery_screen.dart';
import '../../gifts/screens/gift_catalog_screen.dart';
import '../../games/screens/spin_wheel_screen.dart';
import '../../gifts/screens/gift_history_screen.dart';
import '../../rooms/screens/room_schedule_screen.dart';
import '../../social/screens/leaderboard_screen.dart';
import '../../host/screens/availability_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../onboarding/onboarding_screen.dart';
import '../../social/screens/block_user_screen.dart';
import '../../wallet/screens/transaction_history_screen.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../wallet/screens/withdrawal_screen.dart';
import '../models/profile_hub_models.dart';
import '../services/settings_service.dart';
import '../widgets/profile_hub_widgets.dart';
import 'delete_account_screen.dart';
import 'my_level_screen.dart';
import 'policy_screen.dart';
import 'preferences_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

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
  bool _isLoggingOut = false;
  final Set<String> _savingKeys = <String>{};

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

  Future<bool> _update(
    Map<String, dynamic> values, {
    required List<String> keys,
  }) async {
    if (keys.any(_savingKeys.contains)) return false;
    setState(() {
      _savingKeys.addAll(keys);
    });

    try {
      final settings = await _service.updateSettings(values);
      if (!mounted) return false;
      setState(() {
        _settings = settings;
        _future = Future.value(settings);
      });
      return true;
    } catch (e) {
      debugPrint('[Settings._update] failed: $e');
      if (!mounted) return false;
      SroodToast.show(context, context.isArabic ? 'تعذر حفظ الإعداد. حاول مرة أخرى.' : 'Could not save setting. Please try again.', type: SroodToastType.error);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _savingKeys.removeAll(keys);
        });
      }
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await const AppUpdateService().checkForUpdate();
    if (!mounted) return;
    if (info == null) {
      SroodToast.show(context, widget.isArabic ? 'التطبيق محدّث بالفعل' : 'App is up to date', type: SroodToastType.info);
      return;
    }
    await showAppUpdateDialog(context, info: info, isArabic: widget.isArabic);
  }

  Future<bool> _confirmAction(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool isDanger = true,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF141720),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              body,
              style: const TextStyle(color: Color(0xFF9E91B8)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(color: Color(0xFF9E91B8)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  confirmLabel,
                  style: TextStyle(
                    color: isDanger
                        ? const Color(0xFFEF4444)
                        : const Color(0xFFF0C15A),
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final isArabic = context.isArabic;
    final ok = await _confirmAction(
      context,
      title: isArabic ? 'تسجيل الخروج' : 'Logout',
      body: isArabic
          ? 'هل تريد تسجيل الخروج من حسابك؟'
          : 'Are you sure you want to log out?',
      confirmLabel: isArabic ? 'خروج' : 'Logout',
    );
    if (!ok || !mounted) return;
    setState(() => _isLoggingOut = true);
    debugPrint('[SettingsLogout] logout pressed');

    try {
      await SafeLogout.run();
      // Navigation is handled by the root-level auth listener in main.dart
      // (_SrOOdLiveAppState._onAuthStateChange). We wait briefly to let it fire;
      // if it hasn't navigated yet we fall back here.
      debugPrint(
        '[SettingsLogout] SafeLogout done — root auth listener will navigate',
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      // Fallback: root listener may not have fired yet (e.g. in tests or edge cases).
      final nav = rootNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        debugPrint('[SettingsLogout] fallback navigation triggered');
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      debugPrint('[SettingsLogout] SafeLogout threw: $e');
      if (mounted) {
        setState(() => _isLoggingOut = false);
        SroodToast.show(context, widget.isArabic ? 'فشل تسجيل الخروج. حاول مجددًا.' : 'Sign out failed. Please try again.', type: SroodToastType.error);
      }
    }
  }

  void _openPolicy(String key, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PolicyScreen(
          title: title,
          body: policyBody(key, context.isArabic),
          isArabic: context.isArabic,
        ),
      ),
    );
  }

  String _visibilityLabel(String value, bool isArabic) {
    return switch (value) {
      'public' => isArabic ? 'عام' : 'Public',
      'friends' => isArabic ? 'الأصدقاء فقط' : 'Friends only',
      'private' => isArabic ? 'خاص' : 'Private',
      _ => value,
    };
  }

  Future<void> _showProfileVisibilityPicker(UserSettings settings) async {
    final isArabic = context.isArabic;
    final next = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: profileHubCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final options =
            <({String key, IconData icon, String title, String body})>[
              (
                key: 'public',
                icon: Icons.public_rounded,
                title: isArabic ? 'عام' : 'Public',
                body: isArabic
                    ? 'يمكن للجميع رؤية ملفك.'
                    : 'Everyone can view your profile.',
              ),
              (
                key: 'friends',
                icon: Icons.group_rounded,
                title: isArabic ? 'الأصدقاء فقط' : 'Friends only',
                body: isArabic
                    ? 'يظهر ملفك للأصدقاء والمتابعين المسموحين.'
                    : 'Visible to friends and allowed connections.',
              ),
              (
                key: 'private',
                icon: Icons.lock_rounded,
                title: isArabic ? 'خاص' : 'Private',
                body: isArabic
                    ? 'تقليل ظهور ملفك للآخرين.'
                    : 'Limit profile visibility to others.',
              ),
            ];

        return SafeArea(
          child: Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: profileHubBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: isArabic
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Text(
                      isArabic ? 'ظهور الملف' : 'Profile visibility',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...options.map((option) {
                    final selected =
                        option.key == settings.privacyProfileVisibility;
                    return Semantics(
                      label: option.title,
                      button: true,
                      enabled: true,
                      selected: selected,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).pop(option.key),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? profileHubGold.withValues(alpha: 0.12)
                                  : const Color(0xFF1A0D2A),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? profileHubGold
                                    : profileHubBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  option.icon,
                                  color: profileHubGold,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: isArabic
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        option.body,
                                        style: const TextStyle(
                                          color: profileHubMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: profileHubGold,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (next == null || next == settings.privacyProfileVisibility || !mounted) {
      return;
    }

    await _update(
      {'privacy_profile_visibility': next},
      keys: const ['privacy_profile_visibility'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

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
                  onTap: () async {
                    final next = settings.language == 'ar' ? 'en' : 'ar';
                    final ok = await _update(
                      {'language': next},
                      keys: const ['language'],
                    );
                    if (ok && mounted) language.setLocale(Locale(next));
                  },
                ),
                SettingsToggleTile(
                  icon: Icons.notifications_active_rounded,
                  title: isArabic ? 'إشعارات الدفع' : 'Push notifications',
                  subtitle: isArabic
                      ? 'تفعيل إشعارات الجهاز'
                      : 'System-level notification alerts',
                  value: settings.notificationsEnabled,
                  isArabic: isArabic,
                  isEnabled: !_savingKeys.contains('notifications_enabled'),
                  onChanged: (value) => _update(
                    {'notifications_enabled': value},
                    keys: const ['notifications_enabled'],
                  ),
                ),
                SettingsToggleTile(
                  icon: Icons.meeting_room_rounded,
                  title: isArabic ? 'دعوات الغرف' : 'Room invites',
                  value: settings.roomInvitesEnabled,
                  isArabic: isArabic,
                  isEnabled: !_savingKeys.contains('room_invites_enabled'),
                  onChanged: (value) => _update(
                    {'room_invites_enabled': value},
                    keys: const ['room_invites_enabled'],
                  ),
                ),
                SettingsToggleTile(
                  icon: Icons.card_giftcard_rounded,
                  title: isArabic ? 'إشعارات الهدايا' : 'Gift notifications',
                  value: settings.giftNotificationsEnabled,
                  isArabic: isArabic,
                  isEnabled: !_savingKeys.contains(
                    'gift_notifications_enabled',
                  ),
                  onChanged: (value) => _update(
                    {'gift_notifications_enabled': value},
                    keys: const ['gift_notifications_enabled'],
                  ),
                ),
                SettingsToggleTile(
                  icon: Icons.online_prediction_rounded,
                  title: isArabic ? 'إظهار الحالة' : 'Show online status',
                  value: settings.privacyShowOnline,
                  isArabic: isArabic,
                  isEnabled: !_savingKeys.contains('privacy_show_online'),
                  onChanged: (value) => _update(
                    {'privacy_show_online': value},
                    keys: const ['privacy_show_online'],
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.visibility_rounded,
                  title: isArabic ? 'ظهور الملف' : 'Profile visibility',
                  subtitle: _visibilityLabel(
                    settings.privacyProfileVisibility,
                    isArabic,
                  ),
                  isArabic: isArabic,
                  isEnabled: !_savingKeys.contains(
                    'privacy_profile_visibility',
                  ),
                  onTap: () => _showProfileVisibilityPicker(settings),
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
                  title: isArabic ? 'الاستكشاف والنشاط' : 'Discover & Activity',
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
                  title: isArabic ? 'الغرف والبث المباشر' : 'Rooms & Live',
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
                  title: isArabic ? 'الألعاب والهدايا' : 'Games & Gifts',
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
                  title: isArabic ? 'المحفظة والأرباح' : 'Wallet & Earnings',
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

                // Host & Agency actions moved to the Me page (ProfileScreen) —
                // see _HostAgencySection there. Settings no longer routes to the
                // agency/host flow.

                // ── 6. Social ────────────────────────────────────────────
                ProfileSectionTitle(
                  title: isArabic ? 'التواصل والخصوصية' : 'Social & Privacy',
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
                  title: isArabic ? 'المستخدمون المحظورون' : 'Blocked users',
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
                  title: isArabic ? 'التفضيلات' : 'Preferences',
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
                      builder: (_) => const PreferencesScreen(),
                    ),
                  ),
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'التطبيق' : 'App',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.trending_up_rounded,
                  title: isArabic ? 'مستواي' : 'My level',
                  subtitle: isArabic
                      ? 'XP والتقدم والألقاب'
                      : 'XP, progress and titles',
                  isArabic: isArabic,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MyLevelScreen(isArabic: isArabic),
                    ),
                  ),
                ),
                ProfileMenuItem(
                  icon: Icons.system_update_rounded,
                  title: isArabic ? 'التحقق من التحديثات' : 'Check for update',
                  subtitle: isArabic
                      ? 'تحقق من وجود إصدار جديد'
                      : 'Check if a newer version is available',
                  isArabic: isArabic,
                  onTap: _checkForUpdate,
                ),
                ProfileSectionTitle(
                  title: isArabic ? 'الخروج' : 'Session',
                  isArabic: isArabic,
                ),
                ProfileMenuItem(
                  icon: Icons.logout_rounded,
                  title: isArabic ? 'تسجيل الخروج' : 'Logout',
                  isArabic: isArabic,
                  isEnabled: !_isLoggingOut,
                  trailing: _isLoggingOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _logout,
                ),
                // Store-required in-app account deletion (Google Play User Data
                // policy / Apple 5.1.1(v)). Routes to a dedicated confirm screen.
                ProfileMenuItem(
                  icon: Icons.delete_forever_rounded,
                  title: isArabic ? 'حذف الحساب' : 'Delete Account',
                  isArabic: isArabic,
                  isEnabled: !_isLoggingOut,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DeleteAccountScreen(isArabic: isArabic),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
