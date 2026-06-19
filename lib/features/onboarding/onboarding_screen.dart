import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../main.dart';
import '../../shared/branding/branding_assets.dart';
import '../auth/login_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  bool _isArabic(BuildContext context) {
    return AppLanguageController.of(context).locale.languageCode == 'ar';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic(context);
    final language = AppLanguageController.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('English'),
                    selected: !isArabic,
                    onSelected: (_) {
                      language.setLocale(const Locale('en'));
                    },
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text('العربية'),
                    selected: isArabic,
                    onSelected: (_) {
                      language.setLocale(const Locale('ar'));
                    },
                  ),
                ],
              ),
              const Spacer(),
              Container(
                width: 156,
                height: 156,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB000FF).withValues(alpha: 0.26),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Image.asset(
                  BrandingAssets.appIcon,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFFD6A84F).withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 56,
                      color: Color(0xFFD6A84F),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                isArabic
                    ? 'أهلا بك في ${AppConfig.instance.appDisplayName}'
                    : 'Welcome to ${AppConfig.instance.appDisplayName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isArabic
                    ? 'أنشئ غرف صوتية انضم إلى أصدقائك أرسل الهدايا وابن حضورك المميز.'
                    : 'Create voice rooms, join friends, send gifts, and build your live prestige.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Color(0xFFB8B8C7),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  child: Text(
                    isArabic ? 'ابدأ الآن' : 'Get Started',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isArabic
                    ? 'إعداد نسخة ${AppConfig.instance.appDisplayName} التجريبية'
                    : '${AppConfig.instance.appDisplayName} beta setup',
                style: const TextStyle(fontSize: 13, color: Color(0xFF77778A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
