import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../main.dart';
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
              ? 'اكتب البريد الإلكتروني وكلمة المرور أولا.'
              : 'Enter email and password first.';
        });
        return;
      }

      if (password.length < 6) {
        setState(() {
          message = isArabic
              ? 'كلمة المرور يجب أن تكون 6 أحرف أو أكثر.'
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
          message = isArabic ? 'تم حظر هذا الحساب.' : 'This account is banned.';
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
            ? 'فشل تسجيل الدخول: ${error.message}'
            : 'Login failed: ${error.message}';
      });
    } catch (error) {
      setState(() {
        message = isArabic
            ? 'فشل تسجيل الدخول: $error'
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
              ? 'اكتب البريد الإلكتروني وكلمة المرور أولا.'
              : 'Enter email and password first.';
        });
        return;
      }

      if (password.length < 6) {
        setState(() {
          message = isArabic
              ? 'كلمة المرور يجب أن تكون 6 أحرف أو أكثر.'
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
            ? 'تم إنشاء الحساب. اضغط دخول.'
            : 'Account created. Press Login.';
      });
    } on AuthException catch (error) {
      setState(() {
        message = isArabic
            ? 'فشل إنشاء الحساب: ${error.message}'
            : 'Account creation failed: ${error.message}';
      });
    } catch (error) {
      setState(() {
        message = isArabic
            ? 'فشل إنشاء الحساب: $error'
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
      appBar: AppBar(title: Text(isArabic ? 'تسجيل الدخول' : 'Login')),
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
                        Text(
                          isArabic ? 'ادخل إلى SrOOd Live' : 'Enter SrOOd Live',
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
                              ? 'سجل دخولك أو أنشئ حسابا للتجربة.'
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
                            labelText: isArabic ? 'البريد الإلكتروني' : 'Email',
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
                            labelText: isArabic ? 'كلمة المرور' : 'Password',
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
                                  ? (isArabic ? 'انتظر...' : 'Loading...')
                                  : (isArabic ? 'دخول' : 'Login'),
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
                              isArabic ? 'إنشاء حساب' : 'Create account',
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
