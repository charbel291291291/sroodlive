import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/auth/safe_logout.dart';
import '../../core/utils/vip_visuals.dart';
import '../../core/vip/vip_frame_layout.dart';
import '../../shared/widgets/avatar_with_frame.dart';
import '../../shared/widgets/gender_chip.dart';
import '../../shared/widgets/premium_ui.dart';
import '../../shared/widgets/vip_badge.dart';
import '../../shared/widgets/vip_username.dart';
import '../profile_hub/screens/customer_service_screen.dart';
import '../profile_hub/screens/settings_screen.dart';
import '../gamification/screens/backpack_screen.dart';
import '../gamification/screens/checkin_screen.dart';
import '../gamification/screens/store_screen.dart';
import '../gamification/screens/vip_center_screen.dart';
import '../wallet/models/wallet.dart';
import '../wallet/screens/wallet_screen.dart';
import '../wallet/services/wallet_service.dart';
import '../rooms/utils/vip_room_features.dart';
import '../rooms/services/rooms_service.dart';
import '../rooms/screens/room_details_screen.dart';
import '../profile_hub/models/profile_hub_models.dart';
import '../profile_hub/screens/my_level_screen.dart';
import '../profile_hub/services/charm_service.dart';
import '../profile_hub/services/level_service.dart';
import '../wealth/services/wealth_service.dart';
import 'models/avatar_frame.dart';
import 'screens/follow_list_screen.dart';
import 'services/follow_service.dart';
import 'widgets/avatar_crop_screen.dart';
import 'widgets/country_picker_sheet.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import 'utils/vip_assets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

const List<AvatarFrame> _fallbackAvatarFrames = [
  AvatarFrame(
    frameKey: 'luxury_ruby_royal',
    name: 'Ruby Royal Frame',
    category: 'luxury',
    assetUrl: 'assets/avatar_frames/luxury_ruby_royal.png',
    sortOrder: 40,
  ),
  AvatarFrame(
    frameKey: 'luxury_ruby_royal_dark',
    name: 'Ruby Royal Dark Frame',
    category: 'luxury',
    assetUrl: 'assets/avatar_frames/luxury_ruby_royal_dark.png',
    sortOrder: 41,
  ),
  AvatarFrame(
    frameKey: 'custom_srood_live',
    name: 'SrOOd Live Frame',
    category: 'vip',
    assetUrl: 'assets/avatar_frames/custom/srood_live_frame_v2.png',
    sortOrder: 42,
  ),
  AvatarFrame(
    frameKey: 'custom_super_admin',
    name: 'Super Admin Frame',
    category: 'vip',
    assetUrl: 'assets/avatar_frames/custom/super_admin_frame_transparent.png',
    sortOrder: 43,
  ),
  AvatarFrame(
    frameKey: 'custom_admin',
    name: 'Admin Frame',
    category: 'vip',
    assetUrl: 'assets/avatar_frames/custom/admin_frame_transparent.png',
    sortOrder: 44,
  ),
  AvatarFrame(
    frameKey: 'custom_luxury_gold',
    name: 'Luxury Gold Frame',
    category: 'luxury',
    assetUrl: 'assets/avatar_frames/custom/luxury_gold_frame_transparent.png',
    sortOrder: 45,
  ),
  AvatarFrame(
    frameKey: 'custom_luxury_diamond',
    name: 'Luxury Diamond Frame',
    category: 'luxury',
    assetUrl:
        'assets/avatar_frames/custom/luxury_diamond_frame_transparent.png',
    sortOrder: 46,
  ),
];

// -----------------------------------------------------------------------------

class _ProfileScreenState extends State<ProfileScreen> {
  final usernameController = TextEditingController();
  final displayNameController = TextEditingController();
  final birthDateController = TextEditingController();
  final bioController = TextEditingController();
  final countryController = TextEditingController();
  final genderController = TextEditingController();
  Country? _selectedCountry;
  final FollowService _followService = const FollowService();
  final WalletService _walletService = const WalletService();

  bool isLoading = true;
  bool isSaving = false;
  bool isUploadingAvatar = false;
  bool _roomLoading = false;
  String? errorMessage;
  String? successMessage;
  Map<String, dynamic>? profile;
  List<AvatarFrame> avatarFrames = const [];
  int followersCount = 0;
  int followingCount = 0;
  int friendsCount = 0;
  int giftsReceivedCount = 0;
  int visitorsCount = 0;
  UserWallet? wallet;
  UserLevel? _userLevel;
  int? _charmLevel;
  int? _wealthLevel;

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
    countryController.dispose();
    genderController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;

      if (user == null) {
        setState(() {
          isLoading = false;
          errorMessage = context.isArabic
              ? 'لا يوجد مستخدم مسجّل.'
              : 'No logged-in user found.';
        });
        return;
      }

      final data =
          (await client
              .from('profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle()) ??
          <String, dynamic>{};
      var frames = _fallbackAvatarFrames;

      try {
        final frameData = await client
            .from('avatar_frames')
            .select(
              'frame_key, name, category, vip_level, asset_url, sort_order',
            )
            .eq('is_active', true)
            .order('sort_order', ascending: true);

        frames = (frameData as List<dynamic>)
            .map((item) => AvatarFrame.fromJson(item as Map<String, dynamic>))
            .where(_hasBundledFrameAsset)
            .toList();

        if (frames.isEmpty) {
          frames = _fallbackAvatarFrames;
        }
      } catch (_) {
        frames = _fallbackAvatarFrames;
      }

      usernameController.text = data['username']?.toString() ?? '';
      displayNameController.text = data['display_name']?.toString() ?? '';
      birthDateController.text = data['date_of_birth']?.toString() ?? '';
      bioController.text = data['bio']?.toString() ?? '';
      countryController.text = data['country']?.toString() ?? '';
      _selectedCountry = countryFromStored(countryController.text);
      genderController.text = data['gender']?.toString() ?? '';

      int followers = 0;
      int following = 0;
      int friends = 0;
      try {
        followers = await _followService.followersCount(user.id);
        following = await _followService.followingCount(user.id);
        friends = await _followService.friendsCount(user.id);
        debugPrint(
          '[FollowStats] followers=$followers following=$following friends=$friends',
        );
      } catch (e) {
        debugPrint('[FollowStats] failed to load follow stats: $e');
      }

      final gifts = await _safeGiftCount(user.id);
      final loadedWallet = await _safeEnsureWallet(user.id);

      UserLevel? loadedLevel;
      try {
        loadedLevel = await const LevelService().getMyLevel();
        debugPrint(
          '[LevelSync] loaded level=${loadedLevel.level} xp=${loadedLevel.xp}',
        );
      } catch (e) {
        debugPrint('[LevelSync] failed to load level: $e');
      }

      // Charm and Wealth levels are secondary — failures never block the screen.
      int? loadedCharmLevel;
      int? loadedWealthLevel;
      await Future.wait([
        () async {
          try {
            loadedCharmLevel =
                (await const CharmService().getMyCharm()).charmLevel;
          } catch (e) {
            debugPrint('[ProfileBadge] charm load failed: $e');
          }
        }(),
        () async {
          try {
            loadedWealthLevel =
                (await const WealthService().getMyWealth()).wealthLevel;
          } catch (e) {
            debugPrint('[ProfileBadge] wealth load failed: $e');
          }
        }(),
      ]);

      setState(() {
        profile = data;
        avatarFrames = frames;
        followersCount = followers;
        followingCount = following;
        friendsCount = friends;
        giftsReceivedCount = _intFromProfile(
          data,
          'gifts_received_count',
          fallback: gifts,
        );
        visitorsCount = _intFromProfile(data, 'visitors_count');
        wallet = loadedWallet;
        _userLevel = loadedLevel;
        _charmLevel = loadedCharmLevel;
        _wealthLevel = loadedWealthLevel;
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
        errorMessage = context.isArabic
            ? 'فشل تحميل الملف الشخصي: $error'
            : 'Failed to load profile: $error';
      });
    }
  }

