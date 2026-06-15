import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/utils/vip_visuals.dart';
import '../../shared/widgets/avatar_with_frame.dart';
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
import '../games/screens/srood_loto_screen.dart';
import 'models/avatar_frame.dart';
import 'screens/follow_list_screen.dart';
import 'services/follow_service.dart';

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

// ─────────────────────────────────────────────────────────────────────────────

class _ProfileScreenState extends State<ProfileScreen> {
  final usernameController = TextEditingController();
  final displayNameController = TextEditingController();
  final birthDateController = TextEditingController();
  final bioController = TextEditingController();
  final countryController = TextEditingController();
  final genderController = TextEditingController();
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
  int giftsReceivedCount = 0;
  int visitorsCount = 0;
  UserWallet? wallet;

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
          errorMessage = widget.isArabic
              ? 'لا يوجد مستخدم مسجل.'
              : 'No logged-in user found.';
        });
        return;
      }

      final data = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
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
      genderController.text = data['gender']?.toString() ?? '';

      int followers = 0;
      int following = 0;
      try {
        followers = await _followService.followersCount(user.id);
        following = await _followService.followingCount(user.id);
      } catch (_) {}

      final gifts = await _safeGiftCount(user.id);
      final loadedWallet = await _safeEnsureWallet(user.id);

      setState(() {
        profile = data;
        avatarFrames = frames;
        followersCount = _intFromProfile(
          data,
          'followers_count',
          fallback: followers,
        );
        followingCount = _intFromProfile(
          data,
          'following_count',
          fallback: following,
        );
        giftsReceivedCount = _intFromProfile(
          data,
          'gifts_received_count',
          fallback: gifts,
        );
        visitorsCount = _intFromProfile(data, 'visitors_count');
        wallet = loadedWallet;
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
        errorMessage = widget.isArabic
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
        content: Text(widget.isArabic ? 'قريباً' : 'Coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openWalletScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletScreen(isArabic: widget.isArabic),
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
          builder: (_) => RoomDetailsScreen(
            room: result.room,
            isArabic: widget.isArabic,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isArabic ? 'فشل فتح الغرفة: $e' : 'Failed to open room: $e',
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
      MaterialPageRoute(builder: (_) => StoreScreen(isArabic: widget.isArabic)),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openCheckin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckinScreen(isArabic: widget.isArabic),
      ),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openBackpack() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BackpackScreen(isArabic: widget.isArabic),
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
          isArabic: widget.isArabic,
          currentVipLevel: _effectiveProfileVipLevel(),
          vipExpiresAt: expiresAt,
        ),
      ),
    );
  }

  Future<void> _openLoto() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SroodLotoScreen(isArabic: widget.isArabic),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12091D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          widget.isArabic ? 'تسجيل الخروج' : 'Sign Out',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          textAlign: widget.isArabic ? TextAlign.right : TextAlign.left,
        ),
        content: Text(
          widget.isArabic
              ? 'هل أنت متأكد أنك تريد تسجيل الخروج؟'
              : 'Are you sure you want to sign out?',
          style: const TextStyle(color: Color(0xFFBCAED6)),
          textAlign: widget.isArabic ? TextAlign.right : TextAlign.left,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              widget.isArabic ? 'إلغاء' : 'Cancel',
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
            child: Text(widget.isArabic ? 'خروج' : 'Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await SupabaseService.requiredClient.auth.signOut();
    }
  }

  Future<void> _copyPublicId(String publicUserId) async {
    await Clipboard.setData(ClipboardData(text: publicUserId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isArabic ? 'تم نسخ المعرف' : 'ID copied'),
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
                    crossAxisAlignment: widget.isArabic
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isArabic ? 'تعديل الملف' : 'Edit Profile',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ProfileInput(
                        controller: displayNameController,
                        label: widget.isArabic ? 'اللقب' : 'Nickname',
                        isArabic: widget.isArabic,
                      ),
                      _ProfileInput(
                        controller: birthDateController,
                        label: widget.isArabic
                            ? 'تاريخ الميلاد'
                            : 'Date of birth',
                        isArabic: widget.isArabic,
                        readOnly: true,
                        onTap: _pickBirthDate,
                      ),
                      _ProfileInput(
                        controller: countryController,
                        label: widget.isArabic ? 'الدولة' : 'Country',
                        isArabic: widget.isArabic,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Directionality(
                          textDirection: widget.isArabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedGender,
                            decoration: InputDecoration(
                              labelText:
                                  widget.isArabic ? 'الجنس' : 'Gender',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            items: List.generate(genderOptions.length, (i) {
                              return DropdownMenuItem(
                                value: genderOptions[i],
                                child: Text(
                                  widget.isArabic
                                      ? genderLabelsAr[i]
                                      : genderLabelsEn[i],
                                ),
                              );
                            }),
                            onChanged: (v) {
                              setSheetState(() {
                                genderController.text = v ?? '';
                              });
                            },
                          ),
                        ),
                      ),
                      _ProfileInput(
                        controller: bioController,
                        label: widget.isArabic ? 'النبذة' : 'Bio',
                        isArabic: widget.isArabic,
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
                                ? (widget.isArabic
                                      ? 'جار الحفظ...'
                                      : 'Saving...')
                                : (widget.isArabic
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

  String _avatarExtension(String fileName, String? mimeType) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png') || mimeType == 'image/png') return 'png';
    if (lowerName.endsWith('.webp') || mimeType == 'image/webp') return 'webp';
    if (lowerName.endsWith('.gif') || mimeType == 'image/gif') return 'gif';
    return 'jpg';
  }

  String _avatarContentType(String extension, String? mimeType) {
    if (mimeType != null && mimeType.startsWith('image/')) return mimeType;
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
      if (user == null) throw StateError('No logged-in user found.');

      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 900,
        maxHeight: 900,
      );
      if (image == null) return;

      final Uint8List bytes = await image.readAsBytes();
      final extension = _avatarExtension(image.name, image.mimeType);
      final path =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final contentType = _avatarContentType(extension, image.mimeType);

      await client.storage.from('avatars').uploadBinary(
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
        successMessage = isArabic ? 'تم تحديث الصورة.' : 'Profile image updated.';
      });
    } catch (error) {
      setState(() {
        errorMessage = isArabic ? 'فشل رفع الصورة: $error' : 'Image upload failed: $error';
      });
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
          isArabic: widget.isArabic,
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
        successMessage =
            widget.isArabic ? 'تم حفظ إطار الصورة.' : 'Avatar frame saved.';
      });
    } catch (error) {
      setState(() {
        errorMessage = widget.isArabic
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
    final isArabic = widget.isArabic;
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

      final values = {
        'username': currentUsername.isEmpty ? displayName : currentUsername,
        'display_name': displayName,
        'date_of_birth': dateOfBirth.isEmpty ? null : dateOfBirth,
        'bio': bio.isEmpty ? null : bio,
        'country': country.isEmpty ? null : country,
        'gender': gender.isEmpty ? null : gender,
        'updated_at': DateTime.now().toIso8601String(),
      };

      try {
        await client.from('profiles').update(values).eq('id', user.id);
      } catch (error) {
        final message = error.toString();
        if (!message.contains('date_of_birth') &&
            !message.contains('bio') &&
            !message.contains('country') &&
            !message.contains('gender')) {
          rethrow;
        }
        await client
            .from('profiles')
            .update({
              'username':
                  currentUsername.isEmpty ? displayName : currentUsername,
              'display_name': displayName,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);
      }

      await _loadProfile();
      setState(() {
        successMessage =
            isArabic ? 'تم حفظ الملف الشخصي.' : 'Profile saved.';
      });
    } catch (error) {
      setState(() {
        errorMessage = isArabic ? 'فشل الحفظ: $error' : 'Save failed: $error';
      });
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;

    if (isLoading) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final currentUserId =
        SupabaseService.requiredClient.auth.currentUser?.id ?? '';
    final avatarUrl = profile?['avatar_url']?.toString();
    final selectedAvatarFrameKey =
        profile?['selected_avatar_frame_key']?.toString();
    final publicUserId = _profileText(
      'public_user_id',
      fallback: currentUserId.length >= 8
          ? currentUserId.substring(0, 8)
          : (currentUserId.isEmpty ? '-' : currentUserId),
    );
    final effectiveVipLevel = _effectiveProfileVipLevel();
    final isGoldenId = isGoldenIdActive(
      profile?['is_golden_id'] == true,
      DateTime.tryParse(profile?['golden_id_expires_at']?.toString() ?? ''),
    );
    final coins = wallet?.coinsBalance ?? 0;
    final diamonds = wallet?.diamondsBalance ?? 0;
    final level = _intFromProfile(profile ?? {}, 'level', fallback: 1);
    final country = _profileText('country');
    final gender = _profileText('gender');
    final bio = _profileText('bio');
    final displayName = displayNameController.text.trim().isNotEmpty
        ? displayNameController.text.trim()
        : (usernameController.text.trim().isNotEmpty
              ? usernameController.text.trim()
              : (isArabic ? 'عضو سهرود' : 'SrOOd Member'));
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
                16, 12, 16,
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
                      vipLevel: effectiveVipLevel,
                      level: level,
                      isGoldenId: isGoldenId,
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
                      gifts: giftsReceivedCount,
                      onFollowersTap: uid == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => FollowListScreen(
                                    userId: uid,
                                    isFollowers: true,
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
                                    isFollowers: false,
                                    isArabic: isArabic,
                                  ),
                                ),
                              ),
                    ),
                    const SizedBox(height: 14),

                    // 3. Wallet Cards (Coins + Diamonds)
                    _WalletCards(
                      coins: coins,
                      diamonds: diamonds,
                      isArabic: isArabic,
                      isLoading: isLoading,
                      onCoinsTap: _openWalletScreen,
                      onDiamondsTap: _openWalletScreen,
                    ),
                    const SizedBox(height: 14),

                    // 4. VIP Banner
                    _VipUpgradeBanner(
                      vipLevel: effectiveVipLevel,
                      isArabic: isArabic,
                      onTap: _openVipCenter,
                    ),
                    const SizedBox(height: 14),

                    // 5. Quick Actions Grid (6 items)
                    _QuickActionsGrid(
                      isArabic: isArabic,
                      onVipCenter: _openVipCenter,
                      onStore: _openStore,
                      onBackpack: _openBackpack,
                      onLoto: _openLoto,
                      onMyRoom: _openMyRoom,
                      roomLoading: _roomLoading,
                      onSettings: () => _openProfileHub(
                        SettingsScreen(isArabic: isArabic),
                      ),
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
                    _DailyCheckinCard(
                      isArabic: isArabic,
                      onTap: _openCheckin,
                    ),
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
                    _LogoutButton(
                      isArabic: isArabic,
                      onTap: _confirmLogout,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Premium Profile Header
// ─────────────────────────────────────────────────────────────────────────────

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
  });

  final String displayName;
  final String publicUserId;
  final String? avatarUrl;
  final String? frameKey;
  final int vipLevel;
  final int level;
  final bool isGoldenId;
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
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment =
        isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final flag = _countryFlag(country);
    final subtitle = bio.isNotEmpty
        ? bio
        : (isArabic ? 'أهلاً بك في سرود لايف.' : 'Welcome to Srood Live.');

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 184),
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B105A), Color(0xFF180821), Color(0xFF2A0B35)],
        ),
        border: Border.all(
          color: const Color(0xFFF0C15A).withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
          ...VipVisualStyle.glow(vipLevel),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Background glow orb
          Positioned(
            right: isArabic ? null : -46,
            left: isArabic ? -46 : null,
            top: -42,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC13BFF).withValues(alpha: 0.16),
              ),
            ),
          ),
          // Edit button
          Positioned(
            right: isArabic ? null : 0,
            left: isArabic ? 0 : null,
            top: 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onEditTap,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.28),
                  border: Border.all(
                    color: const Color(0xFFF0C15A).withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  color: Color(0xFFF0C15A),
                  size: 17,
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
                    // Profile label chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection:
                            isArabic ? TextDirection.rtl : TextDirection.ltr,
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: Color(0xFFF0C15A),
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isArabic ? 'ملف سرود' : 'Srood Profile',
                            style: const TextStyle(
                              color: Color(0xFFD8CFEA),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    // Display name
                    Row(
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                      children: [
                        Expanded(
                          child: VipUsername(
                            name: displayName,
                            vipLevel: vipLevel,
                            fontSize: 29,
                            textAlign: textAlign,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    // Public ID
                    if (isGoldenId)
                      GoldenIdBadge(
                        idText: 'ID:$publicUserId',
                        onTap: onCopyId,
                        showCopyIcon: true,
                      )
                    else
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: onCopyId,
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF100718).withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFFF0C15A).withValues(alpha: 0.22),
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
                                color: Colors.white.withValues(alpha: 0.58),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    // Badges row
                    Wrap(
                      alignment:
                          isArabic ? WrapAlignment.end : WrapAlignment.start,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (flag.isNotEmpty)
                          _ProfileBadge(
                            icon: Icons.flag_rounded,
                            label: flag,
                            highlighted: false,
                          ),
                        if (vipLevel > 0) VipBadge(vipLevel: vipLevel),
                        _ProfileBadge(
                          icon: Icons.military_tech_rounded,
                          label: isArabic ? 'مستوى $level' : 'Lv. $level',
                          highlighted: false,
                        ),
                        if (gender.isNotEmpty)
                          _ProfileBadge(
                            icon: Icons.person_rounded,
                            label: gender,
                            highlighted: false,
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    // Bio / subtitle
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: textAlign,
                      style: const TextStyle(
                        color: Color(0xFFBCAED6),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Avatar with upload button
              SizedBox(
                width: 106,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onFrameTap,
                      child: AvatarWithFrame(
                        imageUrl: avatarUrl,
                        radius: 48,
                        frameKey: frameKey,
                        vipLevel: vipLevel,
                        showVipBadge: vipLevel > 0,
                        compact: true,
                      ),
                    ),
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: isUploadingAvatar ? null : onAvatarTap,
                        child: Container(
                          width: 31,
                          height: 31,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF0C15A),
                            border: Border.all(
                              color: const Color(0xFF160B26),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            isUploadingAvatar
                                ? Icons.hourglass_top_rounded
                                : Icons.camera_alt_rounded,
                            color: const Color(0xFF160B26),
                            size: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _countryFlag(String value) {
    final c = value.trim().toLowerCase();
    if (c.isEmpty) return '';
    if (c.contains('leban') || c.contains('لبن')) return '🇱🇧 Lebanon';
    if (c.contains('saudi') || c.contains('سعو')) return '🇸🇦 KSA';
    if (c.contains('emir') || c.contains('uae') || c.contains('إمار')) {
      return '🇦🇪 UAE';
    }
    if (c.contains('kuwait') || c.contains('كويت')) return '🇰🇼 Kuwait';
    if (c.contains('qatar') || c.contains('قطر')) return '🇶🇦 Qatar';
    if (c.contains('bahrain') || c.contains('بحرين')) return '🇧🇭 Bahrain';
    if (c.contains('oman') || c.contains('عُمان')) return '🇴🇲 Oman';
    if (c.contains('jordan') || c.contains('الأردن')) return '🇯🇴 Jordan';
    if (c.contains('syria') || c.contains('سوري')) return '🇸🇾 Syria';
    if (c.contains('iraq') || c.contains('عراق')) return '🇮🇶 Iraq';
    if (c.contains('egypt') || c.contains('مصر')) return '🇪🇬 Egypt';
    if (c.contains('morocco') || c.contains('المغرب')) return '🇲🇦 Morocco';
    if (c.contains('tunisia') || c.contains('تونس')) return '🇹🇳 Tunisia';
    if (c.contains('algeria') || c.contains('الجزائر')) return '🇩🇿 Algeria';
    return value;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Row — Friends / Following / Followers
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileStatsRow extends StatelessWidget {
  const _ProfileStatsRow({
    required this.isArabic,
    required this.followers,
    required this.following,
    required this.gifts,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  final bool isArabic;
  final int followers;
  final int following;
  final int gifts;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Friends (gifts received as closest proxy)
          ProfileStatItem(
            value: gifts,
            label: isArabic ? 'الأصدقاء' : 'Friends',
            tappable: false,
          ),
          _StatDivider(),
          // Following
          GestureDetector(
            onTap: onFollowingTap,
            child: ProfileStatItem(
              value: following,
              label: isArabic ? 'المتابَعون' : 'Following',
              tappable: onFollowingTap != null,
            ),
          ),
          _StatDivider(),
          // Followers
          GestureDetector(
            onTap: onFollowersTap,
            child: ProfileStatItem(
              value: followers,
              label: isArabic ? 'المتابعون' : 'Followers',
              tappable: onFollowersTap != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      color: const Color(0xFF4A3470).withValues(alpha: 0.6),
    );
  }
}

class ProfileStatItem extends StatelessWidget {
  const ProfileStatItem({
    required this.value,
    required this.label,
    this.tappable = false,
    super.key,
  });

  final int value;
  final String label;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatCount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tappable
                      ? const Color(0xFFF0C15A)
                      : const Color(0xFFB9A9D4),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (tappable)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 13,
                  color: Color(0xFFF0C15A),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wallet Cards
// ─────────────────────────────────────────────────────────────────────────────

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
            label: isArabic ? 'العملات' : 'Coins',
            value: coins,
            isLoading: isLoading,
            colors: const [Color(0xFFFFD978), Color(0xFFC9871C)],
            glowColor: Color(0xFFF0C15A),
            onTap: onCoinsTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: WalletBalanceCard(
            icon: Icons.diamond_rounded,
            label: isArabic ? 'الألماس' : 'Diamonds',
            value: diamonds,
            isLoading: isLoading,
            colors: const [Color(0xFFE4B5FF), Color(0xFF7D2BFF)],
            glowColor: Color(0xFFB875FF),
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
    this.isLoading = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final int value;
  final List<Color> colors;
  final Color glowColor;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          border: Border.all(
            color: glowColor.withValues(alpha: 0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF160B26), size: 20),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: const Color(0xFF160B26).withValues(alpha: 0.5),
                  size: 12,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  Container(
                    width: 60,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF160B26).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                else
                  Text(
                    _formatCount(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF160B26),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF160B26),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIP Banner
// ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.all(14),
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
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Actions Grid — 6 items in 3×2 layout
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.isArabic,
    required this.onVipCenter,
    required this.onStore,
    required this.onBackpack,
    required this.onLoto,
    required this.onMyRoom,
    required this.onSettings,
    required this.roomLoading,
  });

  final bool isArabic;
  final VoidCallback onVipCenter;
  final VoidCallback onStore;
  final VoidCallback onBackpack;
  final VoidCallback onLoto;
  final VoidCallback onMyRoom;
  final VoidCallback onSettings;
  final bool roomLoading;

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
      _FeatureTileData(
        icon: Icons.confirmation_number_rounded,
        label: isArabic ? 'سحب سرود' : 'Srood Draw',
        onTap: onLoto,
        gradientColors: const [Color(0xFFE4B5FF), Color(0xFF7D2BFF)],
      ),
      _FeatureTileData(
        icon: roomLoading ? Icons.hourglass_top_rounded : Icons.home_rounded,
        label: isArabic ? 'غرفتي' : 'My Room',
        onTap: onMyRoom,
        gradientColors: const [Color(0xFF8B26D9), Color(0xFF4A1478)],
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
  const _ProfileFeatureTile({
    required this.data,
    required this.isArabic,
  });

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
                  child: Icon(
                    data.icon,
                    color: Colors.white,
                    size: 24,
                  ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Account & Support Section — Wallet, Customer Service, Privacy
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Daily Check-in Card
// ─────────────────────────────────────────────────────────────────────────────

class _DailyCheckinCard extends StatelessWidget {
  const _DailyCheckinCard({
    required this.isArabic,
    required this.onTap,
  });

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

// ─────────────────────────────────────────────────────────────────────────────
// Love / Relationship Card (coming soon placeholder)
// ─────────────────────────────────────────────────────────────────────────────

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
                      : 'Find your soulmate on Srood Live',
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

// ─────────────────────────────────────────────────────────────────────────────
// Section card container with title
// ─────────────────────────────────────────────────────────────────────────────

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
              textDirection:
                  isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Icon(icon, color: const Color(0xFFF0C15A), size: 16),
                const SizedBox(width: 6),
                Text(
                  title,
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

// ─────────────────────────────────────────────────────────────────────────────
// Profile List Row
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Logout Button
// ─────────────────────────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({
    required this.isArabic,
    required this.onTap,
  });

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

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

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
        style: const TextStyle(
          color: Color(0xFF160B26),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
            size: 13,
            color: highlighted ? const Color(0xFFF0C15A) : Colors.white,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: highlighted ? const Color(0xFFF0C15A) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
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
          color:
              isSuccess ? const Color(0xFF2ECC71) : const Color(0xFFFF5C7A),
        ),
      ),
      child: Text(
        message,
        textAlign: isArabic ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color:
              isSuccess ? const Color(0xFF2ECC71) : const Color(0xFFFF5C7A),
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

// ─────────────────────────────────────────────────────────────────────────────
// Avatar Frame Picker (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

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
                selected:
                    selectedFrameKey == null || selectedFrameKey!.isEmpty,
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
                frames:
                    frames.where((frame) => frame.category == 'vip').toList(),
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
              childAspectRatio: 0.78,
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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2D1247) : const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                selected ? const Color(0xFFF0C15A) : const Color(0xFF4A3470),
          ),
        ),
        child: Column(
          children: [
            AvatarWithFrame(
              imageUrl: avatarUrl,
              radius: 28,
              frameKey: frame?.frameKey,
              vipLevel: vipLevel,
              showVipBadge: false,
            ),
            const SizedBox(height: 8),
            Text(
              frame?.name ?? (isArabic ? 'بدون إطار' : 'No Frame'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              unlocked
                  ? (selected ? (isArabic ? 'محدد' : 'Selected') : '')
                  : (isArabic
                        ? 'VIP ${requiredVip ?? 1}'
                        : 'Requires VIP ${requiredVip ?? 1}'),
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

// ─────────────────────────────────────────────────────────────────────────────
// Utilities
// ─────────────────────────────────────────────────────────────────────────────

String _formatCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
