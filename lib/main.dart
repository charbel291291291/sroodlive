import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'shared/widgets/app_viewport.dart';

void main() {
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
    return AppLanguageController(
      locale: locale,
      setLocale: setLocale,
      child: MaterialApp(
        title: 'SrOOd Live',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        locale: locale,
        supportedLocales: const [
          Locale('en'),
          Locale('ar'),
        ],
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
            child: AppViewport(
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: const SplashScreen(),
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
    final controller =
        context.dependOnInheritedWidgetOfExactType<AppLanguageController>();

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
