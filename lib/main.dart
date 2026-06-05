import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/splash/splash_screen.dart';
import 'shared/widgets/app_viewport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  runApp(const SrOOdLiveApp());
}

class SrOOdLiveApp extends StatefulWidget {
  const SrOOdLiveApp({super.key});

  @override
  State<SrOOdLiveApp> createState() => _SrOOdLiveAppState();
}

class _SrOOdLiveAppState extends State<SrOOdLiveApp> {
  Locale locale = const Locale('en');

  void setLocale(Locale newLocale) {
    setState(() {
      locale = newLocale;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialRouteName =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final initialUri = Uri.base;
    final isAdminEntrypoint =
        initialUri.path.startsWith('/admin') ||
        initialUri.fragment.startsWith('/admin') ||
        initialRouteName.startsWith('/admin');

    return AppLanguageController(
      locale: locale,
      setLocale: setLocale,
      child: MaterialApp(
        title: 'SrOOd Live',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return Directionality(
            textDirection: locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: isAdminEntrypoint
                ? child ?? const SizedBox.shrink()
                : AppViewport(child: child ?? const SizedBox.shrink()),
          );
        },
        onGenerateRoute: (settings) {
          if (isAdminEntrypoint) {
            return MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/admin'),
              builder: (_) =>
                  AdminDashboardScreen(isArabic: locale.languageCode == 'ar'),
            );
          }

          return MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/'),
            builder: (_) => const SplashScreen(),
          );
        },
      ),
    );
  }
}

class AppLanguageController extends InheritedWidget {
  const AppLanguageController({
    required this.locale,
    required this.setLocale,
    required super.child,
    super.key,
  });

  final Locale locale;
  final void Function(Locale locale) setLocale;

  static AppLanguageController of(BuildContext context) {
    final controller = context
        .dependOnInheritedWidgetOfExactType<AppLanguageController>();

    if (controller == null) {
      throw FlutterError('AppLanguageController not found');
    }

    return controller;
  }

  @override
  bool updateShouldNotify(AppLanguageController oldWidget) {
    return oldWidget.locale != locale;
  }
}
