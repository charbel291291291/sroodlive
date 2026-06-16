import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/supabase/supabase_service.dart';
import '../../shared/branding/branding_assets.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? message;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future<void>.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final client = SupabaseService.client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
      return;
    }

    try {
      final profile = await client
          .from('profiles')
          .select('is_banned')
          .eq('id', user.id)
          .maybeSingle();

      final isBanned = profile?['is_banned'] == true;

      if (!mounted) return;

      if (isBanned) {
        await client.auth.signOut();

        setState(() {
          message = 'Your account is banned.';
        });

        await Future<void>.delayed(const Duration(seconds: 2));

        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );

        return;
      }

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (_) {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF08080B), Color(0xFF11111A), Color(0xFF08080B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Image.asset(
                BrandingAssets.logoWide,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.mic_rounded,
                  size: 72,
                  color: Color(0xFFD6A84F),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              message ?? 'Voice rooms. Gifts. Prestige.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFFB8B8C7)),
            ),
          ],
        ),
      ),
    );
  }
}
