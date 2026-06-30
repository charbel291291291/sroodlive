import 'package:flutter/material.dart';
import 'package:srood_live/shared/utils/error_utils.dart';
import '../../core/supabase/supabase_service.dart';
import '../home/home_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    required this.isArabic,
    this.displayName = '',
    super.key,
  });

  final bool isArabic;
  final String displayName;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  int _step = 0;
  bool _isLoading = false;

  final _bioController = TextEditingController();
  String? _selectedGender;
  final List<String> _selectedInterests = [];
  String? _avatarUrl;

  static const List<String> _genders = ['male', 'female', 'other'];
  static const List<Map<String, dynamic>> _interests = [
    {
      'key': 'music',
      'en': 'Music',
      'ar': 'موسيقى',
      'icon': Icons.music_note_rounded,
    },
    {
      'key': 'gaming',
      'en': 'Gaming',
      'ar': 'ألعاب',
      'icon': Icons.sports_esports_rounded,
    },
    {
      'key': 'sports',
      'en': 'Sports',
      'ar': 'رياضة',
      'icon': Icons.sports_soccer_rounded,
    },
    {'key': 'art', 'en': 'Art', 'ar': 'فن', 'icon': Icons.palette_rounded},
    {
      'key': 'cooking',
      'en': 'Cooking',
      'ar': 'طبخ',
      'icon': Icons.restaurant_rounded,
    },
    {
      'key': 'travel',
      'en': 'Travel',
      'ar': 'سفر',
      'icon': Icons.flight_rounded,
    },
    {
      'key': 'fitness',
      'en': 'Fitness',
      'ar': 'لياقة',
      'icon': Icons.fitness_center_rounded,
    },
    {
      'key': 'comedy',
      'en': 'Comedy',
      'ar': 'كوميديا',
      'icon': Icons.sentiment_very_satisfied_rounded,
    },
    {
      'key': 'education',
      'en': 'Education',
      'ar': 'تعليم',
      'icon': Icons.school_rounded,
    },
    {
      'key': 'fashion',
      'en': 'Fashion',
      'ar': 'موضة',
      'icon': Icons.checkroom_rounded,
    },
  ];

  bool get _isArabic => context.isArabic;

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.requiredClient.auth.currentUser;
      if (user == null) return;

      await SupabaseService.requiredClient.from('profiles').upsert({
        'id': user.id,
        'bio': _bioController.text.trim(),
        'gender': _selectedGender,
        'interests': _selectedInterests,
        if (_avatarUrl != null) 'avatar_url': _avatarUrl,
      });

      if (!mounted) return;

      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e, st) {
      debugError('ProfileSetupScreen._saveProfile', e, st);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _skip() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            children: [
              _buildProgress(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _buildStep(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (i) {
              final active = i <= _step;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: active
                        ? const Color(0xFF8B26D9)
                        : const Color(0xFF2A1840),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _isArabic ? 'الخطوة ${_step + 1} من 3' : 'Step ${_step + 1} of 3',
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      0 => _buildAvatarStep(),
      1 => _buildBioGenderStep(),
      _ => _buildInterestsStep(),
    };
  }

  Widget _buildAvatarStep() {
    final isArabic = _isArabic;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Text(
            isArabic
                ? '👋 مرحباً ${widget.displayName}!'
                : '👋 Welcome, ${widget.displayName}!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            isArabic
                ? 'أضف صورة شخصية لتميّز حسابك'
                : 'Add a profile photo to stand out',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFBCAED6),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () {
              // Photo picker - handled by image_picker in full impl
            },
            child: Stack(
              children: [
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF241638),
                    border: Border.all(
                      color: const Color(0xFF8B26D9),
                      width: 2.5,
                    ),
                  ),
                  child: _avatarUrl != null
                      ? ClipOval(
                          child: Image.network(
                            _avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.person_rounded,
                              size: 60,
                              color: Color(0xFF9E91B8),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          size: 64,
                          color: Color(0xFF9E91B8),
                        ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B26D9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF08060F),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic ? 'اضغط لاختيار صورة' : 'Tap to choose a photo',
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 56),
          _buildBottomButtons(
            onNext: () => setState(() => _step = 1),
            onSkip: () => setState(() => _step = 1),
            isArabic: isArabic,
          ),
        ],
      ),
    );
  }

  Widget _buildBioGenderStep() {
    final isArabic = _isArabic;
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    final crossAxis = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: crossAxis,
        children: [
          const SizedBox(height: 10),
          Text(
            isArabic ? 'عرّف عن نفسك' : 'Tell us about yourself',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'أضف وصفاً مختصراً وحدد جنسك'
                : 'Add a short bio and select your gender',
            style: const TextStyle(
              color: Color(0xFFBCAED6),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            isArabic ? 'نبذة عني' : 'Bio',
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 150,
            textDirection: dir,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: isArabic
                  ? 'اكتب شيئاً عن نفسك...'
                  : 'Write something about yourself...',
              hintStyle: const TextStyle(color: Color(0xFF6E5A8A)),
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
                borderSide: const BorderSide(
                  color: Color(0xFF8B26D9),
                  width: 1.5,
                ),
              ),
              counterStyle: const TextStyle(
                color: Color(0xFF6E5A8A),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            isArabic ? 'الجنس' : 'Gender',
            style: const TextStyle(
              color: Color(0xFFD8CFEA),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            textDirection: dir,
            children: _genders.map((g) {
              final label = isArabic
                  ? (g == 'male'
                        ? 'ذكر'
                        : g == 'female'
                        ? 'أنثى'
                        : 'آخر')
                  : (g == 'male'
                        ? 'Male'
                        : g == 'female'
                        ? 'Female'
                        : 'Other');
              final selected = _selectedGender == g;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedGender = g),
                  child: Container(
                    margin: EdgeInsets.only(
                      right: isArabic ? 0 : (g != 'other' ? 8 : 0),
                      left: isArabic ? (g != 'other' ? 8 : 0) : 0,
                    ),
                    height: 48,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3A174F)
                          : const Color(0xFF160B24),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF8B26D9)
                            : const Color(0xFF4A3470),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFFBCAED6),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
          _buildBottomButtons(
            onNext: () => setState(() => _step = 2),
            onSkip: () => setState(() => _step = 2),
            isArabic: isArabic,
          ),
        ],
      ),
    );
  }

  Widget _buildInterestsStep() {
    final isArabic = _isArabic;
    final crossAxis = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: crossAxis,
        children: [
          const SizedBox(height: 10),
          Text(
            isArabic ? 'اختر اهتماماتك' : 'Pick your interests',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'اختر ما يناسبك لنعرض لك المحتوى المناسب'
                : 'Choose what you like to see relevant content',
            style: const TextStyle(
              color: Color(0xFFBCAED6),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _interests.map((interest) {
              final key = interest['key'] as String;
              final label = isArabic
                  ? interest['ar'] as String
                  : interest['en'] as String;
              final icon = interest['icon'] as IconData;
              final selected = _selectedInterests.contains(key);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedInterests.remove(key);
                    } else {
                      _selectedInterests.add(key);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF3A174F)
                        : const Color(0xFF160B24),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF8B26D9)
                          : const Color(0xFF4A3470),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: selected
                            ? const Color(0xFFF0C15A)
                            : const Color(0xFF9E91B8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFFBCAED6),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _isLoading ? null : _saveProfile,
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
                      isArabic ? 'ابدأ الاستكشاف' : 'Start exploring',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _skip,
              child: Text(
                isArabic ? 'تخطي الآن' : 'Skip for now',
                style: const TextStyle(
                  color: Color(0xFF9E91B8),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons({
    required VoidCallback onNext,
    required VoidCallback onSkip,
    required bool isArabic,
  }) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B26D9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(
              isArabic ? 'التالي' : 'Continue',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onSkip,
          child: Text(
            isArabic ? 'تخطي' : 'Skip',
            style: const TextStyle(
              color: Color(0xFF9E91B8),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