  int _intFromProfile(
    Map<String, dynamic> data,
    String key, {
    int fallback = 0,
  }) {
    final value = data[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _hasBundledFrameAsset(AvatarFrame frame) {
    return avatarFrameAssetPaths.containsKey(frame.frameKey);
  }

  Future<UserWallet> _safeEnsureWallet(String userId) async {
    try {
      return await _walletService.ensureWallet();
    } catch (_) {
      return UserWallet.empty(userId);
    }
  }

  Future<int> _safeGiftCount(String userId) async {
    try {
      return await SupabaseService.requiredClient
          .from('gift_transactions')
          .count()
          .eq('receiver_id', userId);
    } catch (_) {
      return 0;
    }
  }

  String _profileText(String key, {String fallback = ''}) {
    final value = profile?[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  void _showSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.isArabic ? 'قريباً' : 'Coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openWalletScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletScreen(isArabic: context.isArabic),
      ),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openProfileHub(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _loadProfile();
  }

  Future<void> _openMyRoom() async {
    if (_roomLoading) return;
    setState(() => _roomLoading = true);
    try {
      final roomName = displayNameController.text.trim().isNotEmpty
          ? '${displayNameController.text.trim()}\'s Room'
          : 'My Room';
      final result = await RoomsService().getOrCreateRoom(name: roomName);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              RoomDetailsScreen(room: result.room, isArabic: context.isArabic),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isArabic ? 'فشل فتح الغرفة: $e' : 'Failed to open room: $e',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _roomLoading = false);
    }
  }

  Future<void> _openStore() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoreScreen(isArabic: context.isArabic),
      ),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openCheckin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckinScreen(isArabic: context.isArabic),
      ),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openBackpack() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BackpackScreen(isArabic: context.isArabic),
      ),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openVipCenter() async {
    final expiresAt = DateTime.tryParse(
      profile?['vip_expires_at']?.toString() ?? '',
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VipCenterScreen(
          isArabic: context.isArabic,
          currentVipLevel: _effectiveProfileVipLevel(),
          vipExpiresAt: expiresAt,
        ),
      ),
    );
  }

  Future<void> _openLevels() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyLevelScreen(isArabic: context.isArabic),
      ),
    );
    // Refresh all three levels in case XP was earned while on My Level screen.
    _refreshLevelBadges();
  }

  Future<void> _openWealthCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyLevelScreen(isArabic: context.isArabic),
      ),
    );
    _refreshLevelBadges();
  }

  void _refreshLevelBadges() {
    const LevelService()
        .getMyLevel()
        .then((r) {
          if (mounted) setState(() => _userLevel = r);
        })
        .catchError((_) {});
    const CharmService()
        .getMyCharm()
        .then((r) {
          if (mounted) setState(() => _charmLevel = r.charmLevel);
        })
        .catchError((_) {});
    const WealthService()
        .getMyWealth()
        .then((r) {
          if (mounted) setState(() => _wealthLevel = r.wealthLevel);
        })
        .catchError((_) {});
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12091D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          context.isArabic ? 'تسجيل الخروج' : 'Sign Out',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
          textAlign: context.isArabic ? TextAlign.right : TextAlign.left,
        ),
        content: Text(
          context.isArabic
              ? 'هل أنت متأكد أنك تريد تسجيل الخروج؟'
              : 'Are you sure you want to sign out?',
          style: const TextStyle(color: Color(0xFFBCAED6)),
          textAlign: context.isArabic ? TextAlign.right : TextAlign.left,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              context.isArabic ? 'إلغاء' : 'Cancel',
              style: const TextStyle(color: Color(0xFFBCAED6)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C7A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.isArabic ? 'تسجيل الخروج' : 'Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await SafeLogout.run();
    }
  }

  Future<void> _copyPublicId(String publicUserId) async {
    await Clipboard.setData(ClipboardData(text: publicUserId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.isArabic ? 'تم نسخ المعرّف' : 'ID copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showEditProfileSheet() async {
    const genderOptions = ['male', 'female', 'other'];
    final genderLabelsAr = ['ذكر', 'أنثى', 'آخر'];
    const genderLabelsEn = ['Male', 'Female', 'Other'];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF100718),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final currentGender = genderController.text.trim().toLowerCase();
            final selectedGender = genderOptions.contains(currentGender)
                ? currentGender
                : null;
            // One-time locks (server-enforced; UI mirrors them).
            final genderLocked = profile?['gender_changed_once'] == true;
            final countryLocked = profile?['country_changed_once'] == true;
            final lockHint = TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: context.isArabic
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.isArabic
                            ? 'تعديل الملف الشخصي'
                            : 'Edit Profile',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ProfileInput(
                        controller: displayNameController,
                        label: context.isArabic ? 'اللقب' : 'Nickname',
                        isArabic: context.isArabic,
                      ),
                      _ProfileInput(
                        controller: birthDateController,
                        label: context.isArabic
                            ? 'تاريخ الميلاد'
                            : 'Date of birth',
                        isArabic: context.isArabic,
                        readOnly: true,
                        onTap: _pickBirthDate,
                      ),
                      // Country selector label
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          context.isArabic ? 'الدولة' : 'Country',
                          textAlign: context.isArabic
                              ? TextAlign.right
                              : TextAlign.left,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: countryLocked,
                        child: Opacity(
                          opacity: countryLocked ? 0.5 : 1.0,
                          child: CountrySelector(
                            selected: _selectedCountry,
                            isArabic: context.isArabic,
                            onSelected: (c) {
                              setSheetState(() {
                                _selectedCountry = c;
                                countryController.text = c.name;
                              });
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          countryLocked
                              ? (context.isArabic
                                    ? 'الدولة مقفلة.'
                                    : 'Country is locked.')
                              : (context.isArabic
                                    ? 'يمكنك تغيير الدولة مرة واحدة فقط.'
                                    : 'You can change country only once.'),
                          style: lockHint,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Directionality(
                          textDirection: context.isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedGender,
                            decoration: InputDecoration(
                              labelText: context.isArabic ? 'الجنس' : 'Gender',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            items: List.generate(genderOptions.length, (i) {
                              return DropdownMenuItem(
                                value: genderOptions[i],
                                child: Text(
                                  context.isArabic
                                      ? genderLabelsAr[i]
                                      : genderLabelsEn[i],
                                ),
                              );
                            }),
                            onChanged: genderLocked
                                ? null
                                : (v) {
                                    setSheetState(() {
                                      genderController.text = v ?? '';
                                    });
                                  },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          genderLocked
                              ? (context.isArabic
                                    ? 'الجنس مقفل.'
                                    : 'Gender is locked.')
                              : (context.isArabic
                                    ? 'يمكنك تغيير الجنس مرة واحدة فقط.'
                                    : 'You can change gender only once.'),
                          style: lockHint,
                        ),
                      ),
                      _ProfileInput(
                        controller: bioController,
                        label: context.isArabic ? 'النبذة' : 'Bio',
                        isArabic: context.isArabic,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  await _saveProfile();
                                  if (mounted && sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                },
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                            isSaving
                                ? (context.isArabic
                                      ? 'جار الحفظ...'
                                      : 'Saving...')
                                : (context.isArabic
                                      ? 'حفظ التغييرات'
                                      : 'Save changes'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Returns true when the current user may upload an animated GIF avatar.
  /// Eligibility: VIP 8 or above, OR level 60 or above.
  bool _canUseAnimatedAvatar() {
    final vipLevel = _effectiveProfileVipLevel();
    final userLevel = _userLevel?.level ?? 0;
    return vipLevel >= 8 || userLevel >= 60;
  }

  String _avatarExtension(String fileName, String? mimeType) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png') || mimeType == 'image/png') return 'png';
    if (lowerName.endsWith('.webp') || mimeType == 'image/webp') return 'webp';
    if (lowerName.endsWith('.gif') || mimeType == 'image/gif') return 'gif';
    return 'jpg';
  }

  Future<void> _uploadAvatar() async {
    final isArabic = context.isArabic;
    setState(() {
      isUploadingAvatar = true;
      errorMessage = null;
      successMessage = null;
    });
    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('No logged-in user found.');

      final picker = ImagePicker();
      // Pick without quality/resize constraints so GIF frames are not destroyed
      // by the native layer. Static images are already compressed by the device
      // camera app before reaching the gallery.
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        if (mounted) setState(() => isUploadingAvatar = false);
        return;
      }

      final extension = _avatarExtension(image.name, image.mimeType);

      // Animated GIF path
      if (extension == 'gif') {
        final vipLevel = _effectiveProfileVipLevel();
        final userLevel = _userLevel?.level ?? 0;
        final allowed = _canUseAnimatedAvatar();
        final reason = vipLevel >= 8
            ? 'vip'
            : userLevel >= 60
            ? 'level'
            : 'insufficient_status';

        debugPrint(
          '[AvatarGif] selected file type=gif'
          '  vipLevel=$vipLevel userLevel=$userLevel',
        );
        debugPrint('[AvatarGif] allowed=$allowed reason=$reason');

        if (!allowed) {
          debugPrint('[AvatarGif] blocked reason=insufficient_status');
          if (mounted) {
            setState(() {
              isUploadingAvatar = false;
              errorMessage = isArabic
                  ? 'صور الملف الشخصي المتحركة متاحة لـ VIP 8+ أو المستوى 60 فأعلى.'
                  : 'Animated profile pictures are available for VIP 8+ or Level 60+.';
            });
          }
          return;
        }

        // Read raw bytes directly from disk
        // transcoding that could strip GIF animation frames.
        final bytes = await File(image.path).readAsBytes();
        final fileSizeMb = bytes.length / (1024 * 1024);
        debugPrint('[AvatarGif] size=${fileSizeMb.toStringAsFixed(2)}MB');

        if (bytes.length > 2 * 1024 * 1024) {
          if (mounted) {
            setState(() {
              isUploadingAvatar = false;
              errorMessage = isArabic
                  ? 'حجم ملف GIF كبير جداً. الحد الأقصى 2 ميغابايت.'
                  : 'GIF file is too large. Maximum allowed size is 2 MB.';
            });
          }
          return;
        }

        final path =
            '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.gif';
        await client.storage
            .from('avatars')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/gif'),
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
        if (mounted) {
          setState(() {
            successMessage = isArabic
                ? 'تم تحديث الصورة.'
                : 'Profile image updated.';
          });
        }
        return; // GIF path done
      }

      // Static image path
      // Crop/adjust step — the picked image is NOT uploaded until the user taps
      // Save on the crop screen. Cancel returns null and uploads nothing.
      if (!mounted) return;
      final croppedBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          builder: (_) => AvatarCropScreen(
            imageFile: File(image.path),
            isArabic: isArabic,
            vipLevel: _effectiveProfileVipLevel(),
          ),
        ),
      );
      if (croppedBytes == null) {
        if (mounted) setState(() => isUploadingAvatar = false);
        return;
      }

      final Uint8List bytes = croppedBytes;
      final path =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      const contentType = 'image/png';

      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: contentType),
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
      if (mounted) {
        setState(() {
          successMessage = isArabic
              ? 'تم تحديث الصورة.'
              : 'Profile image updated.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          errorMessage = isArabic
              ? 'فشل رفع الصورة: $error'
              : 'Image upload failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => isUploadingAvatar = false);
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
    if (picked == null) return;
    birthDateController.text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  Future<void> _chooseAvatarFrame() async {
    final selectedFrameKey = profile?['selected_avatar_frame_key']?.toString();
    final avatarUrl = profile?['avatar_url']?.toString();
    final vipLevel = _effectiveProfileVipLevel();
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: const Color(0xFF12091D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return _AvatarFramePickerSheet(
          frames: avatarFrames,
          selectedFrameKey: selectedFrameKey,
          avatarUrl: avatarUrl,
          vipLevel: vipLevel,
          isArabic: context.isArabic,
        );
      },
    );

    if (!mounted || selected == selectedFrameKey) return;

    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('No logged-in user found.');

      await client
          .from('profiles')
          .update({
            'selected_avatar_frame_key': selected,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      await _loadProfile();
      setState(() {
        successMessage = context.isArabic
            ? 'تم حفظ إطار الصورة.'
            : 'Avatar frame saved.';
      });
    } catch (error) {
      setState(() {
        errorMessage = context.isArabic
            ? 'فشل حفظ الإطار: $error'
            : 'Frame save failed: $error';
      });
    }
  }

  DateTime? _profileVipExpiresAt() {
    final value = profile?['vip_expires_at'];
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  int _effectiveProfileVipLevel() {
    return VipFeatures.effectiveVipLevel(
      vipLevel: int.tryParse(profile?['vip_level']?.toString() ?? '') ?? 0,
      vipExpiresAt: _profileVipExpiresAt(),
    );
  }

  Future<void> _saveProfile() async {
    final isArabic = context.isArabic;
    final currentUsername = usernameController.text.trim();
    final displayName = displayNameController.text.trim();
    final dateOfBirth = birthDateController.text.trim();
    final bio = bioController.text.trim();
    final country = countryController.text.trim();
    final gender = genderController.text.trim();

    if (displayName.length < 2) {
      setState(() {
        successMessage = null;
        errorMessage = isArabic
            ? 'اللقب يجب أن يكون حرفين أو أكثر.'
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
      if (user == null) throw StateError('No logged-in user found.');

      // Profile updates go through the SECURITY DEFINER RPC, which enforces the
      // one-time gender/country change rule server-side.
      try {
        await client.rpc(
          'update_my_profile',
          params: {
            'p_username': currentUsername,
            'p_display_name': displayName,
            'p_date_of_birth': dateOfBirth,
            'p_bio': bio,
            'p_country': country,
            'p_gender': gender,
          },
        );
      } catch (error) {
        final msg = error.toString();
        if (msg.contains('gender_locked')) {
          setState(() {
            isSaving = false;
            errorMessage = isArabic
                ? 'يمكن تغيير الجنس مرة واحدة فقط.'
                : 'Gender can only be changed once.';
          });
          return;
        }
        if (msg.contains('country_locked')) {
          setState(() {
            isSaving = false;
            errorMessage = isArabic
                ? 'يمكن تغيير الدولة مرة واحدة فقط.'
                : 'Country can only be changed once.';
          });
          return;
        }
        rethrow;
      }

      await _loadProfile();
      setState(() {
        successMessage = isArabic ? 'تم حفظ الملف الشخصي.' : 'Profile saved.';
      });
    } catch (error) {
      setState(() {
        errorMessage = isArabic ? 'فشل الحفظ: $error' : 'Save failed: $error';
      });
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;

    if (isLoading) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: const SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final currentUserId =
        SupabaseService.requiredClient.auth.currentUser?.id ?? '';
    final avatarUrl = profile?['avatar_url']?.toString();
    final selectedAvatarFrameKey = profile?['selected_avatar_frame_key']
        ?.toString();
    final publicUserId = _profileText(
      'public_user_id',
      fallback: currentUserId.length >= 8
          ? currentUserId.substring(0, 8)
          : (currentUserId.isEmpty ? '-' : currentUserId),
    );
    final effectiveVipLevel = _effectiveProfileVipLevel();
    // TODO: remove previewVipLevel after VIP UI preview is confirmed.
    const int? previewVipLevel = null;
    final displayVipLevel = previewVipLevel ?? effectiveVipLevel;
    final isGoldenId = isGoldenIdActive(
      profile?['is_golden_id'] == true,
      DateTime.tryParse(profile?['golden_id_expires_at']?.toString() ?? ''),
    );
    final goldenIdStyle = profile?['golden_id_style']?.toString() ?? 'gold';
    final goldenIdFrame = profile?['golden_id_frame']?.toString() ?? 'classic';
    final coins = wallet?.coinsBalance ?? 0;
    final diamonds = wallet?.diamondsBalance ?? 0;
    final level =
        _userLevel?.level ??
        _intFromProfile(profile ?? {}, 'level', fallback: 1);
    debugPrint(
      '[LevelSync] display level=$level (rpc=${_userLevel?.level}, profile=${_intFromProfile(profile ?? {}, 'level', fallback: 1)})',
    );
    final country = _profileText('country');
    final gender = _profileText('gender');
    final bio = _profileText('bio');
    final displayName = displayNameController.text.trim().isNotEmpty
        ? displayNameController.text.trim()
        : (usernameController.text.trim().isNotEmpty
              ? usernameController.text.trim()
              : (isArabic ? 'عضو سرود' : 'SrOOd Member'));
    final uid = SupabaseService.requiredClient.auth.currentUser?.id;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RefreshIndicator(
              onRefresh: _loadProfile,
              color: const Color(0xFF8B26D9),
              backgroundColor: const Color(0xFF1A0D33),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).padding.bottom + 32 + 80,
                ),
                child: Column(
                  children: [
                    // 1. Premium Profile Header
                    _PremiumProfileHero(
                      displayName: displayName,
                      publicUserId: publicUserId,
                      avatarUrl: avatarUrl,
                      frameKey: selectedAvatarFrameKey,
                      vipLevel: displayVipLevel,
                      level: level,
                      charmLevel: _charmLevel,
                      wealthLevel: _wealthLevel,
                      isGoldenId: isGoldenId,
                      goldenIdStyle: goldenIdStyle,
                      goldenIdFrame: goldenIdFrame,
                      country: country,
                      gender: gender,
                      bio: bio,
                      isUploadingAvatar: isUploadingAvatar,
                      isArabic: isArabic,
                      onAvatarTap: _uploadAvatar,
                      onEditTap: _showEditProfileSheet,
                      onFrameTap: _chooseAvatarFrame,
                      onCopyId: () => _copyPublicId(publicUserId),
                    ),
                    const SizedBox(height: 14),

                    // 2. Stats Row (Friends / Following / Followers)
                    _ProfileStatsRow(
                      isArabic: isArabic,
                      followers: followersCount,
                      following: followingCount,
                      friends: friendsCount,
                      onFollowersTap: uid == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FollowListScreen(
                                  userId: uid,
                                  kind: 'followers',
                                  isArabic: isArabic,
                                ),
                              ),
                            ),
                      onFollowingTap: uid == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FollowListScreen(
                                  userId: uid,
                                  kind: 'following',
                                  isArabic: isArabic,
                                ),
                              ),
                            ),
                      onFriendsTap: uid == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FollowListScreen(
                                  userId: uid,
                                  kind: 'friends',
                                  isArabic: isArabic,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),

                    // 2. Achievements + Gift Wall
                    _ProfileAchievementsCard(
                      vipLevel: displayVipLevel,
                      level: level,
                      isGoldenId: isGoldenId,
                      followers: followersCount,
                      isArabic: isArabic,
                    ),
                    const SizedBox(height: 10),
                    _ProfileGiftWallCard(
                      giftsReceived: giftsReceivedCount,
                      visitors: visitorsCount,
                      charmLevel: _charmLevel,
                      wealthLevel: _wealthLevel,
                      isArabic: isArabic,
                    ),
                    const SizedBox(height: 10),

                    // 3. Moments / Gallery
                    _ProfileMomentsCard(isArabic: isArabic),
                    const SizedBox(height: 14),

                    // 4. Information + Level Progress
                    _ProfileInfoCard(
                      publicUserId: publicUserId,
                      country: country,
                      gender: gender,
                      createdAt: DateTime.tryParse(
                        profile?['created_at']?.toString() ?? '',
                      ),
                      vipLevel: effectiveVipLevel,
                      isGoldenId: isGoldenId,
                      isArabic: isArabic,
                    ),
                    const SizedBox(height: 10),
                    _ProfileLevelProgressCard(
                      userLevel: _userLevel,
                      charmLevel: _charmLevel,
                      wealthLevel: _wealthLevel,
                      isArabic: isArabic,
                    ),
                    const SizedBox(height: 14),

                    // 5. Wallet Cards (Coins + Diamonds)
                    _WalletCards(
                      coins: coins,
                      diamonds: diamonds,
                      isArabic: isArabic,
                      isLoading: isLoading,
                      onCoinsTap: _openWalletScreen,
                      onDiamondsTap: _openWalletScreen,
                    ),
                    const SizedBox(height: 14),

                    // 6. VIP Banner
                    _VipUpgradeBanner(
                      vipLevel: displayVipLevel,
                      isArabic: isArabic,
                      onTap: _openVipCenter,
                    ),
                    const SizedBox(height: 14),

                    // 7. Quick Actions Grid (6 items)
                    _QuickActionsGrid(
                      isArabic: isArabic,
                      onVipCenter: _openVipCenter,
                      onStore: _openStore,
                      onBackpack: _openBackpack,
                      onLevels: _openLevels,
                      onMyRoom: _openMyRoom,
                      roomLoading: _roomLoading,
                      onWealthCenter: _openWealthCenter,
                      onSettings: () =>
                          _openProfileHub(SettingsScreen(isArabic: isArabic)),
                    ),

                    // Notices
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
                    const SizedBox(height: 14),

                    // 6. Daily Check-in Card
                    _DailyCheckinCard(isArabic: isArabic, onTap: _openCheckin),
                    const SizedBox(height: 14),

                    // 7. Love / Relationship Card
                    const _LoveRelationshipCard(),
                    const SizedBox(height: 14),

                    // 8. Account & Support
                    _AccountSection(
                      isArabic: isArabic,
                      onWallet: _openWalletScreen,
                      onCustomerService: () => _openProfileHub(
                        CustomerServiceScreen(isArabic: isArabic),
                      ),
                      onPrivacy: _showSoon,
                    ),
                    const SizedBox(height: 14),

                    // 9. Logout
                    _LogoutButton(isArabic: isArabic, onTap: _confirmLogout),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Premium Profile Header
// -----------------------------------------------------------------------------

class _PremiumProfileHero extends StatelessWidget {
  const _PremiumProfileHero({
    required this.displayName,
    required this.publicUserId,
    required this.avatarUrl,
    required this.frameKey,
    required this.vipLevel,
    required this.level,
    required this.isGoldenId,
    required this.country,
    required this.gender,
    required this.bio,
    required this.isUploadingAvatar,
    required this.isArabic,
    required this.onAvatarTap,
    required this.onEditTap,
    required this.onFrameTap,
    required this.onCopyId,
    this.charmLevel,
    this.wealthLevel,
    this.goldenIdStyle = 'gold',
    this.goldenIdFrame = 'classic',
  });

  final String displayName;
  final String publicUserId;
  final String? avatarUrl;
  final String? frameKey;
  final int vipLevel;
  final int level;
  final int? charmLevel;
  final int? wealthLevel;
  final bool isGoldenId;
  final String goldenIdStyle;
  final String goldenIdFrame;
  final String country;
  final String gender;
  final String bio;
  final bool isUploadingAvatar;
  final bool isArabic;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditTap;
  final VoidCallback onFrameTap;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Avatar is the dominant element on the right. It scales with the card
        // width but is clamped so it never crushes the left content on small
        // phones nor balloons on tablets.
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final avatarZone = (maxW * 0.37).clamp(126.0, 158.0);
        return _buildCard(context, avatarZone);
      },
    );
  }

  Widget _buildCard(BuildContext context, double avatarZone) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final flag = _countryFlag(country);
    final subtitle = bio.isNotEmpty
        ? bio
        : (isArabic
              ? 'أهلاً بك في سرود لايف.'
              : 'Welcome to ${AppConfig.instance.appDisplayName}.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C0A44), Color(0xFF130720), Color(0xFF1E0B2E)],
          stops: [0.0, 0.52, 1.0],
        ),
        border: Border.all(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.32),
            blurRadius: 36,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.06),
            blurRadius: 20,
            spreadRadius: -2,
          ),
          ...VipVisualStyle.glow(vipLevel),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Background glow orb — radial gradient, softer
          Positioned(
            right: isArabic ? null : -40,
            left: isArabic ? -40 : null,
            top: -38,
            child: Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFB03CF5).withValues(alpha: 0.22),
                    const Color(0xFF8B26D9).withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // Top-edge inner glow for depth
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.055),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Edit button — gold pill (icon + label), visually anchored
          Positioned(
            right: isArabic ? null : 4,
            left: isArabic ? 4 : null,
            top: 8,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onEditTap,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: const Color(0xFFF0C15A).withValues(alpha: 0.13),
                  border: Border.all(
                    color: const Color(0xFFF0C15A).withValues(alpha: 0.52),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF0C15A).withValues(alpha: 0.10),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.edit_rounded,
                      color: Color(0xFFF0C15A),
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isArabic ? 'تعديل' : 'Edit',
                      style: const TextStyle(
                        color: Color(0xFFF0C15A),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Decorative EQ icon
          Positioned(
            left: isArabic ? null : 52,
            right: isArabic ? 52 : null,
            bottom: 16,
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 54,
              color: Colors.white.withValues(alpha: 0.045),
            ),
          ),
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    // "Srood Profile" label — padded from top to clear edit pill
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(
                              0xFFF0C15A,
                            ).withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          textDirection: isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFF0C15A),
                              size: 12,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isArabic ? 'ملف سرود' : 'Srood Profile',
                              style: TextStyle(
                                color: const Color(
                                  0xFFF0C15A,
                                ).withValues(alpha: 0.88),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Display name — primary identity element
                    VipUsername(
                      name: displayName,
                      vipLevel: vipLevel,
                      fontSize: 24,
                      textAlign: textAlign,
                    ),
                    const SizedBox(height: 8),
                    // Public ID
                    if (isGoldenId)
                      GoldenIdBadge(
                        idText: 'ID:$publicUserId',
                        goldenIdStyle: goldenIdStyle,
                        goldenIdFrame: goldenIdFrame,
                        onTap: onCopyId,
                        showCopyIcon: true,
                      )
                    else
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: onCopyId,
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF100718,
                            ).withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(
                                0xFFF0C15A,
                              ).withValues(alpha: 0.22),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            textDirection: isArabic
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            children: [
                              Flexible(
                                child: Text(
                                  'ID:$publicUserId',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: textAlign,
                                  style: const TextStyle(
                                    color: Color(0xFFCFC3DC),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                Icons.copy_rounded,
                                color: Colors.white.withValues(alpha: 0.55),
                                size: 13,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Chip row 1 — country + VIP
                    if (flag.isNotEmpty || vipLevel > 0)
                      Wrap(
                        alignment: isArabic
                            ? WrapAlignment.end
                            : WrapAlignment.start,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (flag.isNotEmpty)
                            _ProfileBadge(label: flag, highlighted: false),
                          if (vipLevel > 0) VipBadge(vipLevel: vipLevel),
                        ],
                      ),
                    const SizedBox(height: 8),
                    // Charm + Wealth + Gender — equal compact square chips on
                    // ONE row (replaces the old stacked full-width pills).
                    _buildStatChipRow(),
                    // Bottom status / bio pill — dark glass, full-width-ish.
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFF0C15A).withValues(alpha: 0.20),
                        ),
                      ),
                      child: Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: textAlign,
                        style: TextStyle(
                          color: const Color(
                            0xFFBCAED6,
                          ).withValues(alpha: 0.78),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Avatar zone with soft premium glow
              _buildAvatarZone(avatarZone),
            ],
          ),
        ],
      ),
    );
  }

  // Charm / Wealth / Gender as equal-width compact chips on a single row.
  // Only the chips whose data exists are shown; an empty list renders nothing.
  Widget _buildStatChipRow() {
    final chips = <Widget>[];

    if (charmLevel != null) {
      chips.add(
        _HeroStatChip(
          icon: Icons.favorite_rounded,
          label: isArabic ? 'سحر' : 'Charm',
          value: '$charmLevel',
          colorA: const Color(0xFFE0449A),
          colorB: const Color(0xFF7A1250),
        ),
      );
    }
    if (wealthLevel != null) {
      chips.add(
        _HeroStatChip(
          icon: Icons.diamond_rounded,
          label: isArabic ? 'ثروة' : 'Wealth',
          value: '$wealthLevel',
          colorA: const Color(0xFFD4A017),
          colorB: const Color(0xFF6B4800),
        ),
      );
    }
    if (ProfileGenderChip.isKnown(gender)) {
      final male = gender.trim().toLowerCase() == 'male';
      chips.add(
        _HeroStatChip(
          icon: male ? Icons.male_rounded : Icons.female_rounded,
          label: isArabic ? 'الجنس' : 'Gender',
          value: male
              ? (isArabic ? 'ذكر' : 'Male')
              : (isArabic ? 'أنثى' : 'Female'),
          colorA: male ? const Color(0xFF3B9BFF) : const Color(0xFFFF5C8A),
          colorB: male ? const Color(0xFF1B4E8A) : const Color(0xFF8A2350),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    final row = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      row.add(Expanded(child: chips[i]));
      if (i < chips.length - 1) row.add(const SizedBox(width: 7));
    }

    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: row,
    );
  }

  Widget _buildAvatarZone(double zone) {
    final zoneWidth = zone;
    final glowDiam = zone * 0.76;
    const cameraSize = 31.0; // slightly smaller, cleaner
    const cameraIcon = 15.0;
    final frameBox = zone;

    // The premium webp VIP frame is the single frame when the user has no
    // custom frame selected. Per-tier calibration sizes/centres the avatar so
    // it fits that tier's opening instead of a one-size-fits-all 92px circle.
    final showWebpFrame =
        VipAssets.hasVip(vipLevel) &&
        (frameKey == null || frameKey!.trim().isEmpty);
    final frameLayout = VipFrameLayout.of(vipLevel);
    final avatarRadius = showWebpFrame
        ? (frameBox * frameLayout.avatarFillRatio) / 2
        : zone * 0.35;
    final avatarDy = showWebpFrame
        ? frameBox * frameLayout.avatarDyFraction
        : 0.0;

    return Padding(
      // A little breathing room from the card's right edge so the frame is not
      // crowded against it.
      padding: const EdgeInsets.only(right: 5),
      child: SizedBox(
        width: zoneWidth,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Soft premium glow
            Container(
              width: glowDiam,
              height: glowDiam,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF7B22CC).withValues(alpha: 0.60),
                    const Color(0xFFC13BFF).withValues(alpha: 0.22),
                    const Color(0xFFFF4ECD).withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.44, 0.70, 1.0],
                ),
              ),
            ),
            // Inner gold halo ring
            Container(
              width: glowDiam + 4,
              height: glowDiam + 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFF0C15A).withValues(alpha: 0.24),
                  width: 1.2,
                ),
              ),
            ),
            // Outer gold halo ring (diffuse)
            Container(
              width: glowDiam + 14,
              height: glowDiam + 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFF0C15A).withValues(alpha: 0.08),
                  width: 1.0,
                ),
              ),
            ),
            // Avatar
            // a single clean webp layer below (or the user's custom frameKey), so
            // the shared widget renders only the photo here (no auto PNG frame,
            // no badge pill) to avoid stacking two frames on one avatar. Sized and
            // nudged per VipFrameLayout so it sits inside this tier's opening.
            Transform.translate(
              offset: Offset(0, avatarDy),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onFrameTap,
                child: AvatarWithFrame(
                  imageUrl: avatarUrl,
                  radius: avatarRadius,
                  frameKey: frameKey,
                  vipLevel: vipLevel,
                  showVipBadge: false,
                  autoVipFrame: false,
                  compact: true,
                  animated: _isPremiumFrameKey(frameKey),
                ),
              ),
            ),
            // Section
            // avatar. Only shown when the user has not picked a custom frame
            // (a custom frameKey is rendered by AvatarWithFrame above instead),
            // so the avatar + frame always read as one composed unit.
            if (showWebpFrame)
              IgnorePointer(
                child: Image.asset(
                  VipAssets.frame(vipLevel),
                  width: frameBox,
                  height: frameBox,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            // Camera button
            Positioned(
              right: 2,
              bottom: 0,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isUploadingAvatar ? null : onAvatarTap,
                child: Container(
                  width: cameraSize,
                  height: cameraSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF5D070), Color(0xFFD4A017)],
                    ),
                    border: Border.all(
                      color: const Color(0xFF160B26),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isUploadingAvatar
                        ? Icons.hourglass_top_rounded
                        : Icons.camera_alt_rounded,
                    color: const Color(0xFF160B26),
                    size: cameraIcon,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countryFlag(String value) {
    if (value.trim().isEmpty) return '';
    final match = countryFromStored(value);
    if (match != null) return '${match.flag} ${match.name}';
    // Fall back to displaying the raw value for any legacy free-text entries.
    return value;
  }
}

// -----------------------------------------------------------------------------
// Stats Row - Friends / Following / Followers
// -----------------------------------------------------------------------------

class _ProfileStatsRow extends StatelessWidget {
  const _ProfileStatsRow({
    required this.isArabic,
    required this.followers,
    required this.following,
    required this.friends,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onFriendsTap,
  });

  final bool isArabic;
  final int followers;
  final int following;
  final int friends;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFriendsTap;

  static const _gold = Color(0xFFF0C15A);
  static const _lavender = Color(0xFFBCAED6);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E0D36), Color(0xFF16092C), Color(0xFF0D051A)],
        ),
        border: Border.all(
          color: const Color(0xFF7040B0).withValues(alpha: 0.50),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _gold.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: IntrinsicHeight(
          child: Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: _ProfileStatItem(
                  count: friends,
                  label: isArabic ? 'الأصدقاء' : 'Friends',
                  icon: Icons.people_rounded,
                  accentColor: onFriendsTap != null ? _gold : _lavender,
                  isTappable: onFriendsTap != null,
                  onTap: onFriendsTap,
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _ProfileStatItem(
                  count: following,
                  label: isArabic ? 'يتابع' : 'Following',
                  icon: Icons.person_add_rounded,
                  accentColor: onFollowingTap != null ? _gold : _lavender,
                  isTappable: onFollowingTap != null,
                  onTap: onFollowingTap,
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _ProfileStatItem(
                  count: followers,
                  label: isArabic ? 'المتابعون' : 'Followers',
                  icon: Icons.person_rounded,
                  accentColor: onFollowersTap != null ? _gold : _lavender,
                  isTappable: onFollowersTap != null,
                  onTap: onFollowersTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileStatItem extends StatelessWidget {
  const _ProfileStatItem({
    required this.count,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isTappable,
    this.onTap,
  });

  final int count;
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isTappable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: accentColor.withValues(alpha: 0.12),
      highlightColor: accentColor.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Icon(icon, size: 18, color: accentColor.withValues(alpha: 0.80)),
            const SizedBox(height: 7),
            // Count
            Text(
              _formatCount(count),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            // Label + optional chevron
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (isTappable) ...[
                  const SizedBox(width: 1),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 13,
                    color: accentColor.withValues(alpha: 0.80),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 16),
      color: const Color(0xFF5A3880).withValues(alpha: 0.45),
    );
  }
}

// -----------------------------------------------------------------------------
// Wallet Cards
// -----------------------------------------------------------------------------

class _WalletCards extends StatelessWidget {
  const _WalletCards({
    required this.coins,
    required this.diamonds,
    required this.isArabic,
    required this.isLoading,
    required this.onCoinsTap,
    required this.onDiamondsTap,
  });

  final int coins;
  final int diamonds;
  final bool isArabic;
  final bool isLoading;
  final VoidCallback onCoinsTap;
  final VoidCallback onDiamondsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Expanded(
          child: WalletBalanceCard(
            icon: Icons.monetization_on_rounded,
            label: isArabic ? 'العملات' : 'Coin wallet',
            value: coins,
            isLoading: isLoading,
            colors: const [
              Color(0xFFFFE9A8),
              Color(0xFFF0C15A),
              Color(0xFFC9871C),
            ],
            glowColor: const Color(0xFFF0C15A),
            textColor: const Color(0xFF3A2606),
            onTap: onCoinsTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: WalletBalanceCard(
            icon: Icons.diamond_rounded,
            label: isArabic ? 'الألماس' : 'Diamonds wallet',
            value: diamonds,
            isLoading: isLoading,
            colors: const [
              Color(0xFFF1A6FF),
              Color(0xFFB44CF0),
              Color(0xFF7D2BFF),
            ],
            glowColor: const Color(0xFFB875FF),
            textColor: Colors.white,
            onTap: onDiamondsTap,
          ),
        ),
      ],
    );
  }
}

class WalletBalanceCard extends StatelessWidget {
  const WalletBalanceCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    required this.glowColor,
    required this.onTap,
    this.textColor = const Color(0xFF160B26),
    this.isLoading = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final int value;
  final List<Color> colors;
  final Color glowColor;
  final VoidCallback onTap;
  final Color textColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final onColor = textColor;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            // Premium 3D glossy gradient (identity colors preserved).
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            // Beveled rim.
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.40),
                blurRadius: 22,
                offset: const Offset(0, 10),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Top glossy shine.
              const Positioned.fill(child: GlossSheen(opacity: 0.30)),
              // Right-side programmatic wallet artwork (decorative).
              Positioned(
                right: -14,
                bottom: -10,
                child: _WalletArt(accent: icon, tint: onColor),
              ),
              // Content.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: onColor.withValues(alpha: 0.5),
                          size: 11,
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Raised currency coin/diamond chip.
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Icon(icon, color: onColor, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: isLoading
                              ? Container(
                                  width: 60,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: onColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                )
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    _formatCount(value),
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: onColor,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      height: 1.0,
                                      shadows: [
                                        Shadow(
                                          color: Colors.white.withValues(
                                            alpha: 0.25,
                                          ),
                                          blurRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Programmatic premium wallet artwork (tilted wallet body + flap + accent),
/// used as a decorative element on the right of a wallet card. No assets.
class _WalletArt extends StatelessWidget {
  const _WalletArt({required this.accent, required this.tint});

  final IconData accent;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.34,
        child: Transform.rotate(
          angle: -0.16,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A card slipping out behind the wallet (depth).
                Positioned(
                  top: 14,
                  child: Container(
                    width: 50,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      color: Colors.white.withValues(alpha: 0.22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
                // Wallet body (glossy).
                Container(
                  width: 66,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.42),
                        Colors.white.withValues(alpha: 0.18),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                ),
                // Clasp / button on the wallet.
                Positioned(
                  right: 12,
                  child: Container(
                    width: 6,
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                // Glossy currency coin/diamond accent (raised, top-right).
                Positioned(
                  top: 6,
                  right: 4,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white,
                          Color.lerp(tint, Colors.white, 0.3)!,
                          tint,
                        ],
                        stops: const [0.0, 0.4, 1.0],
                        center: const Alignment(-0.3, -0.4),
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    child: Icon(accent, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// VIP Banner
// -----------------------------------------------------------------------------

class _VipUpgradeBanner extends StatelessWidget {
  const _VipUpgradeBanner({
    required this.vipLevel,
    required this.isArabic,
    required this.onTap,
  });

  final int vipLevel;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = vipLevel > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B105A), Color(0xFF7D2BFF), Color(0xFF4A1478)],
          ),
          border: Border.all(color: const Color(0xFFF0C15A)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB000FF).withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Stack(
            children: [
              // Hero image: right-side decorative background when VIP is active
              if (active && VipAssets.hasVip(vipLevel))
                Positioned(
                  right: isArabic ? null : 0,
                  left: isArabic ? 0 : null,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.82,
                      child: Image.asset(
                        VipAssets.hero(vipLevel),
                        width: 140,
                        fit: BoxFit.contain,
                        alignment: isArabic
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              // Foreground content row
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    Container(
                      width: 48,
                      height: 46,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF0C15A),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFF160B26),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: isArabic
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            active
                                ? (isArabic
                                      ? 'VIP مستوى $vipLevel نشط'
                                      : 'VIP Lv$vipLevel Active')
                                : 'VIP',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            active
                                ? (isArabic
                                      ? 'استمتع بمزايا VIP الحصرية'
                                      : 'Enjoy your exclusive VIP benefits')
                                : (isArabic
                                      ? 'افتح تجربة مميزة'
                                      : 'Unlock Premium Experience'),
                            style: const TextStyle(
                              color: Color(0xFFF7E9FF),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GoldMiniButton(label: active ? 'Manage' : 'Upgrade'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Quick Actions Grid - 6 items in 3x2 layout
// -----------------------------------------------------------------------------

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.isArabic,
    required this.onVipCenter,
    required this.onStore,
    required this.onBackpack,
    required this.onLevels,
    required this.onMyRoom,
    required this.onSettings,
    required this.roomLoading,
    required this.onWealthCenter,
  });

  final bool isArabic;
  final VoidCallback onVipCenter;
  final VoidCallback onStore;
  final VoidCallback onBackpack;
  final VoidCallback onLevels;
  final VoidCallback onMyRoom;
  final VoidCallback onSettings;
  final bool roomLoading;
  final VoidCallback onWealthCenter;

  @override
  Widget build(BuildContext context) {
    final items = [
      _FeatureTileData(
        icon: Icons.workspace_premium_rounded,
        label: isArabic ? 'مركز VIP' : 'VIP Center',
        onTap: onVipCenter,
        gradientColors: const [Color(0xFFF0C15A), Color(0xFFD99A2B)],
      ),
      _FeatureTileData(
        icon: Icons.storefront_rounded,
        label: isArabic ? 'المتجر' : 'Store',
        onTap: onStore,
        gradientColors: const [Color(0xFF9BE88F), Color(0xFF2ECC71)],
      ),
      _FeatureTileData(
        icon: Icons.backpack_rounded,
        label: isArabic ? 'الحقيبة' : 'Backpack',
        onTap: onBackpack,
        gradientColors: const [Color(0xFFFFD978), Color(0xFFFF9500)],
      ),
      // TODO(charm): old generic Levels tile hidden for now. It may return
      // later as the "Charm" (received-support) progression. _openLevels(),
      // onLevels, the LevelCenterScreen import, and the profile header Lv badge
      // are intentionally kept so it can be re-enabled without rebuilding it.
      _FeatureTileData(
        icon: roomLoading ? Icons.hourglass_top_rounded : Icons.home_rounded,
        label: isArabic ? 'غرفتي' : 'My Room',
        onTap: onMyRoom,
        gradientColors: const [Color(0xFF8B26D9), Color(0xFF4A1478)],
      ),
      _FeatureTileData(
        icon: Icons.diamond_rounded,
        label: isArabic ? 'السحر / الثروة' : 'Charm / Wealth',
        onTap: onWealthCenter,
        gradientColors: const [Color(0xFFFFD700), Color(0xFF8B26D9)],
      ),
      _FeatureTileData(
        icon: Icons.settings_rounded,
        label: isArabic ? 'الإعدادات' : 'Settings',
        onTap: onSettings,
        gradientColors: const [Color(0xFFBCAED6), Color(0xFF6B5E8E)],
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4A3470)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 4,
        childAspectRatio: 0.88,
        children: items
            .map((data) => _ProfileFeatureTile(data: data, isArabic: isArabic))
            .toList(),
      ),
    );
  }
}

class _FeatureTileData {
  const _FeatureTileData({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.gradientColors,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final List<Color> gradientColors;
}

class _ProfileFeatureTile extends StatelessWidget {
  const _ProfileFeatureTile({required this.data, required this.isArabic});

  final _FeatureTileData data;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: data.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: data.gradientColors,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: data.gradientColors.last.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Account & Support Section - Wallet, Customer Service, Privacy
// -----------------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.isArabic,
    required this.onWallet,
    required this.onCustomerService,
    required this.onPrivacy,
  });

  final bool isArabic;
  final VoidCallback onWallet;
  final VoidCallback onCustomerService;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      isArabic: isArabic,
      title: isArabic ? 'الحساب والدعم' : 'Account & Support',
      icon: Icons.settings_outlined,
      children: [
        ProfileListRow(
          icon: Icons.account_balance_wallet_rounded,
          iconColor: const Color(0xFF2ECC71),
          title: isArabic ? 'المحفظة' : 'Wallet',
          subtitle: isArabic ? 'الشحن والمعاملات' : 'Recharge & transactions',
          isArabic: isArabic,
          onTap: onWallet,
        ),
        ProfileListRow(
          icon: Icons.support_agent_rounded,
          iconColor: const Color(0xFFFFD978),
          title: isArabic ? 'خدمة العملاء' : 'Customer Service',
          subtitle: isArabic
              ? 'مساعدة، شحن، وبلاغات'
              : 'Help, recharge & reports',
          isArabic: isArabic,
          onTap: onCustomerService,
        ),
        ProfileListRow(
          icon: Icons.privacy_tip_rounded,
          iconColor: const Color(0xFF9BE8FF),
          title: isArabic ? 'الخصوصية' : 'Privacy',
          subtitle: isArabic ? 'قريباً' : 'Coming soon',
          isArabic: isArabic,
          onTap: onPrivacy,
          showDivider: false,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Daily Check-in Card
// -----------------------------------------------------------------------------

class _DailyCheckinCard extends StatelessWidget {
  const _DailyCheckinCard({required this.isArabic, required this.onTap});

  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0C2E), Color(0xFF2D1247)],
          ),
          border: Border.all(
            color: const Color(0xFFF0C15A).withValues(alpha: 0.38),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B26D9).withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF88A0), Color(0xFFFF3D6B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF3D6B).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    isArabic ? 'الحضور اليومي' : 'Daily Check-in',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isArabic
                        ? 'سجّل حضورك واحصل على مكافآت يومية'
                        : 'Check in daily and earn rewards',
                    style: const TextStyle(
                      color: Color(0xFFBCAED6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF0C15A),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                isArabic ? 'تحقق' : 'Check in',
                style: const TextStyle(
                  color: Color(0xFF160B26),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Love / Relationship Card (coming soon placeholder)
// -----------------------------------------------------------------------------

class _LoveRelationshipCard extends StatelessWidget {
  const _LoveRelationshipCard();

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0C2E), Color(0xFF2A0828)],
        ),
        border: Border.all(
          color: const Color(0xFFFF88A0).withValues(alpha: 0.38),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3D6B).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF88A0), Color(0xFFFF3D6B)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3D6B).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'العلاقات' : 'Relationships',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isArabic
                      ? 'ابحث عن روحك التوأم في سرود لايف'
                      : 'Find your soulmate on ${AppConfig.instance.appDisplayName}',
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1428),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFFF88A0).withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              isArabic ? 'قريباً' : 'Soon',
              style: const TextStyle(
                color: Color(0xFFFF88A0),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Section card container with title
// -----------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.isArabic,
    required this.title,
    required this.icon,
    required this.children,
  });

  final bool isArabic;
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4A3470)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Icon(icon, color: const Color(0xFFF0C15A), size: 16),
                const SizedBox(width: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF0C15A),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Profile List Row
// -----------------------------------------------------------------------------

class ProfileListRow extends StatelessWidget {
  const ProfileListRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.isArabic,
    required this.onTap,
    this.subtitle,
    this.showDivider = true,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isArabic;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: showDivider
              ? BorderRadius.zero
              : const BorderRadius.vertical(bottom: Radius.circular(24)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: iconColor.withValues(alpha: 0.15),
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: isArabic
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB9A9D4),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  isArabic
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: const Color(0xFF7D728F),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: isArabic ? 16 : 66,
            endIndent: isArabic ? 66 : 16,
            color: const Color(0xFF4A3470).withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Logout Button
// -----------------------------------------------------------------------------

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.isArabic, required this.onTap});

  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1A0A14),
          border: Border.all(
            color: const Color(0xFFFF5C7A).withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5C7A).withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(
              Icons.logout_rounded,
              color: Color(0xFFFF5C7A),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              isArabic ? 'تسجيل الخروج' : 'Sign Out',
              style: const TextStyle(
                color: Color(0xFFFF5C7A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared helpers
// -----------------------------------------------------------------------------

class _GoldMiniButton extends StatelessWidget {
  const _GoldMiniButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0C15A),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF160B26),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}


// Compact square stat chip used on a single row in the profile hero for
// Charm / Wealth / Gender. Vertical layout (icon → label → value) keeps each
// chip narrow so three fit side by side without overflow on small phones.
class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorA,
    required this.colorB,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color colorA; // lit / highlight tone
  final Color colorB; // deep / shadow tone

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colorA, Colors.white, 0.18)!,
            colorA,
            colorB,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.30),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colorA.withValues(alpha: 0.42),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1.0,
                shadows: [Shadow(color: Colors.black38, blurRadius: 2)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFF0C15A).withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFF0C15A)
              : Colors.white.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted ? const Color(0xFFF0C15A) : Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
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

// -----------------------------------------------------------------------------
// Avatar Frame Picker (unchanged)
// -----------------------------------------------------------------------------

class _AvatarFramePickerSheet extends StatelessWidget {
  const _AvatarFramePickerSheet({
    required this.frames,
    required this.selectedFrameKey,
    required this.avatarUrl,
    required this.vipLevel,
    required this.isArabic,
  });

  final List<AvatarFrame> frames;
  final String? selectedFrameKey;
  final String? avatarUrl;
  final int vipLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: Color(0xFF08030D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            children: [
              Text(
                isArabic ? 'إطار الصورة' : 'Avatar Frame',
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              _AvatarFramePickerTile(
                avatarUrl: avatarUrl,
                frame: null,
                selected: selectedFrameKey == null || selectedFrameKey!.isEmpty,
                unlocked: true,
                vipLevel: vipLevel,
                isArabic: isArabic,
              ),
              _AvatarFrameGroup(
                title: isArabic ? 'عادي' : 'Normal',
                frames: frames
                    .where((frame) => frame.category == 'normal')
                    .toList(),
                selectedFrameKey: selectedFrameKey,
                avatarUrl: avatarUrl,
                vipLevel: vipLevel,
                isArabic: isArabic,
              ),
              _AvatarFrameGroup(
                title: isArabic ? 'فاخر' : 'Luxury',
                frames: frames
                    .where((frame) => frame.category == 'luxury')
                    .toList(),
                selectedFrameKey: selectedFrameKey,
                avatarUrl: avatarUrl,
                vipLevel: vipLevel,
                isArabic: isArabic,
              ),
              _AvatarFrameGroup(
                title: 'VIP',
                frames: frames
                    .where((frame) => frame.category == 'vip')
                    .toList(),
                selectedFrameKey: selectedFrameKey,
                avatarUrl: avatarUrl,
                vipLevel: vipLevel,
                isArabic: isArabic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarFrameGroup extends StatelessWidget {
  const _AvatarFrameGroup({
    required this.title,
    required this.frames,
    required this.selectedFrameKey,
    required this.avatarUrl,
    required this.vipLevel,
    required this.isArabic,
  });

  final String title;
  final List<AvatarFrame> frames;
  final String? selectedFrameKey;
  final String? avatarUrl;
  final int vipLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    if (frames.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: isArabic ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFFF0C15A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: frames.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.70,
            ),
            itemBuilder: (context, index) {
              final frame = frames[index];
              return _AvatarFramePickerTile(
                avatarUrl: avatarUrl,
                frame: frame,
                selected: selectedFrameKey == frame.frameKey,
                unlocked: frame.isUnlockedFor(vipLevel),
                vipLevel: vipLevel,
                isArabic: isArabic,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AvatarFramePickerTile extends StatelessWidget {
  const _AvatarFramePickerTile({
    required this.avatarUrl,
    required this.frame,
    required this.selected,
    required this.unlocked,
    required this.vipLevel,
    required this.isArabic,
  });

  final String? avatarUrl;
  final AvatarFrame? frame;
  final bool selected;
  final bool unlocked;
  final int vipLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final requiredVip = frame?.vipLevel;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (unlocked) {
          Navigator.of(context).pop<String?>(frame?.frameKey);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'هذا الإطار متاح لمستوى VIP أعلى'
                  : 'This frame requires a higher VIP level',
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2D1247) : const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFF0C15A) : const Color(0xFF4A3470),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWithFrame(
              imageUrl: avatarUrl,
              radius: 24,
              frameKey: frame?.frameKey,
              vipLevel: vipLevel,
              showVipBadge: false,
              animated: _isPremiumFrameKey(frame?.frameKey),
            ),
            const SizedBox(height: 5),
            Flexible(
              child: Text(
                frame?.name ?? (isArabic ? 'بدون إطار' : 'No Frame'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unlocked
                  ? (selected ? (isArabic ? 'محدد' : 'Selected') : '')
                  : (isArabic
                        ? 'VIP ${requiredVip ?? 1}'
                        : 'VIP ${requiredVip ?? 1}'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unlocked
                    ? const Color(0xFFF0C15A)
                    : const Color(0xFF9E91B8),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Utilities
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Achievements Card
// -----------------------------------------------------------------------------

class _ProfileAchievementsCard extends StatelessWidget {
  const _ProfileAchievementsCard({
    required this.vipLevel,
    required this.level,
    required this.isGoldenId,
    required this.followers,
    required this.isArabic,
  });

  final int vipLevel;
  final int level;
  final bool isGoldenId;
  final int followers;
  final bool isArabic;

  static const _gold   = Color(0xFFF0C15A);
  static const _purple = Color(0xFF8B26D9);

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.emoji_events_rounded,
            label: isArabic ? 'الإنجازات' : 'Achievements',
            iconColor: _gold,
            isArabic: isArabic,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemW = (constraints.maxWidth - 12 * (items.length - 1)) /
                  items.length;
              return Row(
                textDirection:
                    isArabic ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    SizedBox(width: itemW, child: items[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildItems() {
    return [
      _AchievementBadge(
        icon: Icons.star_rounded,
        label: isArabic ? 'المستوى' : 'Level',
        value: level.toString(),
        gradientColors: const [Color(0xFF3D1A6E), Color(0xFF6A28C0)],
        glowColor: _purple,
        iconColor: const Color(0xFFD8AAFF),
      ),
      _AchievementBadge(
        icon: Icons.workspace_premium_rounded,
        label: isArabic ? 'VIP' : 'VIP',
        value: vipLevel > 0 ? 'V$vipLevel' : '—',
        gradientColors: const [Color(0xFF1A3A10), Color(0xFF2E6A20)],
        glowColor: const Color(0xFF4CAF50),
        iconColor: const Color(0xFF88EE88),
      ),
      _AchievementBadge(
        icon: isGoldenId
            ? Icons.verified_rounded
            : Icons.tag_rounded,
        label: isArabic ? 'المعرّف' : 'ID',
        value: isGoldenId ? (isArabic ? 'ذهبي' : 'Gold') : (isArabic ? 'عادي' : 'Basic'),
        gradientColors: isGoldenId
            ? const [Color(0xFF4A3000), Color(0xFF7A5500)]
            : const [Color(0xFF1E1040), Color(0xFF2E1C60)],
        glowColor: isGoldenId ? _gold : _purple,
        iconColor: isGoldenId ? _gold : const Color(0xFFBCAED6),
      ),
      _AchievementBadge(
        icon: Icons.people_rounded,
        label: isArabic ? 'المتابعون' : 'Followers',
        value: _formatCount(followers),
        gradientColors: const [Color(0xFF1A0830), Color(0xFF3A1260)],
        glowColor: const Color(0xFFE040FB),
        iconColor: const Color(0xFFE8B0FF),
      ),
    ];
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradientColors,
    required this.glowColor,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradientColors;
  final Color glowColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.18),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glowColor.withValues(alpha: 0.15),
              border: Border.all(
                color: glowColor.withValues(alpha: 0.40),
                width: 1.0,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: iconColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.50),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Gift Wall Summary Card
// -----------------------------------------------------------------------------

class _ProfileGiftWallCard extends StatelessWidget {
  const _ProfileGiftWallCard({
    required this.giftsReceived,
    required this.visitors,
    this.charmLevel,
    this.wealthLevel,
    required this.isArabic,
  });

  final int giftsReceived;
  final int visitors;
  final int? charmLevel;
  final int? wealthLevel;
  final bool isArabic;

  static const _gold   = Color(0xFFF0C15A);
  static const _rose   = Color(0xFFE0449A);
  static const _teal   = Color(0xFF26D9B8);

  @override
  Widget build(BuildContext context) {
    final textDir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.card_giftcard_rounded,
            label: isArabic ? 'الهدايا والزيارات' : 'Gifts & Visits',
            iconColor: _rose,
            isArabic: isArabic,
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              textDirection: textDir,
              children: [
                Expanded(
                  child: _GiftStatItem(
                    icon: Icons.card_giftcard_rounded,
                    label: isArabic ? 'الهدايا المستلمة' : 'Gifts Received',
                    value: _formatCount(giftsReceived),
                    iconColor: _rose,
                    glowColor: _rose,
                  ),
                ),
                _VerticalDivider(),
                Expanded(
                  child: _GiftStatItem(
                    icon: Icons.remove_red_eye_rounded,
                    label: isArabic ? 'الزيارات' : 'Profile Visits',
                    value: _formatCount(visitors),
                    iconColor: _teal,
                    glowColor: _teal,
                  ),
                ),
                if (charmLevel != null) ...[
                  _VerticalDivider(),
                  Expanded(
                    child: _GiftStatItem(
                      icon: Icons.favorite_rounded,
                      label: isArabic ? 'مستوى السحر' : 'Charm Lv.',
                      value: charmLevel.toString(),
                      iconColor: _rose,
                      glowColor: _rose,
                    ),
                  ),
                ],
                if (wealthLevel != null) ...[
                  _VerticalDivider(),
                  Expanded(
                    child: _GiftStatItem(
                      icon: Icons.diamond_rounded,
                      label: isArabic ? 'مستوى الثروة' : 'Wealth Lv.',
                      value: wealthLevel.toString(),
                      iconColor: _gold,
                      glowColor: _gold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftStatItem extends StatelessWidget {
  const _GiftStatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.glowColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glowColor.withValues(alpha: 0.12),
              border: Border.all(
                color: glowColor.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.22),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: iconColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// Shared card shell
// -----------------------------------------------------------------------------
// Information Card (P5)
// -----------------------------------------------------------------------------

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({
    required this.publicUserId,
    required this.country,
    required this.gender,
    required this.vipLevel,
    required this.isGoldenId,
    required this.isArabic,
    this.createdAt,
  });

  final String publicUserId;
  final String country;
  final String gender;
  final DateTime? createdAt;
  final int vipLevel;
  final bool isGoldenId;
  final bool isArabic;

  static const _purple = Color(0xFF8B26D9);
  static const _gold = Color(0xFFF0C15A);

  String _localiseGender(String raw) {
    final g = raw.trim().toLowerCase();
    if (isArabic) {
      if (g == 'male') return 'ذكر';
      if (g == 'female') return 'أنثى';
      if (g == 'other') return 'آخر';
    } else {
      if (g == 'male') return 'Male';
      if (g == 'female') return 'Female';
      if (g == 'other') return 'Other';
    }
    return raw;
  }

  String _formatJoined(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const monthsAr = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    final m = isArabic ? monthsAr[dt.month - 1] : months[dt.month - 1];
    return isArabic ? '${dt.year} $m' : '$m ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <_InfoRowData>[];

    rows.add(_InfoRowData(
      label: isArabic ? 'المعرّف' : 'User ID',
      valueWidget: Text(
        publicUserId,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
    ));

    if (country.isNotEmpty) {
      rows.add(_InfoRowData(
        label: isArabic ? 'الدولة' : 'Country',
        valueWidget: Text(
          country,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ));
    }

    if (gender.isNotEmpty) {
      rows.add(_InfoRowData(
        label: isArabic ? 'الجنس' : 'Gender',
        valueWidget: Text(
          _localiseGender(gender),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ));
    }

    if (createdAt != null) {
      rows.add(_InfoRowData(
        label: isArabic ? 'الانضمام' : 'Joined',
        valueWidget: Text(
          _formatJoined(createdAt!),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ));
    }

    if (vipLevel > 0) {
      rows.add(_InfoRowData(
        label: isArabic ? 'مستوى VIP' : 'VIP Level',
        valueWidget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              colors: [Color(0xFFDAA520), Color(0xFFFAD166)],
            ),
          ),
          child: Text(
            'VIP $vipLevel',
            style: const TextStyle(
              color: Color(0xFF3D1C00),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ));
    }

    if (isGoldenId) {
      rows.add(_InfoRowData(
        label: isArabic ? 'المعرّف الذهبي' : 'Golden ID',
        valueWidget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _gold.withValues(alpha: 0.14),
            border: Border.all(color: _gold.withValues(alpha: 0.55)),
          ),
          child: Text(
            isArabic ? 'نشط' : 'Active',
            style: TextStyle(
              color: _gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ));
    }

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(
            icon: Icons.info_outline_rounded,
            label: isArabic ? 'المعلومات' : 'Information',
            iconColor: _purple,
            isArabic: isArabic,
          ),
          const SizedBox(height: 14),
          Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: rows
                  .map(
                    (r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              r.label,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.48),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: r.valueWidget),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData({required this.label, required this.valueWidget});
  final String label;
  final Widget valueWidget;
}

// -----------------------------------------------------------------------------
// Level Progress Card (P5)
// -----------------------------------------------------------------------------

class _ProfileLevelProgressCard extends StatelessWidget {
  const _ProfileLevelProgressCard({
    required this.isArabic,
    this.userLevel,
    this.charmLevel,
    this.wealthLevel,
  });

  final bool isArabic;
  final UserLevel? userLevel;
  final int? charmLevel;
  final int? wealthLevel;

  static const _purple = Color(0xFF8B26D9);
  static const _purple2 = Color(0xFF5A28A0);
  static const _gold = Color(0xFFF0C15A);

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(
            icon: Icons.trending_up_rounded,
            label: isArabic ? 'مستوى التقدم' : 'Level Progress',
            iconColor: _gold,
            isArabic: isArabic,
          ),
          const SizedBox(height: 14),
          if (userLevel == null) _emptyState() else _content(userLevel!),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.18),
        border: Border.all(color: _purple.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart_rounded,
              color: _gold.withValues(alpha: 0.5), size: 18),
          const SizedBox(width: 8),
          Text(
            isArabic ? 'التقدم قريباً' : 'Progress coming soon',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(UserLevel ul) {
    final progress = ul.levelProgress?.clamp(0.0, 1.0) ?? 0.0;
    final hasProgress = ul.levelProgress != null;
    final pct = (progress * 100).round();
    final title = ul.currentLevelTitle;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level badge + title + xp
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [_purple, _purple2],
                  ),
                ),
                child: Text(
                  '${isArabic ? 'المستوى ' : 'Lv '}${ul.level}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (title != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '${ul.xp} XP',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // Progress bar
          if (hasProgress) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LayoutBuilder(
                builder: (_, constraints) => Stack(
                  children: [
                    Container(
                      height: 8,
                      width: double.infinity,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Container(
                      height: 8,
                      width: constraints.maxWidth * progress,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_purple, _gold],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$pct%',
                  style: TextStyle(
                    color: _gold.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (ul.nextLevel != null)
                  Text(
                    '${isArabic ? 'التالي: مستوى ' : 'Next: Lv '}${ul.nextLevel}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.38),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],

          // Charm + Wealth summary
          if (charmLevel != null || wealthLevel != null) ...[
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: const Color(0xFF7040B8).withValues(alpha: 0.26),
              margin: const EdgeInsets.only(bottom: 10),
            ),
            Row(
              children: [
                if (charmLevel != null)
                  Expanded(
                    child: _MiniStatChip(
                      icon: Icons.favorite_rounded,
                      iconColor: const Color(0xFFFF7BAC),
                      label: isArabic ? 'السحر' : 'Charm',
                      value: 'Lv $charmLevel',
                      isArabic: isArabic,
                    ),
                  ),
                if (charmLevel != null && wealthLevel != null)
                  const SizedBox(width: 8),
                if (wealthLevel != null)
                  Expanded(
                    child: _MiniStatChip(
                      icon: Icons.monetization_on_rounded,
                      iconColor: _gold,
                      label: isArabic ? 'الثروة' : 'Wealth',
                      value: 'Lv $wealthLevel',
                      isArabic: isArabic,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.isArabic,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: iconColor.withValues(alpha: 0.24)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

// -----------------------------------------------------------------------------

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E0D36), Color(0xFF130820), Color(0xFF0E061A)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: const Color(0xFF7040B8).withValues(alpha: 0.45),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

// Shared card header row
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.isArabic,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.14),
          ),
          child: Icon(icon, color: iconColor, size: 15),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// Thin vertical divider for the gift wall row
class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: const Color(0xFF7040B8).withValues(alpha: 0.35),
    );
  }
}

// -----------------------------------------------------------------------------
// Moments / Gallery Card
// -----------------------------------------------------------------------------

class _ProfileMomentsCard extends StatelessWidget {
  const _ProfileMomentsCard({required this.isArabic});

  final bool isArabic;

  // No moments data exists in the app yet — this renders a premium empty state
  // that communicates the feature and looks polished.  When a moments backend
  // is added the tile grid below can be swapped in without touching the shell.

  static const _purple  = Color(0xFF8B26D9);
  static const _purple2 = Color(0xFF5A28A0);
  static const _gold    = Color(0xFFF0C15A);

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _purple.withValues(alpha: 0.18),
                ),
                child: const Icon(
                  Icons.auto_awesome_mosaic_rounded,
                  color: _purple,
                  size: 15,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isArabic ? 'اللحظات' : 'Moments',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Empty-state body
          LayoutBuilder(
            builder: (context, constraints) {
              final tileSize = (constraints.maxWidth - 8 * 2) / 3;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ghost tile row — 3 placeholder tiles that hint at the grid
                  // layout without showing fake content.
                  Row(
                    textDirection:
                        isArabic ? TextDirection.rtl : TextDirection.ltr,
                    children: List.generate(3, (i) {
                      return Padding(
                        padding: EdgeInsets.only(
                          right: isArabic ? 0 : (i < 2 ? 8 : 0),
                          left:  isArabic ? (i < 2 ? 8 : 0) : 0,
                        ),
                        child: _GhostTile(
                          size: tileSize,
                          opacity: 1.0 - i * 0.22,
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),

                  // Empty state message
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black.withValues(alpha: 0.22),
                      border: Border.all(
                        color: _purple.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Camera icon with soft glow ring
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                _purple.withValues(alpha: 0.28),
                                _purple.withValues(alpha: 0.08),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                            border: Border.all(
                              color: _purple.withValues(alpha: 0.40),
                              width: 1.0,
                            ),
                          ),
                          child: Icon(
                            Icons.add_a_photo_rounded,
                            color: _purple2.withValues(alpha: 0.80),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isArabic
                              ? 'لا توجد لحظات بعد'
                              : 'No moments yet',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isArabic
                              ? 'شارك لحظاتك مع مجتمع سرود لايف'
                              : 'Share your moments with the Srood Live community',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // "Coming soon" pill — passive, non-tappable
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _purple.withValues(alpha: 0.35),
                                _purple2.withValues(alpha: 0.25),
                              ],
                            ),
                            border: Border.all(
                              color: _purple.withValues(alpha: 0.50),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                color: _gold.withValues(alpha: 0.75),
                                size: 13,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isArabic ? 'قريباً' : 'Coming soon',
                                style: TextStyle(
                                  color: _gold.withValues(alpha: 0.82),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// Ghost tile — decorative placeholder that shows the grid skeleton without
// displaying any fake content.
class _GhostTile extends StatelessWidget {
  const _GhostTile({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.15, 1.0),
      child: Container(
        width: size,
        height: size * 0.88, // slight landscape ratio
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1250), Color(0xFF1A0B38)],
          ),
          border: Border.all(
            color: const Color(0xFF7040B8).withValues(alpha: 0.35),
          ),
        ),
        child: Stack(
          children: [
            // Top-left shimmer accent
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                width: 24,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            // Centre icon hint
            Center(
              child: Icon(
                Icons.image_rounded,
                color: Colors.white.withValues(alpha: 0.08),
                size: size * 0.30,
              ),
            ),
            // Bottom shimmer bar
            Positioned(
              bottom: 7,
              left: 6,
              right: 6,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

String _formatCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}

bool _isPremiumFrameKey(String? key) {
  if (key == null || key.isEmpty) return false;
  return key.startsWith('luxury_') ||
      key.startsWith('custom_') ||
      key.startsWith('vip_');
}
