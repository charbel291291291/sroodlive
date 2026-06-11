import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/utils/vip_visuals.dart';
import '../../shared/widgets/avatar_with_frame.dart';
import '../../shared/widgets/vip_badge.dart';
import '../../shared/widgets/vip_username.dart';
import '../profile_hub/screens/badge_screen.dart';
import '../profile_hub/screens/customer_service_screen.dart';
import '../profile_hub/screens/feedback_screen.dart';
import '../profile_hub/screens/my_agency_screen.dart';
import '../profile_hub/screens/my_income_screen.dart';
import '../profile_hub/screens/my_level_screen.dart';
import '../profile_hub/screens/settings_screen.dart';
import '../profile_hub/widgets/profile_hub_widgets.dart';
import '../gamification/screens/backpack_screen.dart';
import '../gamification/screens/checkin_screen.dart';
import '../gamification/screens/store_screen.dart';
import '../gamification/screens/tasks_screen.dart';
import '../gamification/screens/vip_center_screen.dart';
import '../wallet/models/wallet.dart';
import '../wallet/screens/wallet_screen.dart';
import '../wallet/services/wallet_service.dart';
import '../rooms/utils/vip_room_features.dart';
import 'models/avatar_frame.dart';
import 'screens/follow_list_screen.dart';
import 'services/follow_service.dart';
import '../social/screens/leaderboard_screen.dart';

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

class _ProfileScreenState extends State<ProfileScreen> {
  final usernameController = TextEditingController();
  final displayNameController = TextEditingController();
  final birthDateController = TextEditingController();
  final bioController = TextEditingController();
  final FollowService _followService = const FollowService();
  final WalletService _walletService = const WalletService();

  bool isLoading = true;
  bool isSaving = false;
  bool isUploadingAvatar = false;
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
              ? '\u0644\u0627 \u064a\u0648\u062c\u062f \u0645\u0633\u062a\u062e\u062f\u0645 \u0645\u0633\u062c\u0644.'
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
      final followers = await _followService.followersCount(user.id);
      final following = await _followService.followingCount(user.id);
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
            ? '\u0641\u0634\u0644 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0645\u0644\u0641 \u0627\u0644\u0634\u062e\u0635\u064a: $error'
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

    if (value is num) {
      return value.toInt();
    }

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

