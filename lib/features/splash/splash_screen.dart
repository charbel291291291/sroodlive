import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/supabase/supabase_service.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      final client = SupabaseService.client;
      final user = client?.auth.currentUser;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              user == null ? const OnboardingScreen() : const HomeScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF08080B),
              Color(0xFF11111A),
              Color(0xFF08080B),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_rounded,
              size: 72,
              color: Color(0xFFD6A84F),
            ),
            SizedBox(height: 24),
            Text(
              'SrOOd Live',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Voice rooms. Gifts. Prestige.',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFFB8B8C7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
