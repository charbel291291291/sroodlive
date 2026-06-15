import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/branding/branding_assets.dart';
import '../models/admin_models.dart';
import '../services/admin_access_service.dart';
import '../services/admin_service.dart';
import '../../games/screens/hungry_cat_admin_panel.dart';
import '../../games/screens/rocket_crash_admin_panel.dart';
import '../../games/screens/srood_loto_admin_panel.dart';
import '../../charisma/screens/charisma_admin_panel.dart';
import 'owner_game_control_screen.dart';
import 'vip_visual_preview_screen.dart';

enum _AdminModule {
  overview,
  finance,
  users,
  bd,
  content,
  rooms,
  banners,
  audit,
  games,
  vip,
  charisma,
}

// ─────────────────────────────────────────────
// Design tokens — edit here to restyle the panel
// ─────────────────────────────────────────────
const _kBg = Color(0xFF0C0E14); // main page bg
const _kSurface = Color(0xFF141720); // card bg
const _kSidebar = Color(0xFF0F1117); // sidebar bg
const _kBorder = Color(0xFF1E2435); // default border
const _kGold = Color(0xFFF0C15A); // brand / icon accent
const _kGreen = Color(0xFF22C55E); // active / approved
const _kAmber = Color(0xFFF59E0B); // pending / warning
const _kRed = Color(0xFFEF4444); // rejected / danger
const _kBlue = Color(0xFF60A5FA); // info / coins
const _kPurple = Color(0xFF8B5CF6); // accent / gifts
const _kTxt = Color(0xFFF1F5F9); // primary text
const _kMuted = Color(0xFF64748B); // muted text
const _kNavActive = Color(0xFF1A2040); // selected nav bg
const _kNavAccent = Color(0xFF6366F1); // selected nav left bar

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminAccessService _accessService = const AdminAccessService();
  final AdminService _adminService = const AdminService();
  final TextEditingController _walletLookupController = TextEditingController();
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _coinsController = TextEditingController();
  final TextEditingController _diamondsController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _adminPasswordController =
      TextEditingController();

  AdminRole _adminRole = AdminRole.empty;

  _AdminModule _module = _AdminModule.overview;
  bool _isLoading = true;
  bool _canAccess = false;
  bool _actionInProgress = false;
  List<String> _roles = const [];
  String? _error;

  StreamSubscription<AuthState>? _authSub;
  bool _loadInFlight = false;
  bool _reloadQueued = false;

  AdminOverview? _overview;
  List<AdminRechargeRequest> _pending = const [];
  List<AdminWithdrawalRequest> _pendingWithdrawals = const [];
  List<AdminWalletTransaction> _walletTransactions = const [];
  List<AdminGiftTransaction> _giftTransactions = const [];
  List<AdminAgency> _agencies = const [];
  List<AdminAgent> _agents = const [];
  List<AdminUserSummary> _users = const [];
  List<AdminRoomSummary> _rooms = const [];
  List<AdminGiftSummary> _gifts = const [];
  List<AdminAuditLog> _auditLogs = const [];
  AdminFinanceReport? _financeReport;
  List<AdminBdReportRow> _bdReport = const [];
  List<AdminAvatarFrameSummary> _avatarFrames = const [];
  List<AdminVipPackage> _vipPackages = const [];
  List<AdminEntranceBanner> _entranceBanners = const [];
  List<AdminGiftCategory> _giftCategories = const [];
  List<AdminPromoBanner> _promoBanners = const [];
  AdminWalletSummary? _walletLookup;

  // Hidden 7-tap trigger for owner panel
  int _ownerTapCount = 0;
  DateTime? _ownerTapLast;

  void _onBrandTap() {
    final now = DateTime.now();
    if (_ownerTapLast != null &&
        now.difference(_ownerTapLast!) > const Duration(seconds: 3)) {
      _ownerTapCount = 0;
    }
    _ownerTapLast = now;
    _ownerTapCount++;
    if (_ownerTapCount >= 7) {
      _ownerTapCount = 0;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OwnerGameControlScreen(),
          settings:
              const RouteSettings(name: OwnerGameControlScreen.routeName),
        ),
      );
    }
  }

  // ── Role helpers ──────────────────────────────────────────────────────────
  bool get _canFinance     => _adminRole.hasPermission(kPermWalletCredit);
  bool get _canBd          => _adminRole.hasPermission(kPermAgenciesView);
  bool get _canContent     => _adminRole.hasPermission(kPermGiftsManage);
  bool get _canRooms       => _adminRole.hasPermission(kPermRoomsClose);
  bool get _canUnban       => _adminRole.canUnban;
  bool get _canManageStaff => _adminRole.isOSuperAdmin;

  @override
  void initState() {
    super.initState();
    // Re-run the access check whenever the auth session changes, so a late
    // session restore, a token refresh, or a sign-in/out updates the gate
    // instead of being stuck on a one-shot result.
    _authSub = _adminService.authStateChanges().listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.userUpdated:
          _load();
          break;
        default:
          break;
      }
    });
    _load();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _walletLookupController.dispose();
    _userSearchController.dispose();
    _coinsController.dispose();
    _diamondsController.dispose();
    _noteController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  // Re-entrancy guard: if an auth event fires while a load is running, queue a
  // single follow-up load instead of racing two concurrent fetches.
  Future<void> _load() async {
    if (_loadInFlight) {
      _reloadQueued = true;
      return;
    }
    _loadInFlight = true;
    try {
      await _loadInternal();
    } finally {
      _loadInFlight = false;
      if (_reloadQueued) {
        _reloadQueued = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _loadInternal() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final adminRole = await _accessService.fetchCurrentAdminRole();
      final roles     = adminRole.isAnyAdmin ? [adminRole.role] : <String>[];
      final canAccess = adminRole.isAnyAdmin;

      if (!canAccess) {
        if (!mounted) return;
        setState(() {
          _adminRole = adminRole;
          _roles     = roles;
          _canAccess = false;
          _isLoading = false;
        });
        return;
      }

      final overview = await _adminService.fetchOverview();
      final pending = await _adminService.fetchRechargeRequests(
        status: 'pending',
      );
      final pendingWithdrawals = await _adminService.fetchWithdrawalRequests();
      final walletTransactions = await _adminService.fetchWalletTransactions();
      final giftTransactions = await _adminService.fetchGiftTransactions();
      final agencies = await _adminService.fetchAgencies();
      final agents = await _adminService.fetchAgents();
      final users = await _adminService.searchUsers();
      final rooms = await _adminService.fetchRooms();
      final gifts = await _adminService.fetchGifts();
      final auditLogs = await _adminService.fetchAuditLogs();
      final financeReport = await _adminService.fetchFinanceReport();
      final bdReport = await _adminService.fetchBdReport();
      final avatarFrames = await _adminService.fetchAvatarFrames();
      final vipPackages = await _adminService.fetchVipPackages();
      final entranceBanners = await _adminService.fetchEntranceBanners();
      final giftCategories = await _adminService.fetchGiftCategories();
      final promoBanners = await _adminService.fetchPromoBanners();

      if (!mounted) return;
      setState(() {
        _adminRole = adminRole;
        _roles     = roles;
        _canAccess = true;
        _overview  = overview;
        _pending = pending;
        _pendingWithdrawals = pendingWithdrawals;
        _walletTransactions = walletTransactions;
        _giftTransactions = giftTransactions;
        _agencies = agencies;
        _agents = agents;
        _users = users;
        _rooms = rooms;
        _gifts = gifts;
        _auditLogs = auditLogs;
        _financeReport = financeReport;
        _bdReport = bdReport;
        _avatarFrames = avatarFrames;
        _vipPackages = vipPackages;
        _entranceBanners = entranceBanners;
        _giftCategories = giftCategories;
        _promoBanners = promoBanners;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _adminLogin() async {
    final email = _adminEmailController.text.trim();
    final password = _adminPasswordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showSnack('Enter admin email and password');
      return;
    }

    try {
      await _adminService.signIn(email: email, password: password);
      await _load();
      if (!mounted) return;
      _showSnack('Admin login successful');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Admin login failed: $error');
    }
  }

  Future<void> _adminSignOut() async {
    await _adminService.signOut();
    if (!mounted) return;
    setState(() {
      _roles = const [];
      _canAccess = false;
      _isLoading = false;
    });
  }

  Future<void> _approve(AdminRechargeRequest request) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await _adminService.approveRecharge(request.id);
      if (!mounted) return;
      _showSnack('Recharge approved');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Approval failed: $error');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _reject(AdminRechargeRequest request) async {
    if (_actionInProgress) return;
    final reason = await _askForText(title: 'Reject recharge', label: 'Reason');
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _actionInProgress = true);
    try {
      await _adminService.rejectRecharge(request.id, reason.trim());
      if (!mounted) return;
      _showSnack('Recharge rejected');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Rejection failed: $error');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _approveWithdrawal(AdminWithdrawalRequest request) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await _adminService.approveWithdrawal(request.id);
      if (!mounted) return;
      _showSnack('Withdrawal approved');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Approval failed: $error');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _rejectWithdrawal(AdminWithdrawalRequest request) async {
    if (_actionInProgress) return;
    final reason =
        await _askForText(title: 'Reject withdrawal', label: 'Reason');
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _actionInProgress = true);
    try {
      await _adminService.rejectWithdrawal(request.id, reason.trim());
      if (!mounted) return;
      _showSnack('Withdrawal rejected');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Rejection failed: $error');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _lookupWallet() async {
    final query = _walletLookupController.text.trim();
    if (query.isEmpty) return;

    try {
      final wallet = await _adminService.lookupWallet(query);
      if (!mounted) return;
      setState(() => _walletLookup = wallet);
      if (wallet == null) _showSnack('No wallet found for $query');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Lookup failed: $error');
    }
  }

  Future<void> _applyAdjustment() async {
    if (_actionInProgress) return;
    final wallet = _walletLookup;
    if (wallet == null || !_canFinance) return;

    final coins = int.tryParse(_coinsController.text.trim()) ?? 0;
    final diamonds = int.tryParse(_diamondsController.text.trim()) ?? 0;
    final note = _noteController.text.trim();

    if (coins == 0 && diamonds == 0) {
      _showSnack('Enter a coins or diamonds delta');
      return;
    }

    setState(() => _actionInProgress = true);
    try {
      await _adminService.adjustWallet(
        userId: wallet.userId,
        coinsDelta: coins,
        diamondsDelta: diamonds,
        note: note.isEmpty ? null : note,
      );
      _coinsController.clear();
      _diamondsController.clear();
      _noteController.clear();
      await _lookupWallet();
      await _load();
      if (!mounted) return;
      _showSnack('Wallet adjusted');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Adjustment failed: $error');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _searchUsers() async {
    try {
      final users = await _adminService.searchUsers(
        query: _userSearchController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _users = users);
    } catch (error) {
      if (!mounted) return;
      _showSnack('User search failed: $error');
    }
  }

  Future<void> _assignRole(AdminUserSummary user) async {
    final role = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kSurface,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          shrinkWrap: true,
          children: [
            Text('Assign role', style: _titleStyle.copyWith(fontSize: 20)),
            const SizedBox(height: 12),
            ...AdminRoleSpec.all.map(
              (spec) => ListTile(
                enabled: !user.roles.contains(spec.role),
                leading: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: _kGold,
                ),
                title: Text(spec.label),
                subtitle: Text(spec.description),
                onTap: () => Navigator.of(context).pop(spec.role),
              ),
            ),
          ],
        ),
      ),
    );
    if (role == null) return;

    try {
      await _adminService.assignUserRole(userId: user.userId, role: role);
      await _searchUsers();
      await _load();
      if (!mounted) return;
      _showSnack('Role assigned');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Assign role failed: $error');
    }
  }

  Future<void> _removeRole(AdminUserSummary user, String role) async {
    final confirmed = await _confirm(
      title: 'Remove role',
      body: 'Remove ${AdminRoleSpec.byRole(role).label} from ${user.title}?',
      action: 'Remove',
    );
    if (!confirmed) return;

    try {
      await _adminService.removeUserRole(userId: user.userId, role: role);
      await _searchUsers();
      await _load();
      if (!mounted) return;
      _showSnack('Role removed');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Remove role failed: $error');
    }
  }

  Future<void> _createAgency() async {
    final name = await _askForText(title: 'Create agency', label: 'Name');
    if (name == null || name.trim().isEmpty) return;
    final code = await _askForText(title: 'Create agency', label: 'Code');
    if (code == null || code.trim().isEmpty) return;

    try {
      await _adminService.createAgency(name: name.trim(), code: code.trim());
      await _load();
      if (!mounted) return;
      _showSnack('Agency created');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Agency creation failed: $error');
    }
  }

  Future<void> _createAgent() async {
    final agencyCode = await _askForText(
      title: 'Create agent',
      label: 'Agency code',
    );
    if (agencyCode == null || agencyCode.trim().isEmpty) return;
    final name = await _askForText(title: 'Create agent', label: 'Name');
    if (name == null || name.trim().isEmpty) return;
    final code = await _askForText(title: 'Create agent', label: 'Code');
    if (code == null || code.trim().isEmpty) return;

    try {
      await _adminService.createAgent(
        agencyCode: agencyCode.trim(),
        name: name.trim(),
        code: code.trim(),
      );
      await _load();
      if (!mounted) return;
      _showSnack('Agent created');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Agent creation failed: $error');
    }
  }

  Future<void> _toggleAgency(AdminAgency agency) async {
    try {
      await _adminService.setAgencyActive(
        agencyId: agency.id,
        isActive: !agency.isActive,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Agency updated');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Agency update failed: $error');
    }
  }

  Future<void> _toggleAgent(AdminAgent agent) async {
    try {
      await _adminService.setAgentActive(
        agentId: agent.id,
        isActive: !agent.isActive,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Agent updated');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Agent update failed: $error');
    }
  }

  Future<void> _toggleGift(AdminGiftSummary gift) async {
    try {
      await _adminService.setGiftActive(
        giftId: gift.id,
        isActive: !gift.isActive,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Gift updated');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Gift update failed: $error');
    }
  }

  Future<void> _editGift([AdminGiftSummary? gift]) async {
    final result = await showDialog<_GiftEditResult>(
      context: context,
      builder: (context) => _GiftEditDialog(gift: gift),
    );
    if (result == null) return;

    try {
      await _adminService.updateGift(
        giftId: gift?.id,
        code: result.code,
        name: result.name,
        arabicName: result.arabicName,
        priceCoins: result.priceCoins,
        icon: result.icon,
        category: result.category,
        isActive: result.isActive,
        sortOrder: result.sortOrder,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Gift saved');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Gift save failed: $error');
    }
  }

  Future<void> _openUserDetail(AdminUserSummary user) async {
    try {
      final detail = await _adminService.fetchUserDetail(user.userId);
      final ledger = await _adminService.fetchUserWalletTransactions(
        user.userId,
      );
      final recharges = await _adminService.fetchUserRechargeRequests(
        user.userId,
      );
      final gifts = await _adminService.fetchUserGiftTransactions(user.userId);
      if (!mounted || detail == null) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _kSurface,
        builder: (context) => _UserDetailSheet(
          detail: detail,
          ledger: ledger,
          recharges: recharges,
          gifts: gifts,
          canSupport:   _adminRole.hasPermission(kPermUsersEdit),
          canModerate:  _adminRole.hasPermission(kPermUsersTempBan),
          canUnban:     _canUnban,
          onEditProfile: () {
            Navigator.of(context).pop();
            _editUserProfile(detail);
          },
          onGrantVip: () {
            Navigator.of(context).pop();
            _grantVip(detail);
          },
          onGoldenId: () {
            Navigator.of(context).pop();
            _setGoldenId(detail);
          },
          onRestriction: (type, isActive) async {
            Navigator.of(context).pop();
            await _setRestriction(detail, type, isActive);
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Could not load user detail: $error');
    }
  }

  Future<void> _editUserProfile(AdminUserDetail detail) async {
    final result = await showDialog<_UserEditResult>(
      context: context,
      builder: (context) => _UserEditDialog(detail: detail),
    );
    if (result == null) return;

    try {
      await _adminService.updateUserProfile(
        userId: detail.userId,
        displayName: result.displayName,
        username: result.username,
        avatarUrl: result.avatarUrl,
        bio: result.bio,
        vipLevel: result.vipLevel,
      );
      await _searchUsers();
      await _load();
      if (!mounted) return;
      _showSnack('User updated');
    } catch (error) {
      if (!mounted) return;
      _showSnack('User update failed: $error');
    }
  }

  Future<void> _setRestriction(
    AdminUserDetail detail,
    String type,
    bool isActive,
  ) async {
    // Unban (removing account_ban) is exclusive to O-Super Admin
    if (type == 'account_ban' && !isActive) {
      if (!_canUnban) {
        _showSnack(widget.isArabic
            ? 'فقط O-Super Admin يمكنه فك الحظر'
            : 'Only O-Super Admin can unban users');
        return;
      }
    }

    final reason = isActive
        ? await _askForText(title: 'Restriction reason', label: 'Reason')
        : null;
    if (isActive && (reason == null || reason.trim().isEmpty)) return;

    try {
      await _adminService.setUserRestriction(
        userId: detail.userId,
        restrictionType: type,
        isActive: isActive,
        reason: reason?.trim(),
      );
      await _load();
      if (!mounted) return;
      _showSnack(isActive ? 'Restriction added' : 'Restriction removed');
    } catch (error) {
      if (!mounted) return;
      final msg = error.toString();
      if (msg.contains('only_o_super_admin_can_unban')) {
        _showSnack(widget.isArabic
            ? 'فقط O-Super Admin يمكنه فك الحظر'
            : 'Only O-Super Admin can unban users');
      } else {
        _showSnack('Restriction failed: $error');
      }
    }
  }

  Future<void> _grantVip(AdminUserDetail detail) async {
    if (_actionInProgress) return;
    final levelText = await _askForText(
      title: 'Grant VIP',
      label: 'VIP level 0-9',
    );
    if (levelText == null) return;
    final daysText = await _askForText(title: 'Grant VIP', label: 'Days');
    if (daysText == null) return;

    setState(() => _actionInProgress = true);
    try {
      await _adminService.grantVip(
        userId: detail.userId,
        vipLevel: int.tryParse(levelText.trim()) ?? 0,
        days: int.tryParse(daysText.trim()) ?? 30,
      );
      await _load();
      if (!mounted) return;
      _showSnack('VIP updated');
    } catch (error) {
      if (!mounted) return;
      _showSnack('VIP update failed: $error');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _setGoldenId(AdminUserDetail detail) async {
    final publicId = await _askForText(
      title: 'Golden ID',
      label: 'Public user ID',
    );
    if (publicId == null || publicId.trim().isEmpty) return;
    try {
      await _adminService.setGoldenId(
        userId: detail.userId,
        publicUserId: publicId.trim(),
        isGolden: true,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Golden ID updated');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Golden ID failed: $error');
    }
  }

  Future<void> _closeRoom(AdminRoomSummary room) async {
    final confirmed = await _confirm(
      title: 'Close room',
      body: 'Close ${room.name} and remove active members?',
      action: 'Close room',
    );
    if (!confirmed) return;
    final reason = await _askForText(title: 'Close room', label: 'Reason');

    try {
      await _adminService.closeRoom(roomId: room.id, reason: reason);
      await _load();
      if (!mounted) return;
      _showSnack('Room closed');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Close room failed: $error');
    }
  }

  Future<void> _reopenRoom(AdminRoomSummary room) async {
    final confirmed = await _confirm(
      title: 'Reopen room',
      body: 'Reopen ${room.name} so users can join again?',
      action: 'Reopen',
    );
    if (!confirmed) return;

    try {
      await _adminService.reopenRoom(roomId: room.id);
      await _load();
      if (!mounted) return;
      _showSnack('Room reopened');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Reopen room failed: $error');
    }
  }

  Future<void> _editGiftCategory(AdminGiftCategory category) async {
    final result = await showDialog<_GiftCategoryEditResult>(
      context: context,
      builder: (context) => _GiftCategoryEditDialog(category: category),
    );
    if (result == null) return;

    try {
      await _adminService.updateGiftCategory(
        categoryKey: result.categoryKey,
        name: result.name,
        arabicName: result.arabicName,
        icon: result.icon,
        isActive: result.isActive,
        sortOrder: result.sortOrder,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Gift category saved');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Gift category save failed: $error');
    }
  }

  Future<void> _editVipPackage(AdminVipPackage vip) async {
    final result = await showDialog<_VipPackageEditResult>(
      context: context,
      builder: (context) => _VipPackageEditDialog(vip: vip),
    );
    if (result == null) return;

    try {
      await _adminService.updateVipPackage(
        vipLevel: result.vipLevel,
        code: result.code,
        name: result.name,
        arabicName: result.arabicName,
        priceCoins: result.priceCoins,
        durationDays: result.durationDays,
        badgeLabel: result.badgeLabel,
        entranceBannerKey: result.entranceBannerKey,
        isActive: result.isActive,
        sortOrder: result.sortOrder,
      );
      await _load();
      if (!mounted) return;
      _showSnack('VIP package saved');
    } catch (error) {
      if (!mounted) return;
      _showSnack('VIP package save failed: $error');
    }
  }

  Future<void> _editEntranceBanner(AdminEntranceBanner banner) async {
    final result = await showDialog<_EntranceBannerEditResult>(
      context: context,
      builder: (context) => _EntranceBannerEditDialog(banner: banner),
    );
    if (result == null) return;

    try {
      await _adminService.updateEntranceBanner(
        bannerKey: result.bannerKey,
        name: result.name,
        arabicName: result.arabicName,
        vipLevel: result.vipLevel,
        assetUrl: result.assetUrl,
        gradientStart: result.gradientStart,
        gradientEnd: result.gradientEnd,
        messageTemplate: result.messageTemplate,
        isActive: result.isActive,
        sortOrder: result.sortOrder,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Entrance banner saved');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Entrance banner save failed: $error');
    }
  }

  Future<void> _editAvatarFrame(AdminAvatarFrameSummary frame) async {
    final result = await showDialog<_AvatarFrameEditResult>(
      context: context,
      builder: (context) => _AvatarFrameEditDialog(frame: frame),
    );
    if (result == null) return;

    try {
      await _adminService.updateAvatarFrame(
        frameKey: result.frameKey,
        name: result.name,
        category: result.category,
        vipLevel: result.vipLevel,
        requiredVipLevel: result.requiredVipLevel,
        assetUrl: result.assetUrl,
        isActive: result.isActive,
        isFeatured: result.isFeatured,
        sortOrder: result.sortOrder,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Avatar frame saved');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Avatar frame save failed: $error');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _askForText({required String title, required String label}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        title: Text(title),
        content: _AdminTextField(
          controller: controller,
          label: label,
          icon: Icons.edit_rounded,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: _kTxt)),
        backgroundColor: _kSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _kBorder),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: _kGold,
                  strokeWidth: 2.5,
                ),
              )
            : !_canAccess
            ? _adminService.currentEmail == null
                  ? _AdminLoginPanel(
                      emailController: _adminEmailController,
                      passwordController: _adminPasswordController,
                      onLogin: _adminLogin,
                    )
                  : _AdminShellMessage(
                      icon: Icons.lock_rounded,
                      title: 'Not authorized',
                      subtitle: _adminService.currentEmail != null
                          ? 'Signed in as ${_adminService.currentEmail}, which has no admin role. Sign out and use an admin account.'
                          : 'This dashboard is only for admin roles.',
                      onSignOut: _adminService.currentEmail != null
                          ? _adminSignOut
                          : null,
                    )
            : _error != null
            ? _AdminShellMessage(
                icon: Icons.error_outline_rounded,
                title: 'Could not load dashboard',
                subtitle: _error!,
                onRetry: _load,
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 860;
                  return Row(
                    children: [
                      if (!narrow)
                        _AdminSideNav(
                          selected: _module,
                          roles: _roles,
                          pendingCount: _pending.length,
                          onSelected: (module) =>
                              setState(() => _module = module),
                          onBrandTap: _onBrandTap,
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            _AdminTopBar(
                              roles: _roles,
                              onRefresh: _load,
                              onSignOut: _adminSignOut,
                              showTabs: narrow,
                              selected: _module,
                              pendingCount: _pending.length,
                              onSelected: (module) =>
                                  setState(() => _module = module),
                            ),
                            Expanded(
                              child: RefreshIndicator(
                                color: _kGold,
                                backgroundColor: _kSurface,
                                onRefresh: _load,
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    40,
                                  ),
                                  children: [_buildModule()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildModule() {
    return switch (_module) {
      _AdminModule.overview => _buildOverview(),
      _AdminModule.finance => _buildFinance(),
      _AdminModule.users => _buildUsers(),
      _AdminModule.bd => _buildBd(),
      _AdminModule.content => _buildContent(),
      _AdminModule.rooms => _buildRooms(),
      _AdminModule.banners => _buildBanners(),
      _AdminModule.audit  => _buildAudit(),
      _AdminModule.games  => _buildGames(),
      _AdminModule.vip    => _buildVipPreview(),
      _AdminModule.charisma => _buildCharisma(),
    };
  }

  Widget _buildOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Command Center',
          subtitle: 'Live finance, rooms, gifts, and operations overview.',
          icon: Icons.dashboard_customize_rounded,
        ),
        const SizedBox(height: 14),
        _OverviewGrid(overview: _overview),
        const SizedBox(height: 14),
        _ResponsivePair(
          left: _AdminSectionCard(
            title: 'Pending Recharge',
            child: _pending.isEmpty
                ? const _AdminEmptyState(
                    icon: Icons.add_card_rounded,
                    title: 'No pending requests',
                    subtitle: 'Recharge approvals will appear here.',
                  )
                : Column(
                    children: _pending
                        .take(5)
                        .map(
                          (request) => _RechargeRequestTile(
                            request: request,
                            canFinance: _canFinance,
                            onApprove: () => _approve(request),
                            onReject: () => _reject(request),
                          ),
                        )
                        .toList(),
                  ),
          ),
          right: _AdminSectionCard(
            title: 'Role Access',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RoleChip(
                  label: _adminRole.isAnyAdmin
                      ? _adminRole.displayLabel
                      : 'No role',
                ),
                const SizedBox(height: 12),
                Text(
                  _adminRole.isOSuperAdmin
                      ? 'Owner — full access including unban and staff management.'
                      : _adminRole.isPSuperAdmin
                          ? 'Partner — high-level access. Cannot unban users or manage admin roles.'
                          : _adminRole.isSuperAdmin
                              ? 'Operational admin — manages users, rooms, reports, agencies, and challenges.'
                              : _adminRole.isAdmin
                                  ? 'Basic moderator — view reports, close rooms, temp-ban users.'
                                  : 'No admin access.',
                  style: _mutedStyle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Finance',
          subtitle: 'Recharge approvals, wallet lookup, adjustments, ledger.',
          icon: Icons.account_balance_wallet_rounded,
          locked: !_canFinance,
        ),
        const SizedBox(height: 14),
        _FinanceReportCard(report: _financeReport),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Pending Recharge Requests',
          action: IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          child: _pending.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.verified_rounded,
                  title: 'All clear',
                  subtitle: 'No pending recharge requests right now.',
                )
              : Column(
                  children: _pending
                      .map(
                        (request) => _RechargeRequestTile(
                          request: request,
                          canFinance: _canFinance,
                          onApprove: () => _approve(request),
                          onReject: () => _reject(request),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Pending Withdrawal Requests',
          action: IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          child: _pendingWithdrawals.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.verified_rounded,
                  title: 'All clear',
                  subtitle: 'No pending withdrawal requests right now.',
                )
              : Column(
                  children: _pendingWithdrawals
                      .map(
                        (w) => _WithdrawalRequestTile(
                          request: w,
                          canFinance: _canFinance,
                          onApprove: () => _approveWithdrawal(w),
                          onReject: () => _rejectWithdrawal(w),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'BD Performance Today',
          child: _bdReport.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.query_stats_rounded,
                  title: 'No approved sales',
                  subtitle: 'Agency and agent performance appears here.',
                )
              : Column(children: _bdReport.map(_BdReportTile.new).toList()),
        ),
        const SizedBox(height: 14),
        _ResponsivePair(
          left: _WalletLookupCard(
            lookupController: _walletLookupController,
            coinsController: _coinsController,
            diamondsController: _diamondsController,
            noteController: _noteController,
            wallet: _walletLookup,
            canFinance: _canFinance,
            onSearch: _lookupWallet,
            onAdjust: _applyAdjustment,
          ),
          right: _AdminSectionCard(
            title: 'Recent Wallet Ledger',
            child: _walletTransactions.isEmpty
                ? const _AdminEmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No transactions',
                    subtitle: 'Wallet movement appears here.',
                  )
                : Column(
                    children: _walletTransactions
                        .take(12)
                        .map(_WalletTransactionTile.new)
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Users & Roles',
          subtitle: 'Search users, view details, and manage admin staff.',
          icon: Icons.manage_accounts_rounded,
          locked: !_adminRole.hasPermission(kPermUsersView),
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'User Search',
          child: Column(
            children: [
              _SearchRow(
                controller: _userSearchController,
                label: 'Search by ID, nickname, username, or UUID',
                onSearch: _searchUsers,
              ),
              const SizedBox(height: 14),
              if (_users.isEmpty)
                const _AdminEmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'No users found',
                  subtitle: 'Search by public ID, name, username, or UUID.',
                )
              else
                Column(
                  children: _users
                      .map(
                        (user) => _UserTile(
                          user: user,
                          canManageRoles: _canManageStaff,
                          onOpen: () => _openUserDetail(user),
                          onAssign: _canManageStaff ? () => _assignRole(user) : null,
                          onRemoveRole: _canManageStaff
                              ? (role) => _removeRole(user, role)
                              : null,
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBd() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'BD & Recharge Network',
          subtitle: 'Manage agencies, recharge agents, and network status.',
          icon: Icons.handshake_rounded,
          locked: !_canBd,
        ),
        const SizedBox(height: 14),
        _ResponsivePair(
          left: _AgencyListCard(
            agencies: _agencies,
            canManage: _canBd,
            onCreateAgency: _createAgency,
            onToggleAgency: _toggleAgency,
          ),
          right: _AgentListCard(
            agents: _agents,
            canManage: _canBd,
            onCreateAgent: _createAgent,
            onToggleAgent: _toggleAgent,
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Content & Gifts',
          subtitle: 'Gift catalog, active state, and gift economy visibility.',
          icon: Icons.card_giftcard_rounded,
          locked: !_canContent,
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Gift Categories',
          child: _giftCategories.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.category_rounded,
                  title: 'No categories',
                  subtitle: 'Gift categories will appear here.',
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _giftCategories
                      .map(
                        (category) => _CatalogChip(
                          title: category.name,
                          subtitle: category.categoryKey,
                          active: category.isActive,
                          onTap: _canContent
                              ? () => _editGiftCategory(category)
                              : null,
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),
        _ResponsivePair(
          left: _AdminSectionCard(
            title: 'VIP Packages',
            child: _vipPackages.isEmpty
                ? const _AdminEmptyState(
                    icon: Icons.workspace_premium_rounded,
                    title: 'No VIP packages',
                    subtitle: 'VIP package configuration appears here.',
                  )
                : Column(
                    children: _vipPackages
                        .map(
                          (vip) => _AdminListTile(
                            icon: Icons.workspace_premium_rounded,
                            title: '${vip.name} - ${vip.priceCoins} coins',
                            subtitle:
                                '${vip.durationDays} days - ${vip.entranceBannerKey ?? '-'}',
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                _RoleChip(
                                  label: vip.isActive ? 'active' : 'off',
                                ),
                                if (_canContent)
                                  TextButton(
                                    onPressed: () => _editVipPackage(vip),
                                    child: const Text('Edit'),
                                  ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          right: _AdminSectionCard(
            title: 'Entrance Banners',
            child: _entranceBanners.isEmpty
                ? const _AdminEmptyState(
                    icon: Icons.auto_awesome_rounded,
                    title: 'No banners',
                    subtitle: 'Entrance banners appear here.',
                  )
                : Column(
                    children: _entranceBanners
                        .map(
                          (banner) => _AdminListTile(
                            icon: Icons.auto_awesome_rounded,
                            title: banner.name,
                            subtitle:
                                '${banner.bannerKey} - VIP ${banner.vipLevel ?? '-'}',
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                _RoleChip(
                                  label: banner.isActive ? 'active' : 'off',
                                ),
                                if (_canContent)
                                  TextButton(
                                    onPressed: () =>
                                        _editEntranceBanner(banner),
                                    child: const Text('Edit'),
                                  ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Avatar Frames',
          child: _avatarFrames.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.account_circle_rounded,
                  title: 'No frames',
                  subtitle: 'Avatar frame catalog appears here.',
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _avatarFrames
                      .map(
                        (frame) => _CatalogChip(
                          title: frame.name,
                          subtitle:
                              '${frame.category} - used ${frame.usageCount}',
                          active: frame.isActive,
                          onTap: _canContent
                              ? () => _editAvatarFrame(frame)
                              : null,
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Gift Catalog',
          action: _canContent
              ? TextButton.icon(
                  onPressed: () => _editGift(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Gift'),
                )
              : null,
          child: _gifts.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.card_giftcard_rounded,
                  title: 'No gifts',
                  subtitle: 'Gift definitions will appear here.',
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _gifts
                      .map(
                        (gift) => _GiftAdminCard(
                          gift: gift,
                          canManage: _canContent,
                          onToggle: () => _toggleGift(gift),
                          onEdit: () => _editGift(gift),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Recent Gift Transactions',
          child: _giftTransactions.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.history_rounded,
                  title: 'No gift history',
                  subtitle: 'Gift sends will appear here.',
                )
              : Column(
                  children: _giftTransactions
                      .take(15)
                      .map(_GiftTransactionTile.new)
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildRooms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Rooms',
          subtitle: 'Live room visibility and moderation overview.',
          icon: Icons.mic_external_on_rounded,
          locked: !_canRooms,
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Recent Rooms',
          child: _rooms.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.meeting_room_rounded,
                  title: 'No rooms',
                  subtitle: 'Created rooms will appear here.',
                )
              : Column(
                  children: _rooms
                      .map(
                        (room) => _RoomTile(
                          room,
                          canManage: _canRooms,
                          onClose: () => _closeRoom(room),
                          onReopen: () => _reopenRoom(room),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildBanners() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Promo Banners',
          subtitle: 'Carousel slides shown at the top of the Rooms screen.',
          icon: Icons.view_carousel_rounded,
          locked: !_canContent,
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Banner Slides',
          action: _canContent
              ? TextButton.icon(
                  onPressed: () => _editPromoBanner(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Banner'),
                )
              : null,
          child: _promoBanners.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.view_carousel_rounded,
                  title: 'No banners',
                  subtitle: 'Add promotional carousel slides here.',
                )
              : Column(
                  children: _promoBanners
                      .map(
                        (b) => _AdminListTile(
                          icon: Icons.view_carousel_rounded,
                          title: b.titleEn.isNotEmpty ? b.titleEn : b.slideKey,
                          subtitle:
                              '${b.slideKey} · order ${b.sortOrder}'
                              '${b.targetRoute != null ? ' → ${b.targetRoute}' : ''}',
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              _RoleChip(label: b.isActive ? 'active' : 'off'),
                              if (_canContent) ...[
                                TextButton(
                                  onPressed: () => _editPromoBanner(b),
                                  child: const Text('Edit'),
                                ),
                                TextButton(
                                  onPressed: () => _deletePromoBanner(b),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _kRed,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _editPromoBanner([AdminPromoBanner? existing]) async {
    final result = await showDialog<AdminPromoBanner>(
      context: context,
      builder: (_) => _PromoBannerEditDialog(
        existing: existing,
        adminService: _adminService,
      ),
    );
    if (result == null) return;
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await _adminService.upsertPromoBanner(
        id: result.id.isEmpty ? null : result.id,
        slideKey: result.slideKey,
        sortOrder: result.sortOrder,
        isActive: result.isActive,
        labelEn: result.labelEn,
        labelAr: result.labelAr,
        titleEn: result.titleEn,
        titleAr: result.titleAr,
        subtitleEn: result.subtitleEn,
        subtitleAr: result.subtitleAr,
        ctaEn: result.ctaEn,
        ctaAr: result.ctaAr,
        iconName: result.iconName,
        gradientStart: result.gradientStart,
        gradientMid: result.gradientMid,
        gradientEnd: result.gradientEnd,
        iconBgColor: result.iconBgColor,
        imageUrl: result.imageUrl,
        targetRoute: result.targetRoute,
      );
      if (!mounted) return;
      _showSnack('Banner saved');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _deletePromoBanner(AdminPromoBanner banner) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete banner?'),
        content: Text('This removes "${banner.titleEn}" permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: _kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await _adminService.deletePromoBanner(banner.id);
      if (!mounted) return;
      _showSnack('Banner deleted');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Widget _buildGames() {
    if (!_adminRole.hasPermission(kPermDrawManage)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Game controls require P-Super Admin or higher.',
            style: TextStyle(color: _kMuted, fontSize: 14),
          ),
        ),
      );
    }

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = viewportHeight < 860 ? 680.0 : viewportHeight - 220.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ModuleTitle(
          title: 'Game Controls',
          subtitle: 'Odds, test tools, forced results, and emergency void.',
          icon: Icons.sports_esports_rounded,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: panelHeight,
          child: DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141720),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E2435)),
                  ),
                  child: const TabBar(
                    labelColor: Color(0xFFF0C15A),
                    unselectedLabelColor: Color(0xFF64748B),
                    indicatorColor: Color(0xFFF0C15A),
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(icon: Text('🐱'), text: 'Hungry Cat'),
                      Tab(icon: Text('🚀'), text: 'Rocket Crash'),
                      Tab(icon: Text('🎰'), text: 'Srood Draw'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: const [
                      HungryCatAdminPanel(),
                      RocketCrashAdminPanel(),
                      SroodLotoAdminPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVipPreview() {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = viewportHeight < 860 ? 680.0 : viewportHeight - 220.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ModuleTitle(
          title: 'VIP Visual System',
          subtitle: 'Preview VIP 0–9 chat frames, mic waves, and entry banners.',
          icon: Icons.workspace_premium_rounded,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: panelHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: const VipVisualPreviewScreen(),
          ),
        ),
      ],
    );
  }

  Widget _buildCharisma() {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = viewportHeight < 860 ? 680.0 : viewportHeight - 220.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ModuleTitle(
          title: 'Charisma Challenge',
          subtitle: 'Create, manage and crown winners for charisma challenges.',
          icon: Icons.emoji_events_rounded,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: panelHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CharismaAdminPanel(isArabic: widget.isArabic),
          ),
        ),
      ],
    );
  }

  Widget _buildAudit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ModuleTitle(
          title: 'Audit Log',
          subtitle: 'Role, finance, BD, and content changes made by admins.',
          icon: Icons.fact_check_rounded,
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'Recent Admin Actions',
          child: _auditLogs.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.history_edu_rounded,
                  title: 'No audit logs yet',
                  subtitle: 'Admin actions will be recorded here.',
                )
              : Column(children: _auditLogs.map(_AuditTile.new).toList()),
        ),
      ],
    );
  }
}

class _AdminLoginPanel extends StatelessWidget {
  const _AdminLoginPanel({
    required this.emailController,
    required this.passwordController,
    required this.onLogin,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _AdminCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AdminBrand(),
                const SizedBox(height: 28),
                const Divider(color: _kBorder, height: 1),
                const SizedBox(height: 24),
                const Text(
                  'Sign in to Admin Console',
                  style: TextStyle(
                    color: _kTxt,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use an account with an assigned admin role.',
                  style: _mutedStyle,
                ),
                const SizedBox(height: 22),
                _AdminTextField(
                  controller: emailController,
                  label: 'Email address',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _AdminTextField(
                  controller: passwordController,
                  label: 'Password',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                  onSubmitted: (_) => onLogin(),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kNavAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text(
                    'Sign in',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ), // _AdminCard
        ), // ConstrainedBox
      ), // Center
    ); // Container
  }
}

/// Styled text field matching the admin dark theme.
class _AdminTextField extends StatelessWidget {
  const _AdminTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.onSubmitted,
    this.maxLines = 1,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;
  final int? maxLines;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      maxLines: maxLines,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: _kTxt, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: Icon(icon, color: _kMuted, size: 18),
        labelStyle: const TextStyle(color: _kMuted, fontSize: 13),
        helperStyle: const TextStyle(color: _kMuted, fontSize: 11),
        filled: true,
        fillColor: _kBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kNavAccent, width: 1.5),
        ),
      ),
    );
  }
}

class _FinanceReportCard extends StatelessWidget {
  const _FinanceReportCard({required this.report});

  final AdminFinanceReport? report;

  @override
  Widget build(BuildContext context) {
    final item = report;
    if (item == null) {
      return const _AdminSectionCard(
        title: 'Finance Report Today',
        child: _AdminEmptyState(
          icon: Icons.query_stats_rounded,
          title: 'No report',
          subtitle: 'Finance report data is not available yet.',
        ),
      );
    }

    // (label, value, icon, color)
    final stats = [
      ('Approved', item.approvedRecharges, Icons.verified_rounded, _kGreen),
      ('Rejected', item.rejectedRecharges, Icons.cancel_rounded, _kRed),
      (
        'Pending',
        item.pendingRecharges,
        Icons.pending_actions_rounded,
        _kAmber,
      ),
      ('Coins In', item.coinsCharged, Icons.monetization_on_rounded, _kBlue),
      (
        'Gift Spend',
        item.giftCoinsSpent,
        Icons.card_giftcard_rounded,
        _kPurple,
      ),
      ('Adjustments', item.manualAdjustmentCount, Icons.tune_rounded, _kMuted),
    ];

    return _AdminSectionCard(
      title: 'Finance Report — Today',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth > 500 ? 3 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: stats
                .map(
                  (s) => _AdminStatCard(
                    label: s.$1,
                    value: s.$2,
                    icon: s.$3,
                    color: s.$4,
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _BdReportTile extends StatelessWidget {
  const _BdReportTile(this.row);

  final AdminBdReportRow row;

  @override
  Widget build(BuildContext context) {
    return _AdminListTile(
      icon: Icons.handshake_rounded,
      title:
          '${row.agencyName ?? 'No agency'} - ${row.agentName ?? 'No agent'}',
      subtitle:
          '${row.agencyCode ?? '-'} / ${row.agentCode ?? '-'} - ${row.approvedCount} approvals',
      trailing: _RoleChip(label: '${row.coinsCharged} coins'),
    );
  }
}

class _UserDetailSheet extends StatelessWidget {
  const _UserDetailSheet({
    required this.detail,
    required this.ledger,
    required this.recharges,
    required this.gifts,
    required this.canSupport,
    required this.canModerate,
    required this.canUnban,
    required this.onEditProfile,
    required this.onGrantVip,
    required this.onGoldenId,
    required this.onRestriction,
  });

  final AdminUserDetail detail;
  final List<AdminUserLedgerRow> ledger;
  final List<AdminUserRechargeRow> recharges;
  final List<AdminUserGiftRow> gifts;
  final bool canSupport;
  final bool canModerate;
  final bool canUnban;
  final VoidCallback onEditProfile;
  final VoidCallback onGrantVip;
  final VoidCallback onGoldenId;
  final void Function(String type, bool isActive) onRestriction;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.title,
                        style: _titleStyle.copyWith(fontSize: 28),
                      ),
                      Text(
                        detail.email ?? detail.publicUserId ?? detail.userId,
                        style: _mutedStyle,
                      ),
                    ],
                  ),
                ),
                if (canSupport)
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: onEditProfile,
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Edit'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onGrantVip,
                        icon: const Icon(Icons.workspace_premium_rounded),
                        label: const Text('VIP'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onGoldenId,
                        icon: const Icon(Icons.badge_rounded),
                        label: const Text('Golden ID'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RoleChip(label: '${detail.coinsBalance} coins'),
                _RoleChip(label: '${detail.diamondsBalance} diamonds'),
                _RoleChip(label: 'VIP ${detail.vipLevel}'),
                ...detail.roles.map((role) => _RoleChip(label: role)),
              ],
            ),
            if (detail.activeRestrictions.isNotEmpty) ...[
              const SizedBox(height: 14),
              _AdminSectionCard(
                title: 'Active Restrictions',
                child: Column(
                  children: detail.activeRestrictions
                      .map(
                        (item) {
                          final isAccountBan = item.type == 'account_ban';
                          final canRemove    = isAccountBan ? canUnban : canModerate;
                          return _AdminListTile(
                            icon: isAccountBan
                                ? Icons.gavel_rounded
                                : Icons.block_rounded,
                            title: item.type,
                            subtitle: item.reason ?? _dateLabel(item.createdAt),
                            trailing: canRemove
                                ? TextButton(
                                    onPressed: () =>
                                        onRestriction(item.type, false),
                                    child: Text(
                                      isAccountBan ? 'Unban' : 'Remove',
                                    ),
                                  )
                                : _RoleChip(
                                    label: isAccountBan ? '🔒 banned' : 'active',
                                  ),
                          );
                        },
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (canModerate)
              _AdminSectionCard(
                title: 'Safety Actions',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => onRestriction('chat_mute', true),
                      child: const Text('Chat mute'),
                    ),
                    OutlinedButton(
                      onPressed: () => onRestriction('room_ban', true),
                      child: const Text('Room ban'),
                    ),
                    OutlinedButton(
                      onPressed: () => onRestriction('gift_block', true),
                      child: const Text('Gift block'),
                    ),
                    FilledButton(
                      onPressed: () => onRestriction('account_ban', true),
                      child: const Text('Account ban'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            _AdminSectionCard(
              title: 'Wallet Ledger',
              child: ledger.isEmpty
                  ? const _AdminEmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No ledger',
                      subtitle: 'No wallet movement found.',
                    )
                  : Column(
                      children: ledger
                          .take(8)
                          .map(
                            (row) => _AdminListTile(
                              icon: Icons.receipt_long_rounded,
                              title: row.type,
                              subtitle: row.note ?? _dateLabel(row.createdAt),
                              trailing: _RoleChip(
                                label:
                                    '${row.coinsDelta}c / ${row.diamondsDelta}d',
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 14),
            _ResponsivePair(
              left: _AdminSectionCard(
                title: 'Recharges',
                child: recharges.isEmpty
                    ? const _AdminEmptyState(
                        icon: Icons.add_card_rounded,
                        title: 'No recharges',
                        subtitle: 'Recharge history is empty.',
                      )
                    : Column(
                        children: recharges
                            .take(8)
                            .map(
                              (row) => _AdminListTile(
                                icon: Icons.add_card_rounded,
                                title: '${row.requestedCoins} coins',
                                subtitle: '${row.method} - ${row.status}',
                                trailing: _RoleChip(
                                  label: _dateLabel(row.createdAt),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              right: _AdminSectionCard(
                title: 'Gifts',
                child: gifts.isEmpty
                    ? const _AdminEmptyState(
                        icon: Icons.card_giftcard_rounded,
                        title: 'No gifts',
                        subtitle: 'Gift history is empty.',
                      )
                    : Column(
                        children: gifts
                            .take(8)
                            .map(
                              (row) => _AdminListTile(
                                icon: Icons.card_giftcard_rounded,
                                title: '${row.direction}: ${row.giftName}',
                                subtitle: row.otherPublicUserId ?? '-',
                                trailing: _RoleChip(
                                  label: '${row.giftPriceCoins} coins',
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UserEditResult {
  const _UserEditResult({
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    required this.bio,
    required this.vipLevel,
  });

  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final int? vipLevel;
}

class _UserEditDialog extends StatefulWidget {
  const _UserEditDialog({required this.detail});

  final AdminUserDetail detail;

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _avatarUrl;
  late final TextEditingController _bio;
  late final TextEditingController _vipLevel;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(text: widget.detail.displayName);
    _username = TextEditingController(text: widget.detail.username);
    _avatarUrl = TextEditingController(text: widget.detail.avatarUrl);
    _bio = TextEditingController(text: widget.detail.bio);
    _vipLevel = TextEditingController(text: widget.detail.vipLevel.toString());
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _avatarUrl.dispose();
    _bio.dispose();
    _vipLevel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _kSurface,
      title: const Text('Edit user'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: _avatarUrl,
                decoration: const InputDecoration(labelText: 'Avatar URL'),
              ),
              TextField(
                controller: _bio,
                decoration: const InputDecoration(labelText: 'Bio'),
              ),
              TextField(
                controller: _vipLevel,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'VIP level'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _UserEditResult(
                displayName: _nullIfEmpty(_displayName.text),
                username: _nullIfEmpty(_username.text),
                avatarUrl: _nullIfEmpty(_avatarUrl.text),
                bio: _nullIfEmpty(_bio.text),
                vipLevel: int.tryParse(_vipLevel.text.trim()),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _GiftEditResult {
  const _GiftEditResult({
    required this.code,
    required this.name,
    required this.arabicName,
    required this.priceCoins,
    required this.icon,
    required this.category,
    required this.isActive,
    required this.sortOrder,
  });

  final String? code;
  final String? name;
  final String? arabicName;
  final int? priceCoins;
  final String? icon;
  final String category;
  final bool isActive;
  final int sortOrder;
}

class _GiftEditDialog extends StatefulWidget {
  const _GiftEditDialog({this.gift});

  final AdminGiftSummary? gift;

  @override
  State<_GiftEditDialog> createState() => _GiftEditDialogState();
}

class _GiftEditDialogState extends State<_GiftEditDialog> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _arabicName;
  late final TextEditingController _price;
  late final TextEditingController _icon;
  late final TextEditingController _category;
  late final TextEditingController _sortOrder;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final gift = widget.gift;
    _code = TextEditingController(text: gift?.code);
    _name = TextEditingController(text: gift?.name);
    _arabicName = TextEditingController(text: gift?.arabicName);
    _price = TextEditingController(text: gift?.priceCoins.toString());
    _icon = TextEditingController(text: gift?.icon);
    _category = TextEditingController(text: gift?.category ?? 'hot');
    _sortOrder = TextEditingController(text: gift?.sortOrder.toString() ?? '0');
    _isActive = gift?.isActive ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _arabicName.dispose();
    _price.dispose();
    _icon.dispose();
    _category.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _kSurface,
      title: Text(widget.gift == null ? 'Create gift' : 'Edit gift'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _arabicName,
                decoration: const InputDecoration(labelText: 'Arabic name'),
              ),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price coins'),
              ),
              TextField(
                controller: _icon,
                decoration: const InputDecoration(labelText: 'Image URL'),
              ),
              TextField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              TextField(
                controller: _sortOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sort order'),
              ),
              SwitchListTile(
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Active'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _GiftEditResult(
                code: _nullIfEmpty(_code.text),
                name: _nullIfEmpty(_name.text),
                arabicName: _nullIfEmpty(_arabicName.text),
                priceCoins: int.tryParse(_price.text.trim()),
                icon: _nullIfEmpty(_icon.text),
                category: _category.text.trim().isEmpty
                    ? 'hot'
                    : _category.text.trim(),
                isActive: _isActive,
                sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _GiftCategoryEditResult {
  const _GiftCategoryEditResult({
    required this.categoryKey,
    required this.name,
    required this.arabicName,
    required this.icon,
    required this.isActive,
    required this.sortOrder,
  });

  final String categoryKey;
  final String name;
  final String? arabicName;
  final String? icon;
  final bool isActive;
  final int sortOrder;
}

class _GiftCategoryEditDialog extends StatefulWidget {
  const _GiftCategoryEditDialog({required this.category});

  final AdminGiftCategory category;

  @override
  State<_GiftCategoryEditDialog> createState() =>
      _GiftCategoryEditDialogState();
}

class _GiftCategoryEditDialogState extends State<_GiftCategoryEditDialog> {
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _arabicName;
  late final TextEditingController _icon;
  late final TextEditingController _sortOrder;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: widget.category.categoryKey);
    _name = TextEditingController(text: widget.category.name);
    _arabicName = TextEditingController(text: widget.category.arabicName);
    _icon = TextEditingController(text: widget.category.icon);
    _sortOrder = TextEditingController(
      text: widget.category.sortOrder.toString(),
    );
    _isActive = widget.category.isActive;
  }

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _arabicName.dispose();
    _icon.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CatalogEditDialogShell(
      title: 'Edit gift category',
      fields: [
        TextField(
          controller: _key,
          decoration: const InputDecoration(labelText: 'Category key'),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _arabicName,
          decoration: const InputDecoration(labelText: 'Arabic name'),
        ),
        TextField(
          controller: _icon,
          decoration: const InputDecoration(labelText: 'Icon'),
        ),
        TextField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sort order'),
        ),
        SwitchListTile(
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
          title: const Text('Active'),
        ),
      ],
      onSave: () {
        final key = _key.text.trim();
        final name = _name.text.trim();
        if (key.isEmpty || name.isEmpty) return;
        Navigator.of(context).pop(
          _GiftCategoryEditResult(
            categoryKey: key,
            name: name,
            arabicName: _nullIfEmpty(_arabicName.text),
            icon: _nullIfEmpty(_icon.text),
            isActive: _isActive,
            sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
          ),
        );
      },
    );
  }
}

class _VipPackageEditResult {
  const _VipPackageEditResult({
    required this.vipLevel,
    required this.code,
    required this.name,
    required this.arabicName,
    required this.priceCoins,
    required this.durationDays,
    required this.badgeLabel,
    required this.entranceBannerKey,
    required this.isActive,
    required this.sortOrder,
  });

  final int vipLevel;
  final String code;
  final String name;
  final String? arabicName;
  final int priceCoins;
  final int durationDays;
  final String? badgeLabel;
  final String? entranceBannerKey;
  final bool isActive;
  final int sortOrder;
}

class _VipPackageEditDialog extends StatefulWidget {
  const _VipPackageEditDialog({required this.vip});

  final AdminVipPackage vip;

  @override
  State<_VipPackageEditDialog> createState() => _VipPackageEditDialogState();
}

class _VipPackageEditDialogState extends State<_VipPackageEditDialog> {
  late final TextEditingController _level;
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _arabicName;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late final TextEditingController _badge;
  late final TextEditingController _banner;
  late final TextEditingController _sortOrder;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final vip = widget.vip;
    _level = TextEditingController(text: vip.vipLevel.toString());
    _code = TextEditingController(text: vip.code);
    _name = TextEditingController(text: vip.name);
    _arabicName = TextEditingController(text: vip.arabicName);
    _price = TextEditingController(text: vip.priceCoins.toString());
    _duration = TextEditingController(text: vip.durationDays.toString());
    _badge = TextEditingController(text: vip.badgeLabel);
    _banner = TextEditingController(text: vip.entranceBannerKey);
    _sortOrder = TextEditingController(text: vip.sortOrder.toString());
    _isActive = vip.isActive;
  }

  @override
  void dispose() {
    _level.dispose();
    _code.dispose();
    _name.dispose();
    _arabicName.dispose();
    _price.dispose();
    _duration.dispose();
    _badge.dispose();
    _banner.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CatalogEditDialogShell(
      title: 'Edit VIP package',
      fields: [
        TextField(
          controller: _level,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'VIP level'),
        ),
        TextField(
          controller: _code,
          decoration: const InputDecoration(labelText: 'Code'),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _arabicName,
          decoration: const InputDecoration(labelText: 'Arabic name'),
        ),
        TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Price coins'),
        ),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Duration days'),
        ),
        TextField(
          controller: _badge,
          decoration: const InputDecoration(labelText: 'Badge label'),
        ),
        TextField(
          controller: _banner,
          decoration: const InputDecoration(labelText: 'Entrance banner key'),
        ),
        TextField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sort order'),
        ),
        SwitchListTile(
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
          title: const Text('Active'),
        ),
      ],
      onSave: () {
        final code = _code.text.trim();
        final name = _name.text.trim();
        if (code.isEmpty || name.isEmpty) return;
        Navigator.of(context).pop(
          _VipPackageEditResult(
            vipLevel: int.tryParse(_level.text.trim()) ?? 1,
            code: code,
            name: name,
            arabicName: _nullIfEmpty(_arabicName.text),
            priceCoins: int.tryParse(_price.text.trim()) ?? 0,
            durationDays: int.tryParse(_duration.text.trim()) ?? 30,
            badgeLabel: _nullIfEmpty(_badge.text),
            entranceBannerKey: _nullIfEmpty(_banner.text),
            isActive: _isActive,
            sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
          ),
        );
      },
    );
  }
}

class _EntranceBannerEditResult {
  const _EntranceBannerEditResult({
    required this.bannerKey,
    required this.name,
    required this.arabicName,
    required this.vipLevel,
    required this.assetUrl,
    required this.gradientStart,
    required this.gradientEnd,
    required this.messageTemplate,
    required this.isActive,
    required this.sortOrder,
  });

  final String bannerKey;
  final String name;
  final String? arabicName;
  final int? vipLevel;
  final String? assetUrl;
  final String? gradientStart;
  final String? gradientEnd;
  final String? messageTemplate;
  final bool isActive;
  final int sortOrder;
}

class _EntranceBannerEditDialog extends StatefulWidget {
  const _EntranceBannerEditDialog({required this.banner});

  final AdminEntranceBanner banner;

  @override
  State<_EntranceBannerEditDialog> createState() =>
      _EntranceBannerEditDialogState();
}

class _EntranceBannerEditDialogState extends State<_EntranceBannerEditDialog> {
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _arabicName;
  late final TextEditingController _vipLevel;
  late final TextEditingController _gradientStart;
  late final TextEditingController _gradientEnd;
  late final TextEditingController _message;
  late final TextEditingController _sortOrder;
  late bool _isActive;
  String? _assetUrl;

  @override
  void initState() {
    super.initState();
    final banner = widget.banner;
    _key = TextEditingController(text: banner.bannerKey);
    _name = TextEditingController(text: banner.name);
    _arabicName = TextEditingController(text: banner.arabicName);
    _vipLevel = TextEditingController(text: banner.vipLevel?.toString());
    _gradientStart = TextEditingController(text: banner.gradientStart);
    _gradientEnd = TextEditingController(text: banner.gradientEnd);
    _message = TextEditingController(text: banner.messageTemplate);
    _sortOrder = TextEditingController(text: banner.sortOrder.toString());
    _isActive = banner.isActive;
    _assetUrl = banner.assetUrl;
  }

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _arabicName.dispose();
    _vipLevel.dispose();
    _gradientStart.dispose();
    _gradientEnd.dispose();
    _message.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CatalogEditDialogShell(
      title: 'Edit entrance banner',
      fields: [
        TextField(
          controller: _key,
          decoration: const InputDecoration(labelText: 'Banner key'),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _arabicName,
          decoration: const InputDecoration(labelText: 'Arabic name'),
        ),
        TextField(
          controller: _vipLevel,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'VIP level'),
        ),
        _ImageUploadField(
          label: 'Asset URL',
          initialUrl: _assetUrl,
          adminService: const AdminService(),
          onChanged: (url) => setState(() => _assetUrl = url),
        ),
        TextField(
          controller: _gradientStart,
          decoration: const InputDecoration(labelText: 'Gradient start'),
        ),
        TextField(
          controller: _gradientEnd,
          decoration: const InputDecoration(labelText: 'Gradient end'),
        ),
        TextField(
          controller: _message,
          decoration: const InputDecoration(labelText: 'Message template'),
        ),
        TextField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sort order'),
        ),
        SwitchListTile(
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
          title: const Text('Active'),
        ),
      ],
      onSave: () {
        final key = _key.text.trim();
        final name = _name.text.trim();
        if (key.isEmpty || name.isEmpty) return;
        Navigator.of(context).pop(
          _EntranceBannerEditResult(
            bannerKey: key,
            name: name,
            arabicName: _nullIfEmpty(_arabicName.text),
            vipLevel: int.tryParse(_vipLevel.text.trim()),
            assetUrl: _assetUrl,
            gradientStart: _nullIfEmpty(_gradientStart.text),
            gradientEnd: _nullIfEmpty(_gradientEnd.text),
            messageTemplate: _nullIfEmpty(_message.text),
            isActive: _isActive,
            sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
          ),
        );
      },
    );
  }
}

class _AvatarFrameEditResult {
  const _AvatarFrameEditResult({
    required this.frameKey,
    required this.name,
    required this.category,
    required this.vipLevel,
    required this.requiredVipLevel,
    required this.assetUrl,
    required this.isActive,
    required this.isFeatured,
    required this.sortOrder,
  });

  final String frameKey;
  final String name;
  final String category;
  final int? vipLevel;
  final int? requiredVipLevel;
  final String? assetUrl;
  final bool isActive;
  final bool isFeatured;
  final int sortOrder;
}

class _AvatarFrameEditDialog extends StatefulWidget {
  const _AvatarFrameEditDialog({required this.frame});

  final AdminAvatarFrameSummary frame;

  @override
  State<_AvatarFrameEditDialog> createState() => _AvatarFrameEditDialogState();
}

class _AvatarFrameEditDialogState extends State<_AvatarFrameEditDialog> {
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _vipLevel;
  late final TextEditingController _requiredVipLevel;
  late final TextEditingController _sortOrder;
  late bool _isActive;
  late bool _isFeatured;
  String? _assetUrl;

  @override
  void initState() {
    super.initState();
    final frame = widget.frame;
    _key = TextEditingController(text: frame.frameKey);
    _name = TextEditingController(text: frame.name);
    _category = TextEditingController(text: frame.category);
    _vipLevel = TextEditingController(text: frame.vipLevel?.toString());
    _requiredVipLevel = TextEditingController(
      text: frame.requiredVipLevel?.toString(),
    );
    _sortOrder = TextEditingController(text: frame.sortOrder.toString());
    _isActive = frame.isActive;
    _isFeatured = frame.isFeatured;
    _assetUrl = frame.assetUrl;
  }

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _category.dispose();
    _vipLevel.dispose();
    _requiredVipLevel.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CatalogEditDialogShell(
      title: 'Edit avatar frame',
      fields: [
        TextField(
          controller: _key,
          decoration: const InputDecoration(labelText: 'Frame key'),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _category,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        TextField(
          controller: _vipLevel,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'VIP level'),
        ),
        TextField(
          controller: _requiredVipLevel,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Required VIP level'),
        ),
        _ImageUploadField(
          label: 'Asset URL',
          initialUrl: _assetUrl,
          adminService: const AdminService(),
          onChanged: (url) => setState(() => _assetUrl = url),
        ),
        TextField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sort order'),
        ),
        SwitchListTile(
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
          title: const Text('Active'),
        ),
        SwitchListTile(
          value: _isFeatured,
          onChanged: (value) => setState(() => _isFeatured = value),
          title: const Text('Featured'),
        ),
      ],
      onSave: () {
        final key = _key.text.trim();
        final name = _name.text.trim();
        final category = _category.text.trim();
        if (key.isEmpty || name.isEmpty || category.isEmpty) return;
        Navigator.of(context).pop(
          _AvatarFrameEditResult(
            frameKey: key,
            name: name,
            category: category,
            vipLevel: int.tryParse(_vipLevel.text.trim()),
            requiredVipLevel: int.tryParse(_requiredVipLevel.text.trim()),
            assetUrl: _assetUrl,
            isActive: _isActive,
            isFeatured: _isFeatured,
            sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
          ),
        );
      },
    );
  }
}

// ── Image Upload Field ────────────────────────────────────────────────────────

class _ImageUploadField extends StatefulWidget {
  const _ImageUploadField({
    required this.label,
    required this.initialUrl,
    required this.adminService,
    required this.onChanged,
  });

  final String label;
  final String? initialUrl;
  final AdminService adminService;
  final void Function(String? url) onChanged;

  @override
  State<_ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<_ImageUploadField> {
  late final TextEditingController _ctrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
      final url = await widget.adminService.uploadAdminAsset(
        bytes: bytes,
        filename: '${DateTime.now().millisecondsSinceEpoch}.$ext',
        contentType: contentType,
      );
      if (!mounted) return;
      _ctrl.text = url;
      widget.onChanged(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _ctrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(labelText: widget.label),
                onChanged: (v) =>
                    widget.onChanged(v.trim().isEmpty ? null : v.trim()),
              ),
            ),
            const SizedBox(width: 6),
            if (_uploading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.upload_rounded),
                tooltip: 'Pick & upload image',
                onPressed: _pickAndUpload,
              ),
          ],
        ),
        if (previewUrl.startsWith('http'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                previewUrl,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, a, b) => const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Promo Banner Edit Dialog ──────────────────────────────────────────────────

class _PromoBannerEditDialog extends StatefulWidget {
  const _PromoBannerEditDialog({required this.adminService, this.existing});

  final AdminService adminService;
  final AdminPromoBanner? existing;

  @override
  State<_PromoBannerEditDialog> createState() => _PromoBannerEditDialogState();
}

class _PromoBannerEditDialogState extends State<_PromoBannerEditDialog> {
  late final TextEditingController _slideKey;
  late final TextEditingController _sortOrder;
  late final TextEditingController _labelEn;
  late final TextEditingController _labelAr;
  late final TextEditingController _titleEn;
  late final TextEditingController _titleAr;
  late final TextEditingController _subtitleEn;
  late final TextEditingController _subtitleAr;
  late final TextEditingController _ctaEn;
  late final TextEditingController _ctaAr;
  late final TextEditingController _iconName;
  late final TextEditingController _gradientStart;
  late final TextEditingController _gradientMid;
  late final TextEditingController _gradientEnd;
  late final TextEditingController _iconBgColor;
  late final TextEditingController _targetRoute;
  late bool _isActive;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _slideKey = TextEditingController(text: b?.slideKey ?? '');
    _sortOrder = TextEditingController(text: (b?.sortOrder ?? 0).toString());
    _labelEn = TextEditingController(text: b?.labelEn ?? '');
    _labelAr = TextEditingController(text: b?.labelAr ?? '');
    _titleEn = TextEditingController(text: b?.titleEn ?? '');
    _titleAr = TextEditingController(text: b?.titleAr ?? '');
    _subtitleEn = TextEditingController(text: b?.subtitleEn ?? '');
    _subtitleAr = TextEditingController(text: b?.subtitleAr ?? '');
    _ctaEn = TextEditingController(text: b?.ctaEn ?? '');
    _ctaAr = TextEditingController(text: b?.ctaAr ?? '');
    _iconName = TextEditingController(text: b?.iconName ?? 'mic_rounded');
    _gradientStart = TextEditingController(text: b?.gradientStart ?? '');
    _gradientMid = TextEditingController(text: b?.gradientMid ?? '');
    _gradientEnd = TextEditingController(text: b?.gradientEnd ?? '');
    _iconBgColor = TextEditingController(text: b?.iconBgColor ?? '');
    _targetRoute = TextEditingController(text: b?.targetRoute ?? '');
    _isActive = b?.isActive ?? true;
    _imageUrl = b?.imageUrl;
  }

  @override
  void dispose() {
    _slideKey.dispose();
    _sortOrder.dispose();
    _labelEn.dispose();
    _labelAr.dispose();
    _titleEn.dispose();
    _titleAr.dispose();
    _subtitleEn.dispose();
    _subtitleAr.dispose();
    _ctaEn.dispose();
    _ctaAr.dispose();
    _iconName.dispose();
    _gradientStart.dispose();
    _gradientMid.dispose();
    _gradientEnd.dispose();
    _iconBgColor.dispose();
    _targetRoute.dispose();
    super.dispose();
  }

  String? _ne(String v) => v.trim().isEmpty ? null : v.trim();

  @override
  Widget build(BuildContext context) {
    return _CatalogEditDialogShell(
      title: widget.existing == null ? 'New promo banner' : 'Edit promo banner',
      fields: [
        TextField(
          controller: _slideKey,
          decoration: const InputDecoration(
            labelText: 'Slide key (unique ID)',
            hintText: 'e.g. explore_rooms',
          ),
        ),
        TextField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sort order'),
        ),
        const Divider(),
        TextField(
          controller: _labelEn,
          decoration: const InputDecoration(labelText: 'Label (EN)'),
        ),
        TextField(
          controller: _labelAr,
          decoration: const InputDecoration(labelText: 'Label (AR)'),
        ),
        TextField(
          controller: _titleEn,
          decoration: const InputDecoration(labelText: 'Title (EN)'),
        ),
        TextField(
          controller: _titleAr,
          decoration: const InputDecoration(labelText: 'Title (AR)'),
        ),
        TextField(
          controller: _subtitleEn,
          decoration: const InputDecoration(labelText: 'Subtitle (EN)'),
        ),
        TextField(
          controller: _subtitleAr,
          decoration: const InputDecoration(labelText: 'Subtitle (AR)'),
        ),
        TextField(
          controller: _ctaEn,
          decoration: const InputDecoration(labelText: 'CTA button (EN)'),
        ),
        TextField(
          controller: _ctaAr,
          decoration: const InputDecoration(labelText: 'CTA button (AR)'),
        ),
        const Divider(),
        TextField(
          controller: _iconName,
          decoration: const InputDecoration(
            labelText: 'Icon name',
            hintText: 'mic_rounded / card_giftcard_rounded / ...',
          ),
        ),
        TextField(
          controller: _gradientStart,
          decoration: const InputDecoration(
            labelText: 'Gradient start (hex AARRGGBB)',
            hintText: 'FF2D0D5E',
          ),
        ),
        TextField(
          controller: _gradientMid,
          decoration: const InputDecoration(
            labelText: 'Gradient mid (hex AARRGGBB)',
            hintText: 'FF5B1A9A',
          ),
        ),
        TextField(
          controller: _gradientEnd,
          decoration: const InputDecoration(
            labelText: 'Gradient end (hex AARRGGBB)',
            hintText: 'FF8B26D9',
          ),
        ),
        TextField(
          controller: _iconBgColor,
          decoration: const InputDecoration(
            labelText: 'Icon bg color (hex AARRGGBB)',
          ),
        ),
        const Divider(),
        _ImageUploadField(
          label: 'Image URL (optional)',
          initialUrl: _imageUrl,
          adminService: widget.adminService,
          onChanged: (url) => setState(() => _imageUrl = url),
        ),
        TextField(
          controller: _targetRoute,
          decoration: const InputDecoration(
            labelText: 'Target route',
            hintText: 'discovery / gifts / vip',
          ),
        ),
        SwitchListTile(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          title: const Text('Active'),
        ),
      ],
      onSave: () {
        final key = _slideKey.text.trim();
        if (key.isEmpty) return;
        Navigator.of(context).pop(
          AdminPromoBanner(
            id: widget.existing?.id ?? '',
            slideKey: key,
            sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
            isActive: _isActive,
            labelEn: _labelEn.text.trim(),
            labelAr: _labelAr.text.trim(),
            titleEn: _titleEn.text.trim(),
            titleAr: _titleAr.text.trim(),
            subtitleEn: _subtitleEn.text.trim(),
            subtitleAr: _subtitleAr.text.trim(),
            ctaEn: _ctaEn.text.trim(),
            ctaAr: _ctaAr.text.trim(),
            iconName: _iconName.text.trim().isEmpty
                ? 'mic_rounded'
                : _iconName.text.trim(),
            gradientStart: _ne(_gradientStart.text),
            gradientMid: _ne(_gradientMid.text),
            gradientEnd: _ne(_gradientEnd.text),
            iconBgColor: _ne(_iconBgColor.text),
            imageUrl: _imageUrl,
            targetRoute: _ne(_targetRoute.text),
          ),
        );
      },
    );
  }
}

class _CatalogEditDialogShell extends StatelessWidget {
  const _CatalogEditDialogShell({
    required this.title,
    required this.fields,
    required this.onSave,
  });

  final String title;
  final List<Widget> fields;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _kSurface,
      title: Text(title),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: fields),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: onSave, child: const Text('Save')),
      ],
    );
  }
}

class _AdminSideNav extends StatelessWidget {
  const _AdminSideNav({
    required this.selected,
    required this.roles,
    required this.pendingCount,
    required this.onSelected,
    this.onBrandTap,
  });

  final _AdminModule selected;
  final List<String> roles;
  final int pendingCount;
  final ValueChanged<_AdminModule> onSelected;
  final VoidCallback? onBrandTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      decoration: const BoxDecoration(
        color: _kSidebar,
        border: Border(right: BorderSide(color: _kBorder)),
      ),
      child: Column(
        children: [
          // Brand header — tap 7× quickly to open owner control panel
          GestureDetector(
            onTap: onBrandTap,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _AdminBrand(),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: _kBorder, height: 24, indent: 16, endIndent: 16),
          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _AdminModule.values
                  .map(
                    (module) => _NavItem(
                      module: module,
                      selected: selected == module,
                      badge: module == _AdminModule.finance && pendingCount > 0
                          ? pendingCount
                          : 0,
                      onTap: () => onSelected(module),
                    ),
                  )
                  .toList(),
            ),
          ),
          // Roles footer
          const Divider(color: _kBorder, height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your roles',
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: roles.isEmpty
                      ? const [_StatusBadge(label: 'no role')]
                      : roles.map((r) => _StatusBadge(label: r)).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.roles,
    required this.onRefresh,
    required this.onSignOut,
    required this.showTabs,
    required this.selected,
    required this.pendingCount,
    required this.onSelected,
  });

  final List<String> roles;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  final bool showTabs;
  final _AdminModule selected;
  final int pendingCount;
  final ValueChanged<_AdminModule> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                if (showTabs) const _AdminBrand(compact: true),
                if (!showTabs) ...[
                  Text(
                    _moduleLabel(selected),
                    style: const TextStyle(
                      color: _kTxt,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (pendingCount > 0 && selected == _AdminModule.finance) ...[
                    const SizedBox(width: 8),
                    _StatusBadge(label: '$pendingCount pending'),
                  ],
                ],
                const Spacer(),
                _StatusBadge(label: roles.isEmpty ? 'no role' : roles.first),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Refresh',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: _kGold,
                    size: 20,
                  ),
                ),
                IconButton(
                  onPressed: onSignOut,
                  tooltip: 'Sign out',
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: _kMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          // Mobile tab row
          if (showTabs)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: _AdminModule.values.map((module) {
                  final active = selected == module;
                  final hasBadge =
                      module == _AdminModule.finance && pendingCount > 0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => onSelected(module),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: active ? _kNavAccent : _kBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? _kNavAccent : _kBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _moduleLabel(module),
                              style: TextStyle(
                                color: active ? _kTxt : _kMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (hasBadge) ...[
                              const SizedBox(width: 5),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: _kAmber,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminBrand extends StatelessWidget {
  const _AdminBrand({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: compact ? 38 : 46,
          height: compact ? 38 : 46,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
            border: Border.all(color: _kGold),
          ),
          child: Image.asset(
            BrandingAssets.appIcon,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.graphic_eq_rounded, color: _kGold),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SrOOd', style: _titleStyle.copyWith(fontSize: 20)),
            Text('Admin System', style: _mutedStyle),
          ],
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.module,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final _AdminModule module;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: selected ? _kNavActive : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Left accent bar
                if (selected)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3,
                      decoration: const BoxDecoration(
                        color: _kNavAccent,
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _moduleIcon(module),
                        size: 18,
                        color: selected ? _kTxt : _kMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _moduleLabel(module),
                          style: TextStyle(
                            color: selected ? _kTxt : _kMuted,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (badge > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kAmber,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge > 99 ? '99+' : '$badge',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
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

class _ModuleTitle extends StatelessWidget {
  const _ModuleTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _kGold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kTxt,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 8),
                      const _StatusBadge(label: 'view only'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: _mutedStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.overview});

  final AdminOverview? overview;

  @override
  Widget build(BuildContext context) {
    // (label, value, icon, color)
    final items = [
      (
        'Pending',
        overview?.pendingRechargeCount ?? 0,
        Icons.pending_actions_rounded,
        _kAmber,
      ),
      (
        'Approved Today',
        overview?.approvedRechargeCountToday ?? 0,
        Icons.verified_rounded,
        _kGreen,
      ),
      (
        'Coins Today',
        overview?.totalCoinsChargedToday ?? 0,
        Icons.monetization_on_rounded,
        _kBlue,
      ),
      (
        'Gift Spend',
        overview?.totalGiftCoinsSpentToday ?? 0,
        Icons.card_giftcard_rounded,
        _kPurple,
      ),
      (
        'Diamonds',
        overview?.totalDiamondsEarnedToday ?? 0,
        Icons.diamond_rounded,
        _kNavAccent,
      ),
      (
        'Gifts Today',
        overview?.totalGiftTransactionsToday ?? 0,
        Icons.auto_awesome_rounded,
        _kGold,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = _statColumns(w);
        // Fixed pixel height per cell — robust equivalent of an aspect
        // ratio that can never derive a height smaller than the content,
        // so RenderFlex overflow is structurally impossible at any width.
        final cellHeight = cols == 1 ? 132.0 : 162.0;
        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: cellHeight,
          ),
          children: items
              .map(
                (item) => _AdminStatCard(
                  label: item.$1,
                  value: item.$2,
                  icon: item.$3,
                  color: item.$4,
                  wide: cols == 1,
                ),
              )
              .toList(),
        );
      },
    );
  }

  /// Responsive column count for the stat grid.
  static int _statColumns(double width) {
    if (width >= 1300) return 6;
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }
}

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color = _kGold,
    this.wide = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  /// Full-width single-column layout (very small screens).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    const iconBox = 44.0;
    final number = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        _formatAdminCount(value),
        maxLines: 1,
        style: const TextStyle(
          color: _kTxt,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          height: 1.0,
        ),
      ),
    );
    final caption = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _kMuted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );
    final iconChip = Container(
      width: iconBox,
      height: iconBox,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color, size: 22),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.10), Colors.transparent],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        // Single-column screens: icon beside the number (compact height).
        // Multi-column: stacked vertically with the icon on top.
        child: wide
            ? Row(
                children: [
                  iconChip,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: number),
                        const SizedBox(height: 4),
                        caption,
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconChip,
                  const Spacer(),
                  number,
                  const SizedBox(height: 6),
                  caption,
                ],
              ),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 780) {
          return Column(children: [left, const SizedBox(height: 14), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _AdminSectionCard extends StatelessWidget {
  const _AdminSectionCard({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with left accent bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _kNavAccent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _kTxt,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
          const SizedBox(height: 2),
          const Divider(color: _kBorder, height: 16, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _RechargeRequestTile extends StatelessWidget {
  const _RechargeRequestTile({
    required this.request,
    required this.canFinance,
    required this.onApprove,
    required this.onReject,
  });

  final AdminRechargeRequest request;
  final bool canFinance;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return _AdminListTile(
      icon: Icons.add_card_rounded,
      title:
          '${request.nickname ?? request.publicUserId ?? request.userId} - ${request.requestedCoins} coins',
      subtitle:
          '${request.method.toUpperCase()} - Ref ${request.referenceCode ?? '-'} - Agent ${request.agentCode ?? '-'}',
      trailing: canFinance
          ? Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: const BorderSide(color: _kRed),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Approve'),
                ),
              ],
            )
          : const _RoleChip(label: 'view only'),
    );
  }
}

class _WithdrawalRequestTile extends StatelessWidget {
  const _WithdrawalRequestTile({
    required this.request,
    required this.canFinance,
    required this.onApprove,
    required this.onReject,
  });

  final AdminWithdrawalRequest request;
  final bool canFinance;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final user =
        request.displayName ?? request.publicUserId ?? request.userId;
    final split = '\$${request.hostShareUsd.toStringAsFixed(2)} net'
        '${request.agencyShareUsd > 0 ? ' (agency \$${request.agencyShareUsd.toStringAsFixed(2)})' : ''}';
    return _AdminListTile(
      icon: Icons.arrow_circle_up_rounded,
      title:
          '$user — ${request.diamondsAmount} 💎 (\$${request.grossUsd.toStringAsFixed(2)} gross)',
      subtitle:
          '${request.method.toUpperCase()} · ${request.accountDetails} · $split',
      trailing: canFinance
          ? Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: const BorderSide(color: _kRed),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Approve'),
                ),
              ],
            )
          : const _RoleChip(label: 'view only'),
    );
  }
}

class _WalletLookupCard extends StatelessWidget {
  const _WalletLookupCard({
    required this.lookupController,
    required this.coinsController,
    required this.diamondsController,
    required this.noteController,
    required this.wallet,
    required this.canFinance,
    required this.onSearch,
    required this.onAdjust,
  });

  final TextEditingController lookupController;
  final TextEditingController coinsController;
  final TextEditingController diamondsController;
  final TextEditingController noteController;
  final AdminWalletSummary? wallet;
  final bool canFinance;
  final VoidCallback onSearch;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final item = wallet;

    return _AdminSectionCard(
      title: 'Wallet Lookup',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AdminTextField(
            controller: lookupController,
            label: 'Public user ID',
            icon: Icons.search_rounded,
            onSubmitted: (_) => onSearch(),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onSearch,
            style: FilledButton.styleFrom(
              backgroundColor: _kNavAccent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('Search wallet'),
          ),
          if (item != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: _kGold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.nickname ?? item.publicUserId ?? item.userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _titleStyle.copyWith(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Public ID: ${item.publicUserId ?? '-'}',
                    style: _mutedStyle,
                  ),
                  const SizedBox(height: 4),
                  Text('Coins: ${item.coinsBalance}', style: _mutedStyle),
                  const SizedBox(height: 4),
                  Text('Diamonds: ${item.diamondsBalance}', style: _mutedStyle),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _AdminTextField(
              controller: coinsController,
              label: 'Coins delta',
              icon: Icons.toll_rounded,
              keyboardType: TextInputType.number,
              helper: 'Use positive or negative number',
            ),
            const SizedBox(height: 10),
            _AdminTextField(
              controller: diamondsController,
              label: 'Diamonds delta',
              icon: Icons.diamond_rounded,
              keyboardType: TextInputType.number,
              helper: 'Use positive or negative number',
            ),
            const SizedBox(height: 10),
            _AdminTextField(
              controller: noteController,
              label: 'Admin note',
              icon: Icons.notes_rounded,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canFinance ? onAdjust : null,
              style: FilledButton.styleFrom(
                backgroundColor: _kNavAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Apply adjustment'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.label,
    required this.onSearch,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final field = _AdminTextField(
          controller: controller,
          label: label,
          icon: Icons.search_rounded,
          onSubmitted: (_) => onSearch(),
        );
        final btn = FilledButton.icon(
          onPressed: onSearch,
          style: FilledButton.styleFrom(
            backgroundColor: _kNavAccent,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: const Icon(Icons.search_rounded, size: 16),
          label: const Text('Search'),
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [field, const SizedBox(height: 8), btn],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 10),
            btn,
          ],
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.canManageRoles,
    required this.onOpen,
    this.onAssign,
    this.onRemoveRole,
  });

  final AdminUserSummary user;
  final bool canManageRoles;
  final VoidCallback onOpen;
  final VoidCallback? onAssign;
  final ValueChanged<String>? onRemoveRole;

  @override
  Widget build(BuildContext context) {
    return _AdminListTile(
      icon: Icons.person_rounded,
      title: user.title,
      subtitle:
          '${user.publicUserId ?? user.userId} - ${user.coinsBalance} coins - VIP ${user.vipLevel}',
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          runSpacing: 6,
          children: [
            ActionChip(
              avatar: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open'),
              onPressed: onOpen,
            ),
            ...user.roles.map(
              (role) => InputChip(
                label: Text(AdminRoleSpec.byRole(role).label),
                onDeleted: canManageRoles ? () => onRemoveRole?.call(role) : null,
              ),
            ),
            if (canManageRoles)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Role'),
                onPressed: onAssign,
              ),
          ],
        ),
      ),
    );
  }
}

class _AgencyListCard extends StatelessWidget {
  const _AgencyListCard({
    required this.agencies,
    required this.canManage,
    required this.onCreateAgency,
    required this.onToggleAgency,
  });

  final List<AdminAgency> agencies;
  final bool canManage;
  final VoidCallback onCreateAgency;
  final ValueChanged<AdminAgency> onToggleAgency;

  @override
  Widget build(BuildContext context) {
    return _AdminSectionCard(
      title: 'Agencies',
      action: canManage
          ? TextButton.icon(
              onPressed: onCreateAgency,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Agency'),
            )
          : const _RoleChip(label: 'view only'),
      child: agencies.isEmpty
          ? const _AdminEmptyState(
              icon: Icons.business_rounded,
              title: 'No agencies',
              subtitle: 'Recharge agencies will appear here.',
            )
          : Column(
              children: agencies
                  .map(
                    (agency) => _AdminListTile(
                      icon: Icons.business_rounded,
                      title: '${agency.name} (${agency.code})',
                      subtitle: agency.whatsapp ?? agency.country ?? '-',
                      trailing: Switch(
                        value: agency.isActive,
                        onChanged: canManage
                            ? (_) => onToggleAgency(agency)
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _AgentListCard extends StatelessWidget {
  const _AgentListCard({
    required this.agents,
    required this.canManage,
    required this.onCreateAgent,
    required this.onToggleAgent,
  });

  final List<AdminAgent> agents;
  final bool canManage;
  final VoidCallback onCreateAgent;
  final ValueChanged<AdminAgent> onToggleAgent;

  @override
  Widget build(BuildContext context) {
    return _AdminSectionCard(
      title: 'Agents',
      action: canManage
          ? TextButton.icon(
              onPressed: onCreateAgent,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Agent'),
            )
          : const _RoleChip(label: 'view only'),
      child: agents.isEmpty
          ? const _AdminEmptyState(
              icon: Icons.support_agent_rounded,
              title: 'No agents',
              subtitle: 'Recharge agents will appear here.',
            )
          : Column(
              children: agents
                  .map(
                    (agent) => _AdminListTile(
                      icon: Icons.support_agent_rounded,
                      title: '${agent.name} (${agent.code})',
                      subtitle: agent.agencyCode ?? agent.agencyName ?? '-',
                      trailing: Switch(
                        value: agent.isActive,
                        onChanged: canManage
                            ? (_) => onToggleAgent(agent)
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _GiftAdminCard extends StatelessWidget {
  const _GiftAdminCard({
    required this.gift,
    required this.canManage,
    required this.onToggle,
    required this.onEdit,
  });

  final AdminGiftSummary gift;
  final bool canManage;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: gift.isActive ? _kGreen : _kBorder,
          width: gift.isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GiftIcon(icon: gift.icon),
              const Spacer(),
              IconButton(
                onPressed: canManage ? onEdit : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
              ),
              Switch(
                value: gift.isActive,
                onChanged: canManage ? (_) => onToggle() : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(gift.name, style: _titleStyle.copyWith(fontSize: 18)),
          Text('${gift.priceCoins} coins', style: _mutedStyle),
          const SizedBox(height: 8),
          _RoleChip(label: '${gift.sentCount} sent'),
        ],
      ),
    );
  }
}

class _GiftIcon extends StatelessWidget {
  const _GiftIcon({required this.icon});

  final String? icon;

  @override
  Widget build(BuildContext context) {
    final source = icon?.trim();
    if (source != null && source.startsWith('http')) {
      return Image.network(source, width: 42, height: 42, fit: BoxFit.contain);
    }
    return const Icon(Icons.card_giftcard_rounded, color: _kGold, size: 42);
  }
}

class _CatalogChip extends StatelessWidget {
  const _CatalogChip({
    required this.title,
    required this.subtitle,
    required this.active,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? _kNavAccent : _kBorder,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle.copyWith(fontSize: 14),
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.edit_rounded, color: _kNavAccent, size: 16),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mutedStyle.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 8),
            _RoleChip(label: active ? 'active' : 'off'),
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile(
    this.room, {
    required this.canManage,
    required this.onClose,
    required this.onReopen,
  });

  final AdminRoomSummary room;
  final bool canManage;
  final VoidCallback onClose;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    return _AdminListTile(
      icon: Icons.meeting_room_rounded,
      title: room.name,
      subtitle:
          'Owner ${room.ownerName ?? room.ownerPublicUserId ?? room.ownerId} - ${room.activeMembers}/${room.maxSeats} active${room.closedReason == null ? '' : ' - ${room.closedReason}'}',
      trailing: Wrap(
        spacing: 6,
        children: [
          _RoleChip(label: room.isClosed ? 'closed' : 'live'),
          _RoleChip(label: room.isLocked ? 'locked' : 'open'),
          if (room.isPrivate) const _RoleChip(label: 'private'),
          if (canManage)
            TextButton(
              onPressed: room.isClosed ? onReopen : onClose,
              child: Text(room.isClosed ? 'Reopen' : 'Close'),
            ),
        ],
      ),
    );
  }
}

class _WalletTransactionTile extends StatelessWidget {
  const _WalletTransactionTile(this.transaction);

  final AdminWalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return _AdminListTile(
      icon: Icons.receipt_long_rounded,
      title:
          '${transaction.nickname ?? transaction.publicUserId ?? transaction.userId} - ${transaction.type}',
      subtitle: transaction.note ?? _dateLabel(transaction.createdAt),
      trailing: Text(
        '${transaction.coinsDelta >= 0 ? '+' : ''}${transaction.coinsDelta}c'
        ' / ${transaction.diamondsDelta >= 0 ? '+' : ''}${transaction.diamondsDelta}d',
        style: TextStyle(
          color: transaction.coinsDelta >= 0 ? _kGreen : _kRed,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _GiftTransactionTile extends StatelessWidget {
  const _GiftTransactionTile(this.gift);

  final AdminGiftTransaction gift;

  @override
  Widget build(BuildContext context) {
    return _AdminListTile(
      icon: Icons.card_giftcard_rounded,
      title: '${gift.giftName} - ${gift.giftPriceCoins} coins',
      subtitle:
          '${gift.senderPublicUserId ?? '-'} -> ${gift.receiverPublicUserId ?? '-'}',
      trailing: _RoleChip(label: _dateLabel(gift.createdAt)),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile(this.log);

  final AdminAuditLog log;

  @override
  Widget build(BuildContext context) {
    return _AdminListTile(
      icon: Icons.fact_check_rounded,
      title: log.action,
      subtitle:
          '${log.adminName ?? log.adminPublicUserId ?? 'admin'} - ${log.entityType ?? '-'} - ${_dateLabel(log.createdAt)}',
      trailing: _RoleChip(
        label: log.targetName ?? log.targetPublicUserId ?? '-',
      ),
    );
  }
}

class _AdminListTile extends StatelessWidget {
  const _AdminListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final leading = Row(
            children: [
              Icon(icon, color: _kMuted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _titleStyle.copyWith(fontSize: 14),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mutedStyle.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leading,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: trailing),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: leading),
              const SizedBox(width: 8),
              Flexible(child: trailing),
            ],
          );
        },
      ),
    );
  }
}

/// Skeleton loading placeholder — shows 3 shimmering ghost tiles.
class _AdminSkeletonList extends StatefulWidget {
  const _AdminSkeletonList();
  static const _count = 3;
  @override
  State<_AdminSkeletonList> createState() => _AdminSkeletonListState();
}

class _AdminSkeletonListState extends State<_AdminSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final opacity = 0.35 + _anim.value * 0.35;
        return Column(
          children: List.generate(
            _AdminSkeletonList._count,
            (i) => _SkeletonTile(opacity: opacity),
          ),
        );
      },
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile({required this.opacity});
  final double opacity;

  Widget _box(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: _kBorder.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(6),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          _box(36, 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(double.infinity, 12),
                const SizedBox(height: 8),
                _box(160, 10),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _box(64, 24),
        ],
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _kBorder,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _kMuted, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kTxt,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: _mutedStyle),
        ],
      ),
    );
  }
}

class _AdminShellMessage extends StatelessWidget {
  const _AdminShellMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
    this.onSignOut,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AdminEmptyState(icon: icon, title: title, subtitle: subtitle),
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTxt,
                    side: const BorderSide(color: _kBorder),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                ),
              ],
              if (onSignOut != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onSignOut,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kNavAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Sign out / switch account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Semantic status badge — auto-picks color by label keyword.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  static Color _colorFor(String l) {
    final s = l.toLowerCase();
    if (s.contains('approv') ||
        s.contains('active') ||
        s.contains('live') ||
        s.contains('open') ||
        s.contains('success') ||
        s.contains('done') ||
        s.contains('earned') ||
        s.contains('reopen')) {
      return _kGreen;
    }
    if (s.contains('pending') ||
        s.contains('wait') ||
        s.contains('locked') ||
        s.contains('warn')) {
      return _kAmber;
    }
    if (s.contains('reject') ||
        s.contains('ban') ||
        s.contains('block') ||
        s.contains('close') ||
        s.contains('off') ||
        s.contains('cancel') ||
        s.contains('danger') ||
        s.contains('mute')) {
      return _kRed;
    }
    if (s.contains('coin') || s.contains('charge') || s.contains('info')) {
      return _kBlue;
    }
    if (s.contains('super') ||
        s.contains('vip') ||
        s.contains('gift') ||
        s.contains('diamond')) {
      return _kPurple;
    }
    return _kGold;
  }

  @override
  Widget build(BuildContext context) {
    final c = _colorFor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Backwards-compat alias so existing call-sites still compile.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => _StatusBadge(label: label);
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

IconData _moduleIcon(_AdminModule module) {
  return switch (module) {
    _AdminModule.overview => Icons.dashboard_customize_rounded,
    _AdminModule.finance => Icons.account_balance_wallet_rounded,
    _AdminModule.users => Icons.manage_accounts_rounded,
    _AdminModule.bd => Icons.handshake_rounded,
    _AdminModule.content => Icons.card_giftcard_rounded,
    _AdminModule.rooms => Icons.mic_external_on_rounded,
    _AdminModule.banners => Icons.view_carousel_rounded,
    _AdminModule.audit  => Icons.fact_check_rounded,
    _AdminModule.games    => Icons.sports_esports_rounded,
    _AdminModule.vip      => Icons.workspace_premium_rounded,
    _AdminModule.charisma => Icons.emoji_events_rounded,
  };
}

String _moduleLabel(_AdminModule module) {
  return switch (module) {
    _AdminModule.overview => 'Overview',
    _AdminModule.finance => 'Finance',
    _AdminModule.users => 'Users',
    _AdminModule.bd => 'BD',
    _AdminModule.content => 'Content',
    _AdminModule.rooms => 'Rooms',
    _AdminModule.banners => 'Banners',
    _AdminModule.audit  => 'Audit',
    _AdminModule.games    => 'Games',
    _AdminModule.vip      => 'VIP',
    _AdminModule.charisma => 'Charisma',
  };
}

String _formatAdminCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toString();
}

String _dateLabel(DateTime? value) {
  if (value == null) return '-';
  return '${value.month}/${value.day}/${value.year}';
}

String? _nullIfEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

const _titleStyle = TextStyle(
  color: _kTxt,
  fontSize: 18,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.2,
);

const _mutedStyle = TextStyle(
  color: _kMuted,
  fontSize: 13,
  fontWeight: FontWeight.w500,
);

