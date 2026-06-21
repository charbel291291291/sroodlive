import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../main.dart';
import '../home/home_screen.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  String? message;

  bool _isArabic(BuildContext context) {
    return AppLanguageController.of(context).locale.languageCode == 'ar';
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<bool> _isCurrentUserBanned() async {
    final client = SupabaseService.requiredClient;
    final user = client.auth.currentUser;

    if (user == null) return false;

    final profile = await client
        .from('profiles')
        .select('is_banned')
        .eq('id', user.id)
        .maybeSingle();

    return profile?['is_banned'] == true;
  }

  Future<void> _login() async {
    final isArabic = _isArabic(context);

    setState(() {
      isLoading = true;
      message = null;
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        setState(() {
          message = isArabic
              ? '\u0627\u0643\u062a\u0628 \u0627\u0644\u0628\u0631\u064a\u062f \u0627\u0644\u0625\u0644\u0643\u062a\u0631\u0648\u0646\u064a \u0648\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u0623\u0648\u0644\u0627.'
              : 'Enter email and password first.';
        });
        return;
      }

      if (password.length < 6) {
        setState(() {
          message = isArabic
              ? '\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u064a\u062c\u0628 \u0623\u0646 \u062a\u0643\u0648\u0646 6 \u0623\u062d\u0631\u0641 \u0623\u0648 \u0623\u0643\u062b\u0631.'
              : 'Password must be 6 characters or more.';
        });
        return;
      }

      await SupabaseService.requiredClient.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final isBanned = await _isCurrentUserBanned();

      if (isBanned) {
        await SupabaseService.requiredClient.auth.signOut();

        if (!mounted) return;

        setState(() {
          message = isArabic
              ? '\u062a\u0645 \u062d\u0638\u0631 \u0647\u0630\u0627 \u0627\u0644\u062d\u0633\u0627\u0628.'
              : 'This account is banned.';
        });

        return;
      }

      if (!mounted) return;

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on AuthException catch (error) {
      setState(() {
        message = isArabic
            ? '\u0641\u0634\u0644 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644: ${error.message}'
            : 'Login failed: ${error.message}';
      });
    } catch (error) {
      setState(() {
        message = isArabic
            ? '\u0641\u0634\u0644 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644: $error'
            : 'Login failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          isArabic ? '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644' : 'Login',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_bg.webp',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
          // Deeper overlay so form text stays readable
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
                final topSpacing = constraints.maxHeight < 560 ? 20.0 : 56.0;
                final bottomSpacing = constraints.maxHeight < 560 ? 20.0 : 40.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    24 + keyboardInset,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: topSpacing),

                            // Subtitle under the Srood Live watermark \u2014 soft,
                            // centered, the only header copy on the page.
                            Text(
                              isArabic
                                  ? '\u0627\u062f\u062e\u0644 \u0625\u0644\u0649 \u0639\u0627\u0644\u0645 Srood Live'
                                  : 'Enter your Srood Live world',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFFBCAED6)
                                    .withValues(alpha: 0.82),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 36),

                            // Email field
                            _AuthField(
                              controller: emailController,
                              label: isArabic ? '\u0627\u0644\u0628\u0631\u064a\u062f \u0627\u0644\u0625\u0644\u0643\u062a\u0631\u0648\u0646\u064a' : 'Email',
                              icon: Icons.email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              isArabic: isArabic,
                            ),
                            const SizedBox(height: 14),

                            // Password field
                            _AuthField(
                              controller: passwordController,
                              label: isArabic ? '\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631' : 'Password',
                              icon: Icons.lock_rounded,
                              obscureText: true,
                              isArabic: isArabic,
                            ),

                            // Error / info message
                            if (message != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                message!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFD6A84F),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),

                            // Primary: Sign In
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF0C15A),
                                  foregroundColor: const Color(0xFF0A0612),
                                  disabledBackgroundColor: const Color(
                                    0xFFF0C15A,
                                  ).withValues(alpha: 0.38),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: isLoading ? null : _login,
                                child: Text(
                                  isLoading
                                      ? (isArabic ? '\u0627\u0646\u062a\u0638\u0631...' : 'Loading...')
                                      : (isArabic ? '\u062f\u062e\u0648\u0644' : 'Sign In'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Secondary: Create Account
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFF0C15A),
                                  side: BorderSide(
                                    color: const Color(
                                      0xFFF0C15A,
                                    ).withValues(alpha: 0.65),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: isLoading
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const RegistrationScreen(),
                                        ),
                                      ),
                                child: Text(
                                  isArabic ? '\u0625\u0646\u0634\u0627\u0621 \u062d\u0633\u0627\u0628' : 'Create Account',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: bottomSpacing),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isArabic,
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isArabic;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    const borderRadius = 18.0;
    const gold = Color(0xFFF0C15A);
    const lavender = Color(0xFFBCAED6);
    final fillColor = const Color(0xFF160B26).withValues(alpha: 0.72);
    final borderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.38);

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: lavender,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: const TextStyle(
          color: gold,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: gold, size: 20),
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
      ),
    );
  }
}
