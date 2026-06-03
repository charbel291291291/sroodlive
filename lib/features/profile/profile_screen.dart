import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../onboarding/onboarding_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final usernameController = TextEditingController();
  final displayNameController = TextEditingController();
  final birthDateController = TextEditingController();
  final bioController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;
  bool isUploadingAvatar = false;
  String? errorMessage;
  String? successMessage;
  Map<String, dynamic>? profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    usernameController.dispose();
    displayNameController.dispose();
    birthDateController.dispose();
    bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;

      if (user == null) {
        setState(() {
          isLoading = false;
          errorMessage = widget.isArabic
              ? 'Ù„Ø§ ÙŠÙˆØ¬Ø¯ Ù…Ø³ØªØ®Ø¯Ù… Ù…Ø³Ø¬Ù„.'
              : 'No logged-in user found.';
        });
        return;
      }

      final data = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      usernameController.text = data['username']?.toString() ?? '';
      displayNameController.text = data['display_name']?.toString() ?? '';
      birthDateController.text = data['date_of_birth']?.toString() ?? '';
      bioController.text = data['bio']?.toString() ?? '';

      setState(() {
        profile = data;
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
        errorMessage = widget.isArabic
            ? 'ÙØ´Ù„ ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ: $error'
            : 'Failed to load profile: $error';
      });
    }
  }

  String _avatarExtension(String fileName, String? mimeType) {
    final lowerName = fileName.toLowerCase();

    if (lowerName.endsWith('.png') || mimeType == 'image/png') {
      return 'png';
    }

    if (lowerName.endsWith('.webp') || mimeType == 'image/webp') {
      return 'webp';
    }

    if (lowerName.endsWith('.gif') || mimeType == 'image/gif') {
      return 'gif';
    }

    return 'jpg';
  }

  String _avatarContentType(String extension, String? mimeType) {
    if (mimeType != null && mimeType.startsWith('image/')) {
      return mimeType;
    }

    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  Future<void> _uploadAvatar() async {
    final isArabic = widget.isArabic;

    setState(() {
      isUploadingAvatar = true;
      errorMessage = null;
      successMessage = null;
    });

    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;

      if (user == null) {
        throw StateError('No logged-in user found.');
      }

      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 900,
        maxHeight: 900,
      );

      if (image == null) {
        return;
      }

      final Uint8List bytes = await image.readAsBytes();
      final extension = _avatarExtension(image.name, image.mimeType);
      final path =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final contentType = _avatarContentType(extension, image.mimeType);

      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

      final publicUrl = client.storage.from('avatars').getPublicUrl(path);
      final versionedUrl =
          '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await client
          .from('profiles')
          .update({
            'avatar_url': versionedUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      await _loadProfile();

      setState(() {
        successMessage = isArabic
            ? '\u062a\u0645 \u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0635\u0648\u0631\u0629.'
            : 'Profile image updated.';
      });
    } catch (error) {
      setState(() {
        errorMessage = isArabic
            ? '\u0641\u0634\u0644 \u0631\u0641\u0639 \u0627\u0644\u0635\u0648\u0631\u0629: $error'
            : 'Image upload failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          isUploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final existingValue = birthDateController.text.trim();
    final initialDate =
        DateTime.tryParse(existingValue) ??
        DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1940),
      lastDate: now,
    );

    if (picked == null) {
      return;
    }

    birthDateController.text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveProfile() async {
    final isArabic = widget.isArabic;
    final currentUsername = usernameController.text.trim();
    final displayName = displayNameController.text.trim();
    final dateOfBirth = birthDateController.text.trim();
    final bio = bioController.text.trim();

    if (displayName.length < 2) {
      setState(() {
        successMessage = null;
        errorMessage = isArabic
            ? '\u0627\u0644\u0644\u0642\u0628 \u064a\u062c\u0628 \u0623\u0646 \u064a\u0643\u0648\u0646 \u062d\u0631\u0641\u064a\u0646 \u0623\u0648 \u0623\u0643\u062b\u0631.'
            : 'Nickname must be 2 characters or more.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
      successMessage = null;
    });

    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;

      if (user == null) {
        throw StateError('No logged-in user found.');
      }

      final values = {
        'username': currentUsername.isEmpty ? displayName : currentUsername,
        'display_name': displayName,
        'date_of_birth': dateOfBirth.isEmpty ? null : dateOfBirth,
        'bio': bio.isEmpty ? null : bio,
        'updated_at': DateTime.now().toIso8601String(),
      };

      try {
        await client.from('profiles').update(values).eq('id', user.id);
      } catch (error) {
        final message = error.toString();

        if (!message.contains('date_of_birth') && !message.contains('bio')) {
          rethrow;
        }

        await client
            .from('profiles')
            .update({
              'username': currentUsername.isEmpty
                  ? displayName
                  : currentUsername,
              'display_name': displayName,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);
      }

      await _loadProfile();

      setState(() {
        successMessage = isArabic
            ? '\u062a\u0645 \u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641 \u0627\u0644\u0634\u062e\u0635\u064a.'
            : 'Profile saved.';
      });
    } catch (error) {
      setState(() {
        errorMessage = isArabic
            ? '\u0641\u0634\u0644 \u0627\u0644\u062d\u0641\u0638: $error'
            : 'Save failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    if (isLoading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }

    final email = profile?['email']?.toString() ?? '-';
    final avatarUrl = profile?['avatar_url']?.toString();
    final publicUserId = profile?['public_user_id']?.toString() ?? '-';
    final role = profile?['role']?.toString() ?? 'user';
    final coins = profile?['coins_balance']?.toString() ?? '0';
    final vipLevel = profile?['vip_level']?.toString() ?? '0';
    final diamonds = profile?['diamonds_balance']?.toString() ?? '0';
    final income = profile?['income_balance']?.toString() ?? '0';
    final agency = profile?['agency_name']?.toString() ?? '-';
    final displayName = displayNameController.text.trim().isNotEmpty
        ? displayNameController.text.trim()
        : (usernameController.text.trim().isNotEmpty
              ? usernameController.text.trim()
              : (isArabic
                    ? '\u0639\u0636\u0648 \u0633\u0647\u0631\u0648\u062f'
                    : 'SrOOd Member'));

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 120),
          child: Column(
            crossAxisAlignment: isArabic
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                isArabic
                    ? '\u0627\u0644\u0645\u0644\u0641 \u0627\u0644\u0634\u062e\u0635\u064a'
                    : 'Profile',
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? '\u0623\u062f\u0631 \u0645\u0644\u0641\u0643\u060c \u0631\u0635\u064a\u062f\u0643\u060c \u0648\u0645\u0643\u0627\u0646\u062a\u0643 \u062f\u0627\u062e\u0644 \u0633\u0647\u0631\u0648\u062f.'
                    : 'Manage your profile, balance, and status inside SrOOd.',
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: Color(0xFFD8CFEA),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              _ProfileHeroCard(
                displayName: displayName,
                email: email,
                avatarUrl: avatarUrl,
                publicUserId: publicUserId,
                role: role,
                vipLevel: vipLevel,
                isUploadingAvatar: isUploadingAvatar,
                isArabic: isArabic,
                onAvatarTap: _uploadAvatar,
              ),
              const SizedBox(height: 18),
              _ProfileWalletGrid(
                coins: coins,
                diamonds: diamonds,
                income: income,
                agency: agency,
                isArabic: isArabic,
              ),
              const SizedBox(height: 18),
              _ProfileSectionCard(
                title: isArabic
                    ? '\u062a\u0639\u062f\u064a\u0644 \u0627\u0644\u0645\u0644\u0641'
                    : 'Edit Profile',
                subtitle: isArabic
                    ? '\u062d\u062f\u062b \u0644\u0642\u0628\u0643\u060c \u062a\u0627\u0631\u064a\u062e \u0645\u064a\u0644\u0627\u062f\u0643\u060c \u0648\u0627\u0644\u0646\u0628\u0630\u0629.'
                    : 'Update your nickname, date of birth, and bio.',
                isArabic: isArabic,
                child: Column(
                  children: [
                    _ProfileInput(
                      controller: displayNameController,
                      label: isArabic
                          ? '\u0627\u0644\u0644\u0642\u0628'
                          : 'Nickname',
                      isArabic: isArabic,
                    ),
                    _ProfileInput(
                      controller: birthDateController,
                      label: isArabic
                          ? '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0645\u064a\u0644\u0627\u062f'
                          : 'Date of birth',
                      isArabic: isArabic,
                      readOnly: true,
                      onTap: _pickBirthDate,
                    ),
                    _ProfileInput(
                      controller: bioController,
                      label: isArabic
                          ? '\u0627\u0644\u0646\u0628\u0630\u0629'
                          : 'Bio',
                      isArabic: isArabic,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: isSaving ? null : _saveProfile,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(
                          isSaving
                              ? (isArabic
                                    ? '\u062c\u0627\u0631 \u0627\u0644\u062d\u0641\u0638...'
                                    : 'Saving...')
                              : (isArabic
                                    ? '\u062d\u0641\u0638 \u0627\u0644\u062a\u063a\u064a\u064a\u0631\u0627\u062a'
                                    : 'Save changes'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 14),
                _ProfileNotice(
                  message: errorMessage!,
                  isSuccess: false,
                  isArabic: isArabic,
                ),
              ],
              if (successMessage != null) ...[
                const SizedBox(height: 14),
                _ProfileNotice(
                  message: successMessage!,
                  isSuccess: true,
                  isArabic: isArabic,
                ),
              ],
              const SizedBox(height: 18),
              _ProfileSectionCard(
                title: isArabic
                    ? '\u0645\u0639\u0644\u0648\u0645\u0627\u062a \u0627\u0644\u062d\u0633\u0627\u0628'
                    : 'Account Info',
                subtitle: isArabic
                    ? '\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062d\u0633\u0627\u0628 \u0627\u0644\u0623\u0633\u0627\u0633\u064a\u0629.'
                    : 'Your basic account information.',
                isArabic: isArabic,
                child: Column(
                  children: [
                    _ProfileCard(
                      label: isArabic
                          ? '\u0631\u0642\u0645 \u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645'
                          : 'User ID',
                      value: publicUserId,
                      icon: Icons.badge_rounded,
                      isArabic: isArabic,
                    ),
                    _ProfileCard(
                      label: isArabic
                          ? '\u0627\u0644\u0628\u0631\u064a\u062f'
                          : 'Email',
                      value: email,
                      icon: Icons.email_rounded,
                      isArabic: isArabic,
                    ),
                    _ProfileCard(
                      label: isArabic
                          ? '\u0627\u0644\u062f\u0648\u0631'
                          : 'Role',
                      value: role,
                      icon: Icons.verified_user_rounded,
                      isArabic: isArabic,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await SupabaseService.requiredClient.auth.signOut();

                    if (!context.mounted) return;

                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(),
                      ),
                      (_) => false,
                    );
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(
                    isArabic
                        ? '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c'
                        : 'Logout',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.publicUserId,
    required this.role,
    required this.vipLevel,
    required this.isUploadingAvatar,
    required this.isArabic,
    required this.onAvatarTap,
  });

  final String displayName;
  final String email;
  final String? avatarUrl;
  final String publicUserId;
  final String role;
  final String vipLevel;
  final bool isUploadingAvatar;
  final bool isArabic;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B168C), Color(0xFF241638), Color(0xFFE0A83A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: isUploadingAvatar ? null : onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _ProfileAvatar(
                  avatarUrl: avatarUrl,
                  size: 76,
                  isUploading: isUploadingAvatar,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF0C15A),
                      border: Border.all(
                        color: const Color(0xFF241638),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      isUploadingAvatar
                          ? Icons.hourglass_top_rounded
                          : Icons.camera_alt_rounded,
                      size: 15,
                      color: const Color(0xFF160B26),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Text(
                  displayName,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.80),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ProfileBadge(
                      icon: Icons.badge_rounded,
                      label: publicUserId,
                      highlighted: true,
                    ),
                    _ProfileBadge(
                      icon: Icons.diamond_rounded,
                      label: 'VIP $vipLevel',
                      highlighted: false,
                    ),
                    _ProfileBadge(
                      icon: Icons.admin_panel_settings_rounded,
                      label: role,
                      highlighted: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
    required this.icon,
    required this.label,
    required this.highlighted,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFF0C15A)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: highlighted ? const Color(0xFFF0C15A) : Colors.white,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: highlighted ? const Color(0xFFF0C15A) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.avatarUrl,
    required this.size,
    required this.isUploading,
  });

  final String? avatarUrl;
  final double size;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.4,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 40,
                );
              },
            )
          else
            const Icon(Icons.person_rounded, color: Colors.white, size: 40),
          if (isUploading)
            Container(
              color: Colors.black.withValues(alpha: 0.42),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileWalletGrid extends StatelessWidget {
  const _ProfileWalletGrid({
    required this.coins,
    required this.diamonds,
    required this.income,
    required this.agency,
    required this.isArabic,
  });

  final String coins;
  final String diamonds;
  final String income;
  final String agency;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Expanded(
              child: _ProfileStatCard(
                icon: Icons.monetization_on_rounded,
                label: isArabic
                    ? '\u0627\u0644\u0639\u0645\u0644\u0627\u062a'
                    : 'Coins',
                value: coins,
                highlighted: true,
                isArabic: isArabic,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ProfileStatCard(
                icon: Icons.diamond_rounded,
                label: isArabic
                    ? '\u0627\u0644\u0623\u0644\u0645\u0627\u0633'
                    : 'Diamonds',
                value: diamonds,
                highlighted: false,
                isArabic: isArabic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Expanded(
              child: _ProfileStatCard(
                icon: Icons.account_balance_wallet_rounded,
                label: isArabic ? '\u0627\u0644\u062f\u062e\u0644' : 'Income',
                value: income,
                highlighted: false,
                isArabic: isArabic,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ProfileStatCard(
                icon: Icons.groups_rounded,
                label: isArabic
                    ? '\u0627\u0644\u0648\u0643\u0627\u0644\u0629'
                    : 'Agency',
                value: agency,
                highlighted: false,
                isArabic: isArabic,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  const _ProfileStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.highlighted,
    required this.isArabic,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlighted;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlighted
              ? const [Color(0xFF3A174F), Color(0xFF241638)]
              : const [Color(0xFF171125), Color(0xFF12091D)],
        ),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFF0C15A)
              : const Color(0xFF4A3470),
        ),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: highlighted
                ? const Color(0xFFF0C15A)
                : const Color(0xFFD8CFEA),
            size: 28,
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFFD8CFEA),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.isArabic,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            title,
            textAlign: textAlign,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: textAlign,
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ProfileNotice extends StatelessWidget {
  const _ProfileNotice({
    required this.message,
    required this.isSuccess,
    required this.isArabic,
  });

  final String message;
  final bool isSuccess;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSuccess
            ? const Color(0xFF2ECC71).withValues(alpha: 0.12)
            : const Color(0xFFFF5C7A).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSuccess ? const Color(0xFF2ECC71) : const Color(0xFFFF5C7A),
        ),
      ),
      child: Text(
        message,
        textAlign: isArabic ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: isSuccess ? const Color(0xFF2ECC71) : const Color(0xFFFF5C7A),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileInput extends StatelessWidget {
  const _ProfileInput({
    required this.controller,
    required this.label,
    required this.isArabic,
    this.readOnly = false,
    this.onTap,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool isArabic;
  final bool readOnly;
  final VoidCallback? onTap;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isArabic,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xFFD8CFEA),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
