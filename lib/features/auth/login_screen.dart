import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../main.dart';
import '../home/home_screen.dart';
import 'legal_screens.dart';
import 'presentation/srood_auth_background.dart';
import 'presentation/srood_auth_buttons.dart';
import 'presentation/srood_auth_fields.dart';
import 'presentation/srood_login_header.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool isLoading = false;

  /// Banner message for auth/network/ban errors (never raw backend text).
  String? message;

  // Inline validation presentation for the existing rules.
  String? _emailError;
  String? _passwordError;
  bool _obscurePassword = true;

  bool _isArabic(BuildContext context) {
    return AppLanguageController.of(context).locale.languageCode == 'ar';
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
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

  /// Maps backend auth failures to readable user messages — presentation
  /// only; the underlying errors and auth behavior are unchanged.
  String _friendlyAuthMessage(String rawMessage, bool isArabic) {
    final raw = rawMessage.toLowerCase();
    if (raw.contains('invalid login credentials') ||
        raw.contains('invalid_credentials') ||
        raw.contains('invalid email or password')) {
      return isArabic
          ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة.'
          : 'Incorrect email or password.';
    }
    if (raw.contains('email not confirmed')) {
      return isArabic
          ? 'يرجى تأكيد بريدك الإلكتروني أولاً.'
          : 'Please confirm your email first.';
    }
    if (raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('connection') ||
        raw.contains('timed out') ||
        raw.contains('failed host lookup')) {
      return isArabic
          ? 'تعذر الاتصال. تحقق من الإنترنت وحاول مجدداً.'
          : 'Connection problem. Check your internet and try again.';
    }
    return isArabic
        ? 'فشل تسجيل الدخول. حاول مرة أخرى.'
        : 'Sign in failed. Please try again.';
  }

  Future<void> _login() async {
    // Guard against duplicate sign-in requests.
    if (isLoading) return;
    FocusScope.of(context).unfocus();
    final isArabic = _isArabic(context);

    setState(() {
      message = null;
      _emailError = null;
      _passwordError = null;
    });

    final email = emailController.text.trim();
    final password = passwordController.text;

    // Same validation rules as before — presented inline per field.
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        if (email.isEmpty) {
          _emailError = isArabic
              ? 'اكتب البريد الإلكتروني.'
              : 'Enter your email.';
        }
        if (password.isEmpty) {
          _passwordError = isArabic
              ? 'اكتب كلمة المرور.'
              : 'Enter your password.';
        }
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _passwordError = isArabic
            ? 'كلمة المرور يجب أن تكون 6 أحرف أو أكثر.'
            : 'Password must be 6 characters or more.';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
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
      if (!mounted) return;
      setState(() {
        message = _friendlyAuthMessage(error.message, isArabic);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        message = _friendlyAuthMessage(error.toString(), isArabic);
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _openRegistration() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RegistrationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        // Close the keyboard when tapping outside the form.
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            const Positioned.fill(child: SroodAuthBackground()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final shortScreen = constraints.maxHeight < 620;
                  final brandGap = shortScreen ? 14.0 : 28.0;

                  return Column(
                    children: [
                      SroodLoginHeader(isArabic: isArabic),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            shortScreen ? 8 : 20,
                            20,
                            20 + keyboardInset,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 430),
                              child: AutofillGroup(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SroodLoginBrand(isArabic: isArabic),
                                    SizedBox(height: brandGap),

                                    // ── Form card ─────────────────────────
                                    SroodLoginFormCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SroodAuthTextField(
                                            controller: emailController,
                                            label: isArabic
                                                ? 'البريد الإلكتروني'
                                                : 'Email',
                                            icon: Icons.email_rounded,
                                            isArabic: isArabic,
                                            errorText: _emailError,
                                            enabled: !isLoading,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            autofillHints: const [
                                              AutofillHints.email,
                                            ],
                                            textInputAction:
                                                TextInputAction.next,
                                            focusNode: _emailFocus,
                                            onSubmitted: (_) =>
                                                _passwordFocus.requestFocus(),
                                          ),
                                          const SizedBox(height: 12),
                                          SroodPasswordField(
                                            controller: passwordController,
                                            label: isArabic
                                                ? 'كلمة المرور'
                                                : 'Password',
                                            isArabic: isArabic,
                                            errorText: _passwordError,
                                            enabled: !isLoading,
                                            obscured: _obscurePassword,
                                            onToggleVisibility: () =>
                                                setState(() {
                                                  _obscurePassword =
                                                      !_obscurePassword;
                                                }),
                                            focusNode: _passwordFocus,
                                            onSubmitted: (_) => _login(),
                                          ),

                                          // ── Auth error banner ───────────
                                          if (message != null) ...[
                                            const SizedBox(height: 12),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFFFF7A7A,
                                                ).withValues(alpha: 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFFF7A7A,
                                                  ).withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.error_outline_rounded,
                                                    color: Color(0xFFFF9A9A),
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      message!,
                                                      textAlign: isArabic
                                                          ? TextAlign.right
                                                          : TextAlign.left,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFFFFB4B4,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 12.5,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 18),

                                          // ── Sign In ─────────────────────
                                          SroodPrimaryAuthButton(
                                            label: isArabic
                                                ? 'دخول'
                                                : 'Sign In',
                                            icon: Icons.login_rounded,
                                            loading: isLoading,
                                            onPressed: isLoading
                                                ? null
                                                : _login,
                                          ),
                                          const SizedBox(height: 14),

                                          // ── Create Account ──────────────
                                          SroodSecondaryAuthButton(
                                            label: isArabic
                                                ? 'إنشاء حساب'
                                                : 'Create Account',
                                            icon:
                                                Icons.person_add_alt_1_rounded,
                                            onPressed: isLoading
                                                ? null
                                                : _openRegistration,
                                          ),
                                        ],
                                      ),
                                    ),

                                    // ── Legal footer (existing nav) ───────
                                    LegalFooter(isArabic: isArabic),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
