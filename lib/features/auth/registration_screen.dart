import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../main.dart';
import '../../shared/branding/branding_assets.dart';
import 'profile_setup_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  bool get _isArabic =>
      AppLanguageController.of(context).locale.languageCode == 'ar';

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await SupabaseService.requiredClient.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {
          'display_name': _nameController.text.trim(),
          'username': _usernameController.text.trim().toLowerCase(),
        },
      );

      if (!mounted) return;

      if (response.user != null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ProfileSetupScreen(
              isArabic: _isArabic,
              displayName: _nameController.text.trim(),
            ),
          ),
        );
      } else {
        setState(() {
          _error = _isArabic
              ? 'فشل إنشاء الحساب. حاول مجدداً.'
              : 'Account creation failed. Try again.';
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _error = _isArabic ? 'خطأ: ${e.message}' : 'Error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _error = _isArabic ? 'خطأ غير متوقع.' : 'Unexpected error.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic;
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxis = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: crossAxis,
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      textDirection: dir,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            isArabic
                                ? Icons.arrow_forward_rounded
                                : Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: Image.asset(
                          BrandingAssets.owlMark,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person_add_rounded,
                            size: 54,
                            color: Color(0xFFF0C15A),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isArabic ? 'إنشاء حساب جديد' : 'Create account',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isArabic
                          ? 'انضم إلى SrOOd Live وابدأ البث المباشر.'
                          : 'Join SrOOd Live and start streaming.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFBCAED6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildField(
                      controller: _nameController,
                      label: isArabic ? 'الاسم الكامل' : 'Full name',
                      icon: Icons.person_rounded,
                      dir: dir,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? (isArabic ? 'مطلوب' : 'Required')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _usernameController,
                      label: isArabic ? 'اسم المستخدم' : 'Username',
                      icon: Icons.alternate_email_rounded,
                      dir: TextDirection.ltr,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return isArabic ? 'مطلوب' : 'Required';
                        }
                        if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(v.trim())) {
                          return isArabic
                              ? '3-20 حرف (أحرف إنجليزية صغيرة، أرقام، _)'
                              : '3-20 chars: lowercase letters, digits, _';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _emailController,
                      label: isArabic ? 'البريد الإلكتروني' : 'Email',
                      icon: Icons.email_rounded,
                      dir: TextDirection.ltr,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return isArabic ? 'مطلوب' : 'Required';
                        }
                        if (!v.contains('@')) {
                          return isArabic ? 'بريد غير صحيح' : 'Invalid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildPasswordField(
                      controller: _passwordController,
                      label: isArabic ? 'كلمة المرور' : 'Password',
                      obscure: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      dir: dir,
                      validator: (v) {
                        if (v == null || v.length < 6) {
                          return isArabic
                              ? 'على الأقل 6 أحرف'
                              : 'At least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildPasswordField(
                      controller: _confirmController,
                      label: isArabic
                          ? 'تأكيد كلمة المرور'
                          : 'Confirm password',
                      obscure: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      dir: dir,
                      validator: (v) {
                        if (v != _passwordController.text) {
                          return isArabic
                              ? 'كلمات المرور غير متطابقة'
                              : 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A1422),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFFFF6B8A,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _error!,
                          textAlign: textAlign,
                          style: const TextStyle(
                            color: Color(0xFFFF6B8A),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _register,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B26D9),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                isArabic ? 'إنشاء الحساب' : 'Create account',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      textDirection: dir,
                      children: [
                        Text(
                          isArabic
                              ? 'لديك حساب بالفعل؟ '
                              : 'Already have an account? ',
                          style: const TextStyle(
                            color: Color(0xFFBCAED6),
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Text(
                            isArabic ? 'تسجيل الدخول' : 'Log in',
                            style: const TextStyle(
                              color: Color(0xFFF0C15A),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextDirection dir,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textDirection: dir,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      validator: validator,
      decoration: _inputDecoration(label, icon),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required TextDirection dir,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textDirection: dir,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      validator: validator,
      decoration: _inputDecoration(label, Icons.lock_rounded).copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: const Color(0xFF9E91B8),
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF9E91B8)),
      prefixIcon: Icon(icon, color: const Color(0xFF9E91B8)),
      filled: true,
      fillColor: const Color(0xFF160B24),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF4A3470)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF4A3470)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF8B26D9), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFFF6B8A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFFF6B8A), width: 1.5),
      ),
    );
  }
}
