import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'core/config/app_config.dart';
import 'core/config/supabase_config.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/vip/services/vip_service.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/splash/splash_screen.dart';
import 'shared/widgets/app_viewport.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Explicitly initialise the WebRTC engine with voice processing enabled
  // (bypassVoiceProcessing: false is the default, but being explicit here
  // ensures Android sets AudioMode.COMMUNICATION before the first room join,
  // which activates hardware AEC / noise suppression on the device).
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await LiveKitClient.initialize(bypassVoiceProcessing: false);
  }

  // TODO(white-label): Replace SroodLiveConfig() with the client-specific
  // config before calling runApp(), e.g.:
  //   AppConfig.configure(const MyClientConfig());
  AppConfig.configure(const SroodLiveConfig());

  // Explicitly register the WebView platform - skipped on web where dart:io
  // Platform is unavailable and WebView runs natively in the browser.
  if (!kIsWeb) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      WebViewPlatform.instance = WebKitWebViewPlatform();
    }
  }

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    VipService().init();
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
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.isConfigured) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        _onAuthStateChange,
      );
    }
  }

  void _onAuthStateChange(AuthState state) {
    if (state.event != AuthChangeEvent.signedOut) return;
    debugPrint('[RootAuth] signedOut detected — navigating to onboarding');
    // Use addPostFrameCallback so we never mutate the navigator mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) {
        debugPrint('[RootAuth] rootNavigatorKey.currentState is null — skipping');
        return;
      }
      debugPrint('[RootAuth] navigating to onboarding');
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
        (_) => false,
      );
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

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
        navigatorKey: rootNavigatorKey,
        title: AppConfig.instance.appDisplayName,
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