  void _showSoon(String english, String arabic) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.isArabic ? arabic : english)));
  }

  Future<void> _openWalletScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletScreen(isArabic: widget.isArabic),
      ),
    );

    if (mounted) {
      await _loadProfile();
    }
  }

  Future<void> _openProfileHub(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    if (mounted) {
      await _loadProfile();
    }
  }

  Future<void> _openStore() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoreScreen(isArabic: widget.isArabic)),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openTasks() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TasksScreen(isArabic: widget.isArabic)),
    );
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

  Future<void> _copyPublicId(String publicUserId) async {
    await Clipboard.setData(ClipboardData(text: publicUserId));

    if (!mounted) return;

    _showSoon(
      'ID copied',
      '\u062a\u0645 \u0646\u0633\u062e \u0627\u0644\u0631\u0642\u0645',
    );
  }

  Future<void> _showEditProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF100718),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
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
                    widget.isArabic
                        ? '\u062a\u0639\u062f\u064a\u0644 \u0627\u0644\u0645\u0644\u0641'
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
                    label: widget.isArabic
                        ? '\u0627\u0644\u0644\u0642\u0628'
                        : 'Nickname',
                    isArabic: widget.isArabic,
                  ),
                  _ProfileInput(
                    controller: birthDateController,
                    label: widget.isArabic
                        ? '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0645\u064a\u0644\u0627\u062f'
                        : 'Date of birth',
                    isArabic: widget.isArabic,
                    readOnly: true,
                    onTap: _pickBirthDate,
                  ),
                  _ProfileInput(
                    controller: bioController,
                    label: widget.isArabic
                        ? '\u0627\u0644\u0646\u0628\u0630\u0629'
                        : 'Bio',
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
                                  ? '\u062c\u0627\u0631 \u0627\u0644\u062d\u0641\u0638...'
                                  : 'Saving...')
                            : (widget.isArabic
                                  ? '\u062d\u0641\u0638 \u0627\u0644\u062a\u063a\u064a\u064a\u0631\u0627\u062a'
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

    if (!mounted || selected == selectedFrameKey) {
      return;
    }

    try {
      final client = SupabaseService.requiredClient;
      final user = client.auth.currentUser;

      if (user == null) {
        throw StateError('No logged-in user found.');
      }

      await client
          .from('profiles')
          .update({
            'selected_avatar_frame_key': selected,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      await _loadProfile();

      setState(() {
        successMessage = widget.isArabic
            ? '\u062a\u0645 \u062d\u0641\u0638 \u0625\u0637\u0627\u0631 \u0627\u0644\u0635\u0648\u0631\u0629.'
            : 'Avatar frame saved.';
      });
    } catch (error) {
      setState(() {
        errorMessage = widget.isArabic
            ? '\u0641\u0634\u0644 \u062d\u0641\u0638 \u0627\u0644\u0625\u0637\u0627\u0631: $error'
            : 'Frame save failed: $error';
      });
    }
  }

  DateTime? _profileVipExpiresAt() {
    final value = profile?['vip_expires_at'];

    if (value == null) {
      return null;
    }

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

    final currentUserId =
        SupabaseService.requiredClient.auth.currentUser?.id ?? '';
    final email = profile?['email']?.toString() ?? '-';
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
    final isGoldenId = isGoldenIdActive(
      profile?['is_golden_id'] == true,
      DateTime.tryParse(profile?['golden_id_expires_at']?.toString() ?? ''),
    );
    final coins = wallet?.coinsBalance ?? 0;
    final diamonds = wallet?.diamondsBalance ?? 0;
    final country = _profileText('country');
    final gender = _profileText('gender');
    final bio = _profileText('bio');
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
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: RefreshIndicator(
                  onRefresh: _loadProfile,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 142),
                    child: Column(
                      children: [
                        _PremiumProfileHero(
                          displayName: displayName,
                          publicUserId: publicUserId,
                          avatarUrl: avatarUrl,
                          frameKey: selectedAvatarFrameKey,
                          vipLevel: effectiveVipLevel,
                          isGoldenId: isGoldenId,
                          country: country,
                          gender: gender,
                          bio: bio,
                          email: email,
                          isUploadingAvatar: isUploadingAvatar,
                          isArabic: isArabic,
                          onAvatarTap: _uploadAvatar,
                          onEditTap: _showEditProfileSheet,
                          onFrameTap: _chooseAvatarFrame,
                          onCopyId: () => _copyPublicId(publicUserId),
                        ),
                        const SizedBox(height: 14),
                        _ProfileStatsRow(
                          isArabic: isArabic,
                          followers: followersCount,
                          following: followingCount,
                          gifts: giftsReceivedCount,
                          visitors: visitorsCount,
                          onFollowersTap: () {
                            final uid = SupabaseService
                                .requiredClient
                                .auth
                                .currentUser
                                ?.id;
                            if (uid == null) return;
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FollowListScreen(
                                  userId: uid,
                                  isFollowers: true,
                                  isArabic: isArabic,
                                ),
                              ),
                            );
                          },
                          onFollowingTap: () {
                            final uid = SupabaseService
                                .requiredClient
                                .auth
                                .currentUser
                                ?.id;
                            if (uid == null) return;
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FollowListScreen(
                                  userId: uid,
                                  isFollowers: false,
                                  isArabic: isArabic,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        _VipUpgradeBanner(
                          vipLevel: effectiveVipLevel,
                          isArabic: isArabic,
                          onTap: _openVipCenter,
                        ),
                        const SizedBox(height: 14),
                        _BalanceCards(
                          coins: coins,
                          diamonds: diamonds,
                          isArabic: isArabic,
                          onCoinsTap: _openWalletScreen,
                          onDiamondsTap: _openWalletScreen,
                        ),
                        const SizedBox(height: 14),
                        _ShortcutGrid(
                          isArabic: isArabic,
                          onStore: _openStore,
                          onTask: _openTasks,
                          onCheckIn: _openCheckin,
                          onBackpack: _openBackpack,
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
                        const SizedBox(height: 14),
                        _ProfileMenuList(
                          isArabic: isArabic,
                          onLevel: () => _openProfileHub(
                            MyLevelScreen(isArabic: isArabic),
                          ),
                          onAgency: () => _openProfileHub(
                            MyAgencyScreen(isArabic: isArabic),
                          ),
                          onIncome: () => _openProfileHub(
                            MyIncomeScreen(isArabic: isArabic),
                          ),
                          onBadge: () =>
                              _openProfileHub(BadgeScreen(isArabic: isArabic)),
                          onLeaderboard: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  LeaderboardScreen(isArabic: isArabic),
                            ),
                          ),
                          onFeedback: () => _openProfileHub(
                            FeedbackScreen(isArabic: isArabic),
                          ),
                          onCustomerService: () => _openProfileHub(
                            CustomerServiceScreen(isArabic: isArabic),
                          ),
                          onSettings: () => _openProfileHub(
                            SettingsScreen(isArabic: isArabic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumProfileHero extends StatelessWidget {
  const _PremiumProfileHero({
    required this.displayName,
    required this.publicUserId,
    required this.avatarUrl,
    required this.frameKey,
    required this.vipLevel,
    required this.isGoldenId,
    required this.country,
    required this.gender,
    required this.bio,
    required this.email,
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
  final bool isGoldenId;
  final String country;
  final String gender;
  final String bio;
  final String email;
  final bool isUploadingAvatar;
  final bool isArabic;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditTap;
  final VoidCallback onFrameTap;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    final textAlign = isArabic ? TextAlign.right : TextAlign.left;
    final crossAxisAlignment = isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final flag = _countryFlag(country);
    final subtitle = bio.isNotEmpty
        ? bio
        : (isArabic
              ? '\u0623\u0647\u0644\u0627\u064b \u0628\u0643 \u0641\u064a SrOOd Live.'
              : 'Welcome to SrOOd Live.');

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
                        textDirection: isArabic
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: Color(0xFFF0C15A),
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isArabic
                                ? '\u0645\u0644\u0641 SrOOd'
                                : 'SrOOd Profile',
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
                    Row(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
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
                                color: Colors.white.withValues(alpha: 0.58),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: isArabic
                          ? WrapAlignment.end
                          : WrapAlignment.start,
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
                          label: isArabic
                              ? '\u0645\u0633\u062a\u0648\u0649 1'
                              : 'Lv. 1',
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
    final country = value.trim().toLowerCase();

    if (country.isEmpty) {
      return '';
    }

    if (country.contains('leban') || country.contains('\u0644\u0628\u0646')) {
      return '\u{1F1F1}\u{1F1E7} Lebanon';
    }

    return value;
  }
}

class _ProfileStatsRow extends StatelessWidget {
  const _ProfileStatsRow({
    required this.isArabic,
    required this.followers,
    required this.following,
    required this.gifts,
    required this.visitors,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  final bool isArabic;
  final int followers;
  final int following;
  final int gifts;
  final int visitors;
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
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          GestureDetector(
            onTap: onFollowersTap,
            child: _ProfileStatItem(
              value: followers,
              label: isArabic
                  ? '\u0645\u062a\u0627\u0628\u0639\u0648\u0646'
                  : 'Followers',
              tappable: onFollowersTap != null,
            ),
          ),
          GestureDetector(
            onTap: onFollowingTap,
            child: _ProfileStatItem(
              value: following,
              label: isArabic ? '\u064a\u062a\u0627\u0628\u0639' : 'Following',
              tappable: onFollowingTap != null,
            ),
          ),
          _ProfileStatItem(
            value: gifts,
            label: isArabic ? '\u0647\u062f\u0627\u064a\u0627' : 'Gifts',
          ),
          _ProfileStatItem(
            value: visitors,
            label: isArabic ? '\u0632\u0648\u0627\u0631' : 'Visitors',
          ),
        ],
      ),
    );
  }
}

class _ProfileStatItem extends StatelessWidget {
  const _ProfileStatItem({
    required this.value,
    required this.label,
    this.tappable = false,
  });

  final int value;
  final String label;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
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
          gradient: LinearGradient(
            colors: active
                ? VipVisualStyle.gradient(vipLevel)
                : const [Color(0xFF32194A), Color(0xFF7D2BFF)],
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
                    active ? 'VIP Lv$vipLevel Active' : 'VIP',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isArabic
                        ? '\u0627\u0641\u062a\u062d \u062a\u062c\u0631\u0628\u0629 \u0645\u0645\u064a\u0632\u0629'
                        : 'Unlock Premium Experience',
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
            _GoldMiniButton(label: active ? 'Manage' : 'Upgrade Now'),
          ],
        ),
      ),
    );
  }
}

class _BalanceCards extends StatelessWidget {
  const _BalanceCards({
    required this.coins,
    required this.diamonds,
    required this.isArabic,
    required this.onCoinsTap,
    required this.onDiamondsTap,
  });

  final int coins;
  final int diamonds;
  final bool isArabic;
  final VoidCallback onCoinsTap;
  final VoidCallback onDiamondsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Expanded(
          child: _BalanceCard(
            icon: Icons.monetization_on_rounded,
            label: isArabic
                ? '\u0627\u0644\u0639\u0645\u0644\u0627\u062a'
                : 'Coins',
            value: coins,
            colors: const [Color(0xFFFFD978), Color(0xFFC9871C)],
            onTap: onCoinsTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BalanceCard(
            icon: Icons.diamond_rounded,
            label: isArabic
                ? '\u0627\u0644\u0623\u0644\u0645\u0627\u0633'
                : 'Diamonds',
            value: diamonds,
            colors: const [Color(0xFFE4B5FF), Color(0xFF7D2BFF)],
            onTap: onDiamondsTap,
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 90,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(colors: colors),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: const Color(0xFF160B26), size: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatCount(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF160B26),
                    fontSize: 18,
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

class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid({
    required this.isArabic,
    required this.onStore,
    required this.onTask,
    required this.onCheckIn,
    required this.onBackpack,
  });

  final bool isArabic;
  final VoidCallback onStore;
  final VoidCallback onTask;
  final VoidCallback onCheckIn;
  final VoidCallback onBackpack;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ShortcutData(
        Icons.storefront_rounded,
        isArabic ? '\u0627\u0644\u0645\u062a\u062c\u0631' : 'Store',
        onStore,
      ),
      _ShortcutData(
        Icons.task_alt_rounded,
        isArabic ? '\u0645\u0647\u0627\u0645' : 'Task',
        onTask,
      ),
      _ShortcutData(
        Icons.event_available_rounded,
        isArabic ? '\u062d\u0636\u0648\u0631' : 'Check in',
        onCheckIn,
      ),
      _ShortcutData(
        Icons.backpack_rounded,
        isArabic ? '\u062d\u0642\u064a\u0628\u0629' : 'Backpack',
        onBackpack,
      ),
    ];

    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: items
            .map((item) => Expanded(child: _ShortcutTile(data: item)))
            .toList(),
      ),
    );
  }
}

class _ShortcutData {
  const _ShortcutData(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.data});

  final _ShortcutData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: data.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A174F), Color(0xFF241638)],
                ),
                border: Border.all(color: const Color(0xFF5A3A86)),
              ),
              child: Icon(data.icon, color: const Color(0xFFF0C15A)),
            ),
            const SizedBox(height: 7),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuList extends StatelessWidget {
  const _ProfileMenuList({
    required this.isArabic,
    required this.onLevel,
    required this.onAgency,
    required this.onIncome,
    required this.onBadge,
    required this.onLeaderboard,
    required this.onFeedback,
    required this.onCustomerService,
    required this.onSettings,
  });

  final bool isArabic;
  final VoidCallback onLevel;
  final VoidCallback onAgency;
  final VoidCallback onIncome;
  final VoidCallback onBadge;
  final VoidCallback onLeaderboard;
  final VoidCallback onFeedback;
  final VoidCallback onCustomerService;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuData(
        Icons.trending_up_rounded,
        isArabic ? '\u0645\u0633\u062a\u0648\u0627\u064a' : 'My level',
        onLevel,
      ),
      _MenuData(
        Icons.groups_rounded,
        isArabic ? '\u0648\u0643\u0627\u0644\u062a\u064a' : 'My agency',
        onAgency,
      ),
      _MenuData(
        Icons.account_balance_wallet_rounded,
        isArabic ? '\u062f\u062e\u0644\u064a' : 'My income',
        onIncome,
      ),
      _MenuData(
        Icons.verified_rounded,
        isArabic ? '\u0627\u0644\u0634\u0627\u0631\u0627\u062a' : 'Badge',
        onBadge,
      ),
      _MenuData(
        Icons.emoji_events_rounded,
        isArabic
            ? '\u0627\u0644\u0645\u062a\u0635\u062f\u0631\u0648\u0646'
            : 'Leaderboard',
        onLeaderboard,
      ),
      _MenuData(
        Icons.feedback_rounded,
        isArabic ? '\u0645\u0644\u0627\u062d\u0638\u0627\u062a' : 'Feedback',
        onFeedback,
      ),
      _MenuData(
        Icons.support_agent_rounded,
        isArabic
            ? '\u062e\u062f\u0645\u0629 \u0627\u0644\u0639\u0645\u0644\u0627\u0621'
            : 'Customer Service',
        onCustomerService,
        subtitle: isArabic
            ? '\u0645\u0633\u0627\u0639\u062f\u0629\u060c \u0634\u062d\u0646\u060c \u0648\u0628\u0644\u0627\u063a\u0627\u062a'
            : 'Help, recharge support, reports',
        gradientIcon: true,
      ),
      _MenuData(
        Icons.settings_rounded,
        isArabic
            ? '\u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a'
            : 'Settings',
        onSettings,
      ),
    ];

    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ProfileMenuItem(
                icon: item.icon,
                title: item.title,
                subtitle: item.subtitle,
                isArabic: isArabic,
                gradientIcon: item.gradientIcon,
                onTap: item.onTap,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MenuData {
  const _MenuData(
    this.icon,
    this.title,
    this.onTap, {
    this.subtitle,
    this.gradientIcon = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  final bool gradientIcon;
}

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

String _formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }

  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }

  return value.toString();
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
                isArabic
                    ? '\u0625\u0637\u0627\u0631 \u0627\u0644\u0635\u0648\u0631\u0629'
                    : 'Avatar Frame',
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
                title: isArabic ? '\u0639\u0627\u062f\u064a' : 'Normal',
                frames: frames
                    .where((frame) => frame.category == 'normal')
                    .toList(),
                selectedFrameKey: selectedFrameKey,
                avatarUrl: avatarUrl,
                vipLevel: vipLevel,
                isArabic: isArabic,
              ),
              _AvatarFrameGroup(
                title: isArabic ? '\u0641\u0627\u062e\u0631' : 'Luxury',
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
    if (frames.isEmpty) {
      return const SizedBox.shrink();
    }

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
                  ? '\u0647\u0630\u0627 \u0627\u0644\u0625\u0637\u0627\u0631 \u0645\u062a\u0627\u062d \u0644\u0645\u0633\u062a\u0648\u0649 VIP \u0623\u0639\u0644\u0649'
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
            color: selected ? const Color(0xFFF0C15A) : const Color(0xFF4A3470),
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
              frame?.name ??
                  (isArabic
                      ? '\u0628\u062f\u0648\u0646 \u0625\u0637\u0627\u0631'
                      : 'No Frame'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              unlocked
                  ? (selected
                        ? (isArabic ? '\u0645\u062d\u062f\u062f' : 'Selected')
                        : '')
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
