import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../main.dart';
import '../../shared/branding/branding_assets.dart';
import '../home/home_screen.dart';

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
        .single();

    return profile['is_banned'] == true;
  }

  Future<void> _login() async {
    final isArabic = _isArabic(context);

    setState(() {
      isLoading = true;
      message = null;
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

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
          message = isArabic ? '\u062a\u0645 \u062d\u0638\u0631 \u0647\u0630\u0627 \u0627\u0644\u062d\u0633\u0627\u0628.' : 'This account is banned.';
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

  Future<void> _createAccount() async {
    final isArabic = _isArabic(context);

    setState(() {
      isLoading = true;
      message = null;
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

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

      await SupabaseService.requiredClient.auth.signUp(
        email: email,
        password: password,
      );

      if (!mounted) return;

      setState(() {
        message = isArabic
            ? '\u062a\u0645 \u0625\u0646\u0634\u0627\u0621 \u0627\u0644\u062d\u0633\u0627\u0628. \u0627\u0636\u063a\u0637 \u062f\u062e\u0648\u0644.'
            : 'Account created. Press Login.';
      });
    } on AuthException catch (error) {
      setState(() {
        message = isArabic
            ? '\u0641\u0634\u0644 \u0625\u0646\u0634\u0627\u0621 \u0627\u0644\u062d\u0633\u0627\u0628: ${error.message}'
            : 'Account creation failed: ${error.message}';
      });
    } catch (error) {
      setState(() {
        message = isArabic
            ? '\u0641\u0634\u0644 \u0625\u0646\u0634\u0627\u0621 \u0627\u0644\u062d\u0633\u0627\u0628: $error'
            : 'Account creation failed: $error';
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
      appBar: AppBar(title: Text(isArabic ? '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644' : 'Login')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
            final topSpacing = constraints.maxHeight < 560 ? 24.0 : 78.0;
            final bottomSpacing = constraints.maxHeight < 560 ? 20.0 : 54.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + keyboardInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      crossAxisAlignment: isArabic
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: topSpacing),
                        Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 118,
                            height: 118,
                            child: Image.asset(
                              BrandingAssets.owlMark,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 64,
                                    color: Color(0xFFF0C15A),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isArabic ? '\u0627\u062f\u062e\u0644 \u0625\u0644\u0649 SrOOd Live' : 'Enter SrOOd Live',
                          textAlign: isArabic
                              ? TextAlign.right
                              : TextAlign.left,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isArabic
                              ? '\u0633\u062c\u0644 \u062f\u062e\u0648\u0644\u0643 \u0623\u0648 \u0623\u0646\u0634\u0626 \u062d\u0633\u0627\u0628\u0627 \u0644\u0644\u062a\u062c\u0631\u0628\u0629.'
                              : 'Login or create a test account.',
                          textAlign: isArabic
                              ? TextAlign.right
                              : TextAlign.left,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: Color(0xFFB8B8C7),
                          ),
                        ),
                        const SizedBox(height: 28),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: isArabic ? '\u0627\u0644\u0628\u0631\u064a\u062f \u0627\u0644\u0625\u0644\u0643\u062a\u0631\u0648\u0646\u064a' : 'Email',
                            prefixIcon: const Icon(Icons.email_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          textDirection: isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: isArabic ? '\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631' : 'Password',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (message != null)
                          Text(
                            message!,
                            textAlign: isArabic
                                ? TextAlign.right
                                : TextAlign.left,
                            style: const TextStyle(
                              color: Color(0xFFD6A84F),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            onPressed: isLoading ? null : _login,
                            child: Text(
                              isLoading
                                  ? (isArabic ? '\u0627\u0646\u062a\u0638\u0631...' : 'Loading...')
                                  : (isArabic ? '\u062f\u062e\u0648\u0644' : 'Login'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: isLoading ? null : _createAccount,
                            child: Text(
                              isArabic ? '\u0625\u0646\u0634\u0627\u0621 \u062d\u0633\u0627\u0628' : 'Create account',
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
    );
  }
}
