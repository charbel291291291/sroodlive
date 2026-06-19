import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';

import '../../../shared/branding/branding_assets.dart';
import '../models/admin_models.dart';
import '../services/admin_access_service.dart';
import '../services/admin_service.dart';
import '../../games/screens/hungry_cat_admin_panel.dart';
import '../../games/screens/rocket_crash_admin_panel.dart';
import '../../games/screens/srood_loto_admin_panel.dart';
import '../../charisma/screens/charisma_admin_panel.dart';
import '../../startup_promo/models/startup_promo.dart' show AdminStartupPromo;
import '../../startup_promo/services/startup_promo_service.dart';
import 'owner_game_control_screen.dart';
import 'vip_visual_preview_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

enum _AdminModule {
  dashboard,   // Command Center – overview, quick alerts
  users,       // Users & Roles
  rooms,       // Rooms
  finance,     // Finance & Payments
  vip,         // VIP Management
  gifts,       // Gifts & Store
  agencies,    // Agencies & Agents (BD)
  moderation,  // Moderation & Reports
  marketing,   // Marketing & App Content
  system,      // System & Audit
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Design tokens â€” edit here to restyle the panel
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  _AdminModule _module = _AdminModule.dashboard;
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
  List<_AdminStartupPromoRow> _startupPromos = const [];
  AdminWalletSummary? _walletLookup;

  // â”€â”€ Phase 2 additions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // Finance date range (null = today)
  DateTime? _financeFrom;
  DateTime? _financeTo;
  bool _financeReloading = false;

  // Withdrawal history tab
  List<AdminWithdrawalRequest> _withdrawalHistory = const [];

  // Audit log filters
  String? _auditFilterAction;
  String? _auditFilterTargetType;
  DateTime? _auditFilterFrom;
  DateTime? _auditFilterTo;
  bool _auditFiltering = false;

  // Reports
  List<AdminReport> _reports = const [];
  String? _reportsStatusFilter;

  // Auto-moderation events
  List<_ModEvent> _modEvents = const [];
  String? _modEventsStatusFilter;
  bool _modEventsLoading = false;

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

  // â”€â”€ Role helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool get _canFinance     => _adminRole.hasPermission(kPermWalletCredit);
  bool get _canBd          => _adminRole.hasPermission(kPermAgenciesView);
  bool get _canContent     => _adminRole.hasPermission(kPermGiftsManage);
  // Marketing & App Content uses banners.manage, which super_admin already has.
  // Keeping this separate from _canContent (gifts.manage) so the two access
  // levels are independently controllable per role.
  bool get _canMarketing   => _adminRole.hasPermission(kPermBanners);
  bool get _canRooms       => _adminRole.hasPermission(kPermRoomsClose);
  bool get _canUnban       => _adminRole.canUnban;
  bool get _canManageStaff => _adminRole.isOSuperAdmin;

  // ── Pending counts for nav badges ──────────────────────────────────────────
  int get _pendingRechargesCount   => _pending.length;
  int get _pendingWithdrawalsCount => _pendingWithdrawals.length;
  int get _pendingReportsCount     =>
      _reports.where((r) => r.status == 'pending').length;
  int get _financeBadgeCount       =>
      _pendingRechargesCount + _pendingWithdrawalsCount;
  Map<_AdminModule, int> get _navBadges => {
    _AdminModule.finance:    _financeBadgeCount,
    _AdminModule.moderation: _pendingReportsCount,
  };

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

      if (!mounted) return;
      setState(() {
        _adminRole = adminRole;
        _roles     = roles;
        _canAccess = true;
      });

      final overview = await _adminService.fetchOverview();
      final pending = await _adminService.fetchRechargeRequests(
        status: 'pending',
      );
      final pendingWithdrawals = await _adminService.fetchWithdrawalRequests();
      final withdrawalHistory  = await _adminService.fetchWithdrawalHistory();
      final walletTransactions = await _adminService.fetchWalletTransactions();
      final giftTransactions = await _adminService.fetchGiftTransactions();
      final agencies = await _adminService.fetchAgencies();
      final agents = await _adminService.fetchAgents();
      final users = await _adminService.searchUsers();
      final rooms = await _adminService.fetchRooms();
      final gifts = await _adminService.fetchGifts();
      final auditLogs = await _adminService.fetchAuditLogs();
      final financeReport = await _adminService.fetchFinanceReport(
        from: _financeFrom,
        to: _financeTo,
      );
      final bdReport = await _adminService.fetchBdReport();
      final avatarFrames = await _adminService.fetchAvatarFrames();
      final vipPackages = await _adminService.fetchVipPackages();
      final entranceBanners = await _adminService.fetchEntranceBanners();
      final giftCategories = await _adminService.fetchGiftCategories();
      final promoBanners = await _adminService.fetchPromoBanners();
      final startupPromosRaw = _canMarketing
          ? await const StartupPromoService().adminListPromos()
          : <AdminStartupPromo>[];
      final reports = await _adminService.fetchReports(
        status: _reportsStatusFilter,
      );

      if (!mounted) return;
      setState(() {
        _adminRole = adminRole;
        _roles     = roles;
        _canAccess = true;
        _overview  = overview;
        _pending = pending;
        _pendingWithdrawals = pendingWithdrawals;
        _withdrawalHistory = withdrawalHistory;
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
        _startupPromos = startupPromosRaw
            .map((p) => _AdminStartupPromoRow.fromModel(p))
            .toList();
        _reports = reports;
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
        _showSnack(context.isArabic
            ? 'ÙÙ‚Ø· O-Super Admin ÙŠÙ…ÙƒÙ†Ù‡ ÙÙƒ Ø§Ù„Ø­Ø¸Ø±'
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
        _showSnack(context.isArabic
            ? 'ÙÙ‚Ø· O-Super Admin ÙŠÙ…ÙƒÙ†Ù‡ ÙÙƒ Ø§Ù„Ø­Ø¸Ø±'
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

  // â”€â”€ Finance date range â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _reloadFinanceReport() async {
    if (_financeReloading) return;
    setState(() => _financeReloading = true);
    try {
      final report = await _adminService.fetchFinanceReport(
        from: _financeFrom,
        to: _financeTo,
      );
      if (mounted) setState(() => _financeReport = report);
    } catch (e) {
      if (mounted) _showSnack('Finance report failed: $e');
    } finally {
      if (mounted) setState(() => _financeReloading = false);
    }
  }

  Future<void> _pickFinanceDate({required bool isFrom}) async {
    final initial = (isFrom ? _financeFrom : _financeTo) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _kGold,
            onPrimary: Colors.black,
            surface: _kSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _financeFrom = DateTime(picked.year, picked.month, picked.day);
      } else {
        _financeTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
    await _reloadFinanceReport();
  }

  void _resetFinanceDates() {
    setState(() { _financeFrom = null; _financeTo = null; });
    _reloadFinanceReport();
  }

  // â”€â”€ Audit log search â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _searchAuditLogs() async {
    if (_auditFiltering) return;
    setState(() => _auditFiltering = true);
    try {
      final logs = await _adminService.searchAuditLogs(
        action: _auditFilterAction?.trim().isEmpty == true ? null : _auditFilterAction?.trim(),
        targetType: _auditFilterTargetType?.trim().isEmpty == true ? null : _auditFilterTargetType?.trim(),
        from: _auditFilterFrom,
        to: _auditFilterTo,
      );
      if (mounted) setState(() => _auditLogs = logs);
    } catch (e) {
      if (mounted) _showSnack('Audit search failed: $e');
    } finally {
      if (mounted) setState(() => _auditFiltering = false);
    }
  }

  void _resetAuditFilters() {
    setState(() {
      _auditFilterAction = null;
      _auditFilterTargetType = null;
      _auditFilterFrom = null;
      _auditFilterTo = null;
    });
    _searchAuditLogs();
  }

  Future<void> _pickAuditDate({required bool isFrom}) async {
    final initial = (isFrom ? _auditFilterFrom : _auditFilterTo) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _kGold,
            onPrimary: Colors.black,
            surface: _kSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _auditFilterFrom = DateTime(picked.year, picked.month, picked.day);
      } else {
        _auditFilterTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  // â”€â”€ Agency update with commission â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _editAgency(AdminAgency agency) async {
    final result = await showDialog<_AgencyEditResult>(
      context: context,
      builder: (context) => _AgencyEditDialog(agency: agency, canEditCommission: _adminRole.hasPermission(kPermWalletCredit)),
    );
    if (result == null) return;

    try {
      await _adminService.updateAgency(
        agencyId: agency.id,
        name: result.name.trim().isEmpty ? null : result.name.trim(),
        whatsapp: result.whatsapp.trim().isEmpty ? null : result.whatsapp.trim(),
        country: result.country.trim().isEmpty ? null : result.country.trim(),
        commissionRate: result.commissionRate,
      );
      await _load();
      if (!mounted) return;
      _showSnack('Agency updated');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Agency update failed: $e');
    }
  }

  // â”€â”€ Reports â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _processReport(AdminReport report, String newStatus) async {
    String? note;
    if (newStatus == 'resolved' || newStatus == 'rejected' || newStatus == 'needs_more_info') {
      note = await _askForText(
        title: 'Resolution note (optional)',
        label: 'Note for ${newStatus.replaceAll('_', ' ')}',
      );
    }

    try {
      await _adminService.updateReportStatus(
        reportId: report.id,
        status: newStatus,
        resolutionNote: note?.trim().isEmpty == true ? null : note?.trim(),
      );
      final reports = await _adminService.fetchReports(status: _reportsStatusFilter);
      if (!mounted) return;
      setState(() => _reports = reports);
      _showSnack('Report marked as ${newStatus.replaceAll('_', ' ')}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Report update failed: $e');
    }
  }

  Future<void> _reloadReports() async {
    final reports = await _adminService.fetchReports(status: _reportsStatusFilter);
    if (!mounted) return;
    setState(() => _reports = reports);
  }

  Future<void> _reloadModEvents() async {
    setState(() => _modEventsLoading = true);
    try {
      final rows = await SupabaseService.requiredClient.rpc(
        'admin_get_moderation_events',
        params: {
          'p_limit': 100,
          'p_status': _modEventsStatusFilter,
        },
      );
      if (!mounted) return;
      setState(() {
        _modEvents = (rows as List)
            .map((r) => _ModEvent.fromJson(r as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _modEventsLoading = false);
    }
  }

  Future<void> _applyModerationAction({
    required String targetUserId,
    required String actionType,
    required String reason,
    String? roomId,
    DateTime? expiresAt,
    String? eventId,
    String? reportId,
  }) async {
    try {
      await SupabaseService.requiredClient.rpc('admin_apply_moderation_action', params: {
        'p_target_user_id': targetUserId,
        'p_action_type':    actionType,
        'p_reason':         reason,
        'p_room_id':        roomId,
        'p_expires_at':     expiresAt?.toIso8601String(),
        'p_event_id':       eventId,
        'p_report_id':      reportId,
      });
      _showSnack('Action applied: ${actionType.replaceAll('_', ' ')}');
      unawaited(_reloadModEvents());
      unawaited(_reloadReports());
    } catch (e) {
      _showSnack('Action failed: $e');
    }
  }

  Future<void> _showModerationActionDialog({
    required String targetUserId,
    String? targetName,
    String? eventId,
    String? reportId,
    String? roomId,
  }) async {
    String selectedAction = 'chat_mute';
    DateTime? expiresAt = DateTime.now().add(const Duration(hours: 1));
    String reason = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _kSurface,
          title: Text('Moderate: ${targetName ?? targetUserId.substring(0, 8)}',
              style: const TextStyle(color: _kTxt, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogDropdown<String>(
                label: 'Action',
                value: selectedAction,
                items: const [
                  DropdownMenuItem(value: 'warning',     child: Text('Warning (no restriction)')),
                  DropdownMenuItem(value: 'chat_mute',   child: Text('Chat Mute (temp)')),
                  DropdownMenuItem(value: 'account_ban', child: Text('Account Ban (temp)')),
                  DropdownMenuItem(value: 'gift_block',  child: Text('Gift Block')),
                  DropdownMenuItem(value: 'dismissed',   child: Text('Dismiss / False Positive')),
                ],
                onChanged: (v) => setLocal(() => selectedAction = v ?? selectedAction),
              ),
              const SizedBox(height: 8),
              if (selectedAction != 'dismissed' && selectedAction != 'warning') ...[
                _DialogDropdown<Duration>(
                  label: 'Duration',
                  value: const Duration(hours: 1),
                  items: const [
                    DropdownMenuItem(value: Duration(minutes: 15), child: Text('15 minutes')),
                    DropdownMenuItem(value: Duration(hours: 1),    child: Text('1 hour')),
                    DropdownMenuItem(value: Duration(hours: 6),    child: Text('6 hours')),
                    DropdownMenuItem(value: Duration(hours: 24),   child: Text('24 hours')),
                    DropdownMenuItem(value: Duration(days: 7),     child: Text('7 days')),
                  ],
                  onChanged: (d) => setLocal(() =>
                      expiresAt = d != null ? DateTime.now().add(d) : null),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                style: const TextStyle(color: _kTxt),
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  labelStyle: TextStyle(color: _kMuted),
                ),
                onChanged: (v) => reason = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: _kMuted)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _applyModerationAction(
                  targetUserId: targetUserId,
                  actionType:   selectedAction,
                  reason:       reason.isEmpty ? selectedAction : reason,
                  roomId:       roomId,
                  expiresAt:    expiresAt,
                  eventId:      eventId,
                  reportId:     reportId,
                );
              },
              style: FilledButton.styleFrom(backgroundColor: _kRed),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
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
                          badges: _navBadges,
                          onSelected: (module) {
                            setState(() => _module = module);
                            if (module == _AdminModule.moderation) {
                              unawaited(_reloadModEvents());
                            }
                          },
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
                              badges: _navBadges,
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
      _AdminModule.dashboard  => _buildDashboard(),
      _AdminModule.users      => _buildUsers(),
      _AdminModule.rooms      => _buildRooms(),
      _AdminModule.finance    => _buildFinance(),
      _AdminModule.vip        => _buildVipManagement(),
      _AdminModule.gifts      => _buildGiftsStore(),
      _AdminModule.agencies   => _buildAgenciesSection(),
      _AdminModule.moderation => _buildModeration(),
      _AdminModule.marketing  => _buildMarketing(),
      _AdminModule.system     => _buildSystem(),
    };
  }

  Widget _buildFinance() {
    // Quick-range label for the header subtitle
    String rangeLabel;
    if (_financeFrom == null && _financeTo == null) {
      rangeLabel = 'Today';
    } else {
      String fmt(DateTime? d) => d == null
          ? '?'
          : '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      rangeLabel = '${fmt(_financeFrom)} â†’ ${fmt(_financeTo)}';
    }

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

        // â”€â”€ Date range selector â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        _AdminSectionCard(
          title: 'Report period: $rangeLabel',
          action: _financeReloading
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kGold),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _reloadFinanceReport,
                  tooltip: 'Reload',
                ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _QuickRangeButton(
                label: 'Today',
                selected: _financeFrom == null && _financeTo == null,
                onTap: _resetFinanceDates,
              ),
              _QuickRangeButton(
                label: 'Yesterday',
                selected: false,
                onTap: () {
                  final y = DateTime.now().subtract(const Duration(days: 1));
                  setState(() {
                    _financeFrom = DateTime(y.year, y.month, y.day);
                    _financeTo   = DateTime(y.year, y.month, y.day, 23, 59, 59);
                  });
                  _reloadFinanceReport();
                },
              ),
              _QuickRangeButton(
                label: 'Last 7 days',
                selected: false,
                onTap: () {
                  final now = DateTime.now();
                  setState(() {
                    _financeFrom = now.subtract(const Duration(days: 6));
                    _financeTo   = null;
                  });
                  _reloadFinanceReport();
                },
              ),
              _QuickRangeButton(
                label: 'Last 30 days',
                selected: false,
                onTap: () {
                  final now = DateTime.now();
                  setState(() {
                    _financeFrom = now.subtract(const Duration(days: 29));
                    _financeTo   = null;
                  });
                  _reloadFinanceReport();
                },
              ),
              OutlinedButton.icon(
                onPressed: () => _pickFinanceDate(isFrom: true),
                icon: const Icon(Icons.calendar_today_rounded, size: 14),
                label: Text(_financeFrom == null
                    ? 'From'
                    : '${_financeFrom!.month}/${_financeFrom!.day}/${_financeFrom!.year}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kGold,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickFinanceDate(isFrom: false),
                icon: const Icon(Icons.calendar_today_rounded, size: 14),
                label: Text(_financeTo == null
                    ? 'To'
                    : '${_financeTo!.month}/${_financeTo!.day}/${_financeTo!.year}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kGold,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
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

        // â”€â”€ Withdrawal section with Pending / History tabs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        _WithdrawalTabCard(
          pendingList: _pendingWithdrawals,
          historyList: _withdrawalHistory,
          canFinance: _canFinance,
          onApprove: (w) => _approveWithdrawal(w),
          onReject:  (w) => _rejectWithdrawal(w),
          onRefresh: _load,
        ),
        const SizedBox(height: 14),

        _AdminSectionCard(
          title: 'BD Performance â€” selected period',
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

  // ── Startup Promo admin actions ───────────────────────────────────────────

  Future<void> _editStartupPromo([_AdminStartupPromoRow? existing]) async {
    final result = await showDialog<_AdminStartupPromoRow>(
      context: context,
      builder: (_) => _StartupPromoEditDialog(
        existing: existing,
        adminService: _adminService,
      ),
    );
    if (result == null) return;
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await const StartupPromoService().adminSavePromo(
        id: result.id.isEmpty ? null : result.id,
        title: result.title,
        imageUrl: result.imageUrl,
        isActive: result.isActive,
        startsAt: result.startsAt,
        endsAt: result.endsAt,
        durationSeconds: result.durationSeconds,
        frequency: result.frequency,
        priority: result.priority,
      );
      if (!mounted) return;
      _showSnack('Startup promo saved');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _deleteStartupPromo(_AdminStartupPromoRow promo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete promo?'),
        content: Text('This removes "${promo.title}" permanently.'),
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
      await const StartupPromoService().adminDeletePromo(promo.id);
      if (!mounted) return;
      _showSnack('Promo deleted');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  void _previewStartupPromo(_AdminStartupPromoRow promo) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) =>
            _StartupPromoPreviewPage(promoRow: promo),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
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
                      Tab(icon: Text('ðŸ±'), text: 'Hungry Cat'),
                      Tab(icon: Text('ðŸš€'), text: 'Rocket Crash'),
                      Tab(icon: Text('ðŸŽ°'), text: 'Srood Draw'),
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





  // ═══════════════════════════════════════════════════════════════════════════
  // NEW SECTION BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── 1. Dashboard (enhanced overview) ─────────────────────────────────────
  Widget _buildDashboard() {
    final hasPending = _financeBadgeCount > 0 || _pendingReportsCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Command Center',
          subtitle: 'Live overview of users, rooms, finance, and platform health.',
          icon: Icons.dashboard_customize_rounded,
        ),
        const SizedBox(height: 14),

        // ── Quick Alerts Banner ─────────────────────────────────────────────
        if (hasPending)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kAmber.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notification_important_rounded, color: _kAmber, size: 18),
                    SizedBox(width: 8),
                    Text('Action Required', style: TextStyle(color: _kAmber, fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (_pendingRechargesCount > 0)
                      _AlertChip(
                        icon: Icons.add_card_rounded,
                        label: '$_pendingRechargesCount pending recharge${_pendingRechargesCount == 1 ? '' : 's'}',
                        color: _kAmber,
                        onTap: () => setState(() => _module = _AdminModule.finance),
                      ),
                    if (_pendingWithdrawalsCount > 0)
                      _AlertChip(
                        icon: Icons.currency_exchange_rounded,
                        label: '$_pendingWithdrawalsCount pending withdrawal${_pendingWithdrawalsCount == 1 ? '' : 's'}',
                        color: _kAmber,
                        onTap: () => setState(() => _module = _AdminModule.finance),
                      ),
                    if (_pendingReportsCount > 0)
                      _AlertChip(
                        icon: Icons.flag_rounded,
                        label: '$_pendingReportsCount pending report${_pendingReportsCount == 1 ? '' : 's'}',
                        color: _kRed,
                        onTap: () => setState(() => _module = _AdminModule.moderation),
                      ),
                  ],
                ),
              ],
            ),
          ),

        // ── KPI Grid ────────────────────────────────────────────────────────
        _OverviewGrid(overview: _overview),
        const SizedBox(height: 14),

        // ── Role + Quick navigation ─────────────────────────────────────────
        _ResponsivePair(
          left: _AdminSectionCard(
            title: 'Pending Recharges',
            action: TextButton.icon(
              onPressed: () => setState(() => _module = _AdminModule.finance),
              icon: const Icon(Icons.open_in_new_rounded, size: 14),
              label: const Text('View all'),
            ),
            child: _pending.isEmpty
                ? const _AdminEmptyState(
                    icon: Icons.verified_rounded,
                    title: 'No pending recharges',
                    subtitle: 'All recharge requests are handled.',
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
            title: 'My Role & Access',
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
                          ? 'Partner — high-level access. Cannot unban or manage admin roles.'
                          : _adminRole.isSuperAdmin
                              ? 'Operational Admin — manages users, rooms, reports, agencies, and challenges.'
                              : _adminRole.isAdmin
                                  ? 'Moderator — view reports, close rooms, temporarily ban users.'
                                  : 'No admin access.',
                  style: _mutedStyle,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DashQuickLink(icon: Icons.people_rounded,           label: 'Users',       onTap: () => setState(() => _module = _AdminModule.users)),
                    _DashQuickLink(icon: Icons.mic_external_on_rounded,  label: 'Rooms',       onTap: () => setState(() => _module = _AdminModule.rooms)),
                    _DashQuickLink(icon: Icons.account_balance_wallet_rounded, label: 'Finance', onTap: () => setState(() => _module = _AdminModule.finance)),
                    _DashQuickLink(icon: Icons.flag_rounded,             label: 'Reports',     onTap: () => setState(() => _module = _AdminModule.moderation)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 2. VIP Management ────────────────────────────────────────────────────
  Widget _buildVipManagement() {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = viewportHeight < 860 ? 680.0 : viewportHeight - 220.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'VIP Management',
          subtitle: 'Configure VIP packages, entrance banners, and preview the visual VIP system.',
          icon: Icons.workspace_premium_rounded,
          locked: !_canContent,
        ),
        const SizedBox(height: 14),

        // ── VIP Feature Matrix ──────────────────────────────────────────────
        const _VipFeatureMatrix(),
        const SizedBox(height: 14),

        // ── VIP Packages ────────────────────────────────────────────────────
        _AdminSectionCard(
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
                          title: 'VIP ${vip.vipLevel} — ${vip.name}',
                          subtitle:
                              '${_formatAdminCount(vip.priceCoins)} coins · ${vip.durationDays} days · banner: ${vip.entranceBannerKey ?? 'none'}',
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              _RoleChip(label: vip.isActive ? 'Active' : 'Inactive'),
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
        const SizedBox(height: 14),

        // ── Entrance Banners ────────────────────────────────────────────────
        _AdminSectionCard(
          title: 'Entrance Banners',
          child: _entranceBanners.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.auto_awesome_rounded,
                  title: 'No entrance banners',
                  subtitle: 'Entrance animations configured here.',
                )
              : Column(
                  children: _entranceBanners
                      .map(
                        (banner) => _AdminListTile(
                          icon: Icons.auto_awesome_rounded,
                          title: banner.name,
                          subtitle: '${banner.bannerKey} · Required VIP ${banner.vipLevel ?? '-'}',
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              _RoleChip(label: banner.isActive ? 'Active' : 'Inactive'),
                              if (_canContent)
                                TextButton(
                                  onPressed: () => _editEntranceBanner(banner),
                                  child: const Text('Edit'),
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),

        // ── VIP Visual Preview ──────────────────────────────────────────────
        _AdminSectionCard(
          title: 'VIP Visual Preview',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live preview of VIP 0–9 chat frames, mic waves, and entry banners.',
                style: _mutedStyle,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: panelHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: const VipVisualPreviewScreen(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 3. Gifts & Store ─────────────────────────────────────────────────────
  Widget _buildGiftsStore() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Gifts & Store',
          subtitle: 'Gift catalog, categories, avatar frames, and in-app economy.',
          icon: Icons.card_giftcard_rounded,
          locked: !_canContent,
        ),
        const SizedBox(height: 14),

        // ── Gift Categories ──────────────────────────────────────────────────
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
                        (cat) => _CatalogChip(
                          title: cat.name,
                          subtitle: cat.categoryKey,
                          active: cat.isActive,
                          onTap: _canContent ? () => _editGiftCategory(cat) : null,
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),

        // ── Avatar Frames ────────────────────────────────────────────────────
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
                          subtitle: '${frame.category} · ${frame.usageCount} users',
                          active: frame.isActive,
                          onTap: _canContent ? () => _editAvatarFrame(frame) : null,
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),

        // ── Gift Catalog ─────────────────────────────────────────────────────
        _AdminSectionCard(
          title: 'Gift Catalog',
          action: _canContent
              ? TextButton.icon(
                  onPressed: () => _editGift(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Gift'),
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

        // ── Recent Gift Transactions ─────────────────────────────────────────
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

  // ── 4. Agencies & Agents (was BD) ────────────────────────────────────────
  Widget _buildAgenciesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Agencies & Agents',
          subtitle: 'Manage recharge agencies, agents, and review sales performance.',
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
            onEditAgency: _canBd ? _editAgency : null,
          ),
          right: _AgentListCard(
            agents: _agents,
            canManage: _canBd,
            onCreateAgent: _createAgent,
            onToggleAgent: _toggleAgent,
          ),
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'BD Performance',
          child: _bdReport.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.query_stats_rounded,
                  title: 'No approved sales yet',
                  subtitle: 'Agency and agent performance will appear here once recharges are approved.',
                )
              : Column(children: _bdReport.map(_BdReportTile.new).toList()),
        ),
      ],
    );
  }

  // ── 5. Moderation (enhanced reports) ────────────────────────────────────
  Widget _buildModeration() {
    final statusFilters = [null, 'pending', 'reviewing', 'resolved', 'rejected', 'needs_more_info'];
    final filtered = _reportsStatusFilter == null
        ? _reports
        : _reports.where((r) => r.status == _reportsStatusFilter).toList();

    final pendingCount   = _reports.where((r) => r.status == 'pending').length;
    final reviewingCount = _reports.where((r) => r.status == 'reviewing').length;
    final resolvedCount  = _reports.where((r) => r.status == 'resolved').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ModuleTitle(
          title: 'Moderation & Reports',
          subtitle: 'Review user-submitted reports, take moderation actions, and track safety.',
          icon: Icons.shield_rounded,
        ),
        const SizedBox(height: 14),

        // ── Quick stats ──────────────────────────────────────────────────────
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 500 ? 3 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.0,
              children: [
                _AdminStatCard(label: 'Pending',   value: pendingCount,   icon: Icons.flag_rounded,         color: _kAmber),
                _AdminStatCard(label: 'Reviewing', value: reviewingCount, icon: Icons.search_rounded,       color: _kBlue),
                _AdminStatCard(label: 'Resolved',  value: resolvedCount,  icon: Icons.check_circle_rounded, color: _kGreen),
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        // ── Status filter chips ──────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: statusFilters.map((s) {
              final label = s == null
                  ? 'All'
                  : s == 'needs_more_info'
                      ? 'Needs Info'
                      : s[0].toUpperCase() + s.substring(1);
              final selected = _reportsStatusFilter == s;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _reportsStatusFilter = s);
                    _reloadReports();
                  },
                  backgroundColor: _kSurface,
                  selectedColor: _kGold.withValues(alpha: 0.2),
                  checkmarkColor: _kGold,
                  labelStyle: TextStyle(
                    color: selected ? _kGold : Colors.white54,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  side: BorderSide(color: selected ? _kGold : _kBorder, width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        _AdminSectionCard(
          title: 'Reports (${filtered.length})',
          action: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reloadReports,
            tooltip: 'Refresh',
          ),
          child: filtered.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.shield_outlined,
                  title: 'No reports in this category',
                  subtitle: 'User reports will appear here.',
                )
              : Column(
                  children: filtered
                      .map((r) => _ReportTile(
                            report: r,
                            onProcess: (status) => _processReport(r, status),
                            onAction: () => _showModerationActionDialog(
                              targetUserId: r.targetId,
                              targetName:   r.targetId,
                              reportId:     r.id,
                            ),
                          ))
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),

        // ── Auto-mod events ───────────────────────────────────────────────────
        _AdminSectionCard(
          title: 'Auto-Mod Events (${_modEvents.length})',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status filter
              DropdownButton<String?>(
                value: _modEventsStatusFilter,
                dropdownColor: _kSurface,
                underline: const SizedBox(),
                style: const TextStyle(color: _kTxt, fontSize: 12),
                items: const [
                  DropdownMenuItem(value: null,         child: Text('All')),
                  DropdownMenuItem(value: 'open',       child: Text('Open')),
                  DropdownMenuItem(value: 'reviewed',   child: Text('Reviewed')),
                  DropdownMenuItem(value: 'dismissed',  child: Text('Dismissed')),
                ],
                onChanged: (v) {
                  setState(() => _modEventsStatusFilter = v);
                  _reloadModEvents();
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _reloadModEvents,
                tooltip: 'Refresh',
              ),
            ],
          ),
          child: _modEventsLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: _kGold, strokeWidth: 2),
                  ),
                )
              : _modEvents.isEmpty
                  ? const _AdminEmptyState(
                      icon: Icons.smart_toy_outlined,
                      title: 'No auto-mod events',
                      subtitle: 'Events logged by text auto-moderation will appear here.',
                    )
                  : Column(
                      children: _modEvents
                          .map((e) => _ModEventTile(
                                event: e,
                                onAction: () => _showModerationActionDialog(
                                  targetUserId: e.userId,
                                  targetName:   e.userName,
                                  eventId:      e.id,
                                  roomId:       e.roomId,
                                ),
                              ))
                          .toList(),
                    ),
        ),
      ],
    );
  }

  // ── 6. Marketing & App Content ──────────────────────────────────────────
  Widget _buildMarketing() {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = viewportHeight < 860 ? 680.0 : viewportHeight - 220.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModuleTitle(
          title: 'Marketing & App Content',
          subtitle: 'Promo banners, carousel slides, and Charisma Challenge management.',
          icon: Icons.campaign_rounded,
          locked: !_canMarketing,
        ),
        const SizedBox(height: 14),

        // ── Promo Banners ────────────────────────────────────────────────────
        _AdminSectionCard(
          title: 'Promo Banners',
          action: _canMarketing
              ? TextButton.icon(
                  onPressed: () => _editPromoBanner(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Banner'),
                )
              : null,
          child: _promoBanners.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.view_carousel_rounded,
                  title: 'No promo banners',
                  subtitle: 'Add promotional carousel slides shown at the top of the Rooms screen.',
                )
              : Column(
                  children: _promoBanners
                      .map(
                        (b) => _AdminListTile(
                          icon: b.imageUrl != null && b.imageUrl!.isNotEmpty
                              ? Icons.image_rounded
                              : Icons.view_carousel_rounded,
                          title: b.imageUrl != null && b.imageUrl!.isNotEmpty
                              ? '[Image] ${b.targetRoute ?? b.slideKey}'
                              : (b.titleEn.isNotEmpty ? b.titleEn : b.slideKey),
                          subtitle:
                              '${b.slideKey} · order ${b.sortOrder}'
                              '${b.targetRoute != null ? ' → ${b.targetRoute}' : ''}',
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              _RoleChip(label: b.isActive ? 'Active' : 'Inactive'),
                              if (_canMarketing) ...[
                                TextButton(
                                  onPressed: () => _editPromoBanner(b),
                                  child: const Text('Edit'),
                                ),
                                TextButton(
                                  onPressed: () => _deletePromoBanner(b),
                                  style: TextButton.styleFrom(foregroundColor: _kRed),
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
        const SizedBox(height: 14),

        const SizedBox(height: 14),

        // ── Startup Promo ────────────────────────────────────────────────────
        _AdminSectionCard(
          title: 'Startup Promo',
          action: _canMarketing
              ? TextButton.icon(
                  onPressed: () => _editStartupPromo(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Promo'),
                )
              : null,
          child: _startupPromos.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.photo_size_select_actual_rounded,
                  title: 'No startup promos',
                  subtitle: 'Add a full-screen promo shown when the app opens.',
                )
              : Column(
                  children: _startupPromos
                      .map(
                        (p) => _AdminListTile(
                          icon: Icons.photo_size_select_actual_rounded,
                          title: p.title,
                          subtitle: '${p.frequency} · ${p.durationSeconds}s · priority ${p.priority}',
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              _RoleChip(label: p.isActive ? 'Active' : 'Inactive'),
                              if (p.imageUrl.isNotEmpty)
                                TextButton(
                                  onPressed: () => _previewStartupPromo(p),
                                  child: const Text('Preview'),
                                ),
                              if (_canMarketing) ...[
                                TextButton(
                                  onPressed: () => _editStartupPromo(p),
                                  child: const Text('Edit'),
                                ),
                                TextButton(
                                  onPressed: () => _deleteStartupPromo(p),
                                  style: TextButton.styleFrom(foregroundColor: _kRed),
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

        // ── Charisma Challenge ───────────────────────────────────────────────
        _AdminSectionCard(
          title: 'Charisma Challenge',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create, manage, and crown winners for live charisma challenges.',
                style: _mutedStyle,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: panelHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CharismaAdminPanel(isArabic: context.isArabic),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 7. System — Audit + Games ───────────────────────────────────────────
  Widget _buildSystem() {
    final logs = _auditLogs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ModuleTitle(
          title: 'System & Audit',
          subtitle: 'Admin activity logs, role changes, and game control panels.',
          icon: Icons.settings_rounded,
        ),
        const SizedBox(height: 14),

        // ── Audit Log ────────────────────────────────────────────────────────
        _AdminSectionCard(
          title: 'Audit Log Filters',
          action: TextButton.icon(
            onPressed: _resetAuditFilters,
            icon: const Icon(Icons.clear_rounded, size: 14),
            label: const Text('Reset'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: TextField(
                      style: const TextStyle(color: _kTxt, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Action type (e.g. ban_user)',
                        hintStyle: const TextStyle(color: _kMuted, fontSize: 12),
                        filled: true,
                        fillColor: _kBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kGold)),
                      ),
                      onChanged: (v) => setState(() => _auditFilterAction = v.trim().isEmpty ? null : v.trim()),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _auditFilterTargetType,
                      dropdownColor: _kSurface,
                      style: const TextStyle(color: _kTxt, fontSize: 12),
                      hint: const Text('Target type', style: TextStyle(color: _kMuted, fontSize: 12)),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _kBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All types')),
                        DropdownMenuItem(value: 'profiles', child: Text('Users')),
                        DropdownMenuItem(value: 'rooms', child: Text('Rooms')),
                        DropdownMenuItem(value: 'admin_user_restrictions', child: Text('Restrictions')),
                        DropdownMenuItem(value: 'recharge_agencies', child: Text('Agencies')),
                        DropdownMenuItem(value: 'user_reports', child: Text('Reports')),
                      ],
                      onChanged: (v) => setState(() => _auditFilterTargetType = v),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickAuditDate(isFrom: true),
                    icon: const Icon(Icons.calendar_today_rounded, size: 13),
                    label: Text(_auditFilterFrom == null ? 'From' : '${_auditFilterFrom!.month}/${_auditFilterFrom!.day}'),
                    style: OutlinedButton.styleFrom(foregroundColor: _kGold, side: const BorderSide(color: _kBorder), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), textStyle: const TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickAuditDate(isFrom: false),
                    icon: const Icon(Icons.calendar_today_rounded, size: 13),
                    label: Text(_auditFilterTo == null ? 'To' : '${_auditFilterTo!.month}/${_auditFilterTo!.day}'),
                    style: OutlinedButton.styleFrom(foregroundColor: _kGold, side: const BorderSide(color: _kBorder), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), textStyle: const TextStyle(fontSize: 12)),
                  ),
                  FilledButton.icon(
                    onPressed: _auditFiltering ? null : _searchAuditLogs,
                    icon: _auditFiltering
                        ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search_rounded, size: 14),
                    label: const Text('Search'),
                    style: FilledButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6)),
                  ),
                ],
              ),
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${logs.length} result${logs.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        _AdminSectionCard(
          title: 'Admin Action Log',
          child: logs.isEmpty
              ? const _AdminEmptyState(
                  icon: Icons.history_edu_rounded,
                  title: 'No audit logs',
                  subtitle: 'Try different filters, or clear filters to see all.',
                )
              : Column(children: logs.map(_AuditTile.new).toList()),
        ),
        const SizedBox(height: 14),

        // ── Game Controls ────────────────────────────────────────────────────
        if (_adminRole.hasPermission(kPermDrawManage))
          _buildGames()
        else
          const _AdminSectionCard(
            title: 'Game Controls',
            child: _AdminEmptyState(
              icon: Icons.sports_esports_rounded,
              title: 'Game controls not available',
              subtitle: 'P-Super Admin or higher is required to access game controls.',
            ),
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
      title: 'Finance Report â€” Today',
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
                                    label: isAccountBan ? 'ðŸ”’ banned' : 'active',
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

// â”€â”€ Image Upload Field â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€ Promo Banner Edit Dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PromoBannerEditDialog extends StatefulWidget {
  const _PromoBannerEditDialog({required this.adminService, this.existing});

  final AdminService adminService;
  final AdminPromoBanner? existing;

  @override
  State<_PromoBannerEditDialog> createState() => _PromoBannerEditDialogState();
}

class _PromoBannerEditDialogState extends State<_PromoBannerEditDialog> {
  late final TextEditingController _sortOrder;
  late final TextEditingController _targetRoute;
  // Fallback text/icon fields (only used when no image is uploaded).
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
  late bool _isActive;
  String? _imageUrl;
  bool _showFallbackFields = false;

  // Preserved from existing record so we don't accidentally null out the key.
  late final String _existingSlideKey;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _existingSlideKey = b?.slideKey ?? '';
    _sortOrder = TextEditingController(text: (b?.sortOrder ?? 0).toString());
    _targetRoute = TextEditingController(text: b?.targetRoute ?? '');
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
    _isActive = b?.isActive ?? true;
    _imageUrl = b?.imageUrl;
    // Auto-expand fallback section when editing a gradient banner.
    _showFallbackFields = _imageUrl == null || _imageUrl!.isEmpty;
  }

  @override
  void dispose() {
    _sortOrder.dispose();
    _targetRoute.dispose();
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
    super.dispose();
  }

  String? _ne(String v) => v.trim().isEmpty ? null : v.trim();

  // Generates a stable unique key from route + epoch so admins don't need to type one.
  String _deriveSlideKey() {
    if (_existingSlideKey.isNotEmpty) return _existingSlideKey;
    final route = _targetRoute.text.trim().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final suffix = DateTime.now().millisecondsSinceEpoch % 100000;
    return route.isNotEmpty ? '${route}_$suffix' : 'banner_$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageUrl != null && _imageUrl!.isNotEmpty;
    return _CatalogEditDialogShell(
      title: widget.existing == null ? 'New promo banner' : 'Edit promo banner',
      fields: [
        // ── Always-required fields ──────────────────────────────────────────
        _ImageUploadField(
          label: 'Banner image (upload replaces text layout)',
          initialUrl: _imageUrl,
          adminService: widget.adminService,
          onChanged: (url) => setState(() {
            _imageUrl = url;
            // Auto-collapse fallback fields when image is added.
            if (url != null && url.isNotEmpty) _showFallbackFields = false;
          }),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _targetRoute,
          decoration: const InputDecoration(
            labelText: 'Target route *',
            hintText: 'discovery / gifts / vip / rooms',
          ),
        ),
        TextField(
          controller: _sortOrder,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sort order'),
        ),
        SwitchListTile(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          title: const Text('Active'),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(height: 24),
        // ── Fallback text/icon fields (hidden when image is set) ────────────
        if (hasImage)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Image banner — text layout hidden.',
              style: TextStyle(color: Colors.green.shade300, fontSize: 12),
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _showFallbackFields = !_showFallbackFields),
          icon: Icon(_showFallbackFields ? Icons.expand_less : Icons.expand_more, size: 18),
          label: Text(
            _showFallbackFields
                ? 'Hide fallback text/icon fields'
                : 'Show fallback text/icon fields${hasImage ? ' (not used)' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          style: TextButton.styleFrom(foregroundColor: Colors.white54),
        ),
        if (_showFallbackFields) ...[
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
        ],
      ],
      onSave: () {
        // Require at minimum a target route.
        if (_targetRoute.text.trim().isEmpty) return;
        Navigator.of(context).pop(
          AdminPromoBanner(
            id: widget.existing?.id ?? '',
            slideKey: _deriveSlideKey(),
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
    required this.badges,
    required this.onSelected,
    this.onBrandTap,
  });

  final _AdminModule selected;
  final List<String> roles;
  final Map<_AdminModule, int> badges;
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
          // Brand header â€” tap 7Ã— quickly to open owner control panel
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
                      badge: badges[module] ?? 0,
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
    required this.badges,
    required this.onSelected,
  });

  final List<String> roles;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  final bool showTabs;
  final _AdminModule selected;
  final Map<_AdminModule, int> badges;
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
                  if ((badges[selected] ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    _StatusBadge(label: '${badges[selected]} pending'),
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
                  final hasBadge = (badges[module] ?? 0) > 0;
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
        // Fixed pixel height per cell â€” robust equivalent of an aspect
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
          '$user â€” ${request.diamondsAmount} ðŸ’Ž (\$${request.grossUsd.toStringAsFixed(2)} gross)',
      subtitle:
          '${request.method.toUpperCase()} Â· ${request.accountDetails} Â· $split',
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
    this.onEditAgency,
  });

  final List<AdminAgency> agencies;
  final bool canManage;
  final VoidCallback onCreateAgency;
  final ValueChanged<AdminAgency> onToggleAgency;
  final ValueChanged<AdminAgency>? onEditAgency;

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
                      subtitle: [
                        if (agency.country != null) agency.country!,
                        'Commission: ${(agency.commissionRate * 100).toStringAsFixed(1)}%',
                      ].join(' Â· '),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onEditAgency != null)
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 16, color: _kMuted),
                              onPressed: () => onEditAgency!(agency),
                              tooltip: 'Edit',
                            ),
                          Switch(
                            value: agency.isActive,
                            onChanged: canManage
                                ? (_) => onToggleAgency(agency)
                                : null,
                          ),
                        ],
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

/// Skeleton loading placeholder â€” shows 3 shimmering ghost tiles.
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

/// Semantic status badge â€” auto-picks color by label keyword.
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
    _AdminModule.dashboard  => Icons.dashboard_customize_rounded,
    _AdminModule.users      => Icons.manage_accounts_rounded,
    _AdminModule.rooms      => Icons.mic_external_on_rounded,
    _AdminModule.finance    => Icons.account_balance_wallet_rounded,
    _AdminModule.vip        => Icons.workspace_premium_rounded,
    _AdminModule.gifts      => Icons.card_giftcard_rounded,
    _AdminModule.agencies   => Icons.handshake_rounded,
    _AdminModule.moderation => Icons.shield_rounded,
    _AdminModule.marketing  => Icons.campaign_rounded,
    _AdminModule.system     => Icons.settings_rounded,
  };
}

String _moduleLabel(_AdminModule module) {
  return switch (module) {
    _AdminModule.dashboard  => 'Dashboard',
    _AdminModule.users      => 'Users',
    _AdminModule.rooms      => 'Rooms',
    _AdminModule.finance    => 'Finance',
    _AdminModule.vip        => 'VIP',
    _AdminModule.gifts      => 'Gifts & Store',
    _AdminModule.agencies   => 'Agencies',
    _AdminModule.moderation => 'Moderation',
    _AdminModule.marketing  => 'Marketing',
    _AdminModule.system     => 'System',
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

// â”€â”€ New helpers for Phase 2 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _QuickRangeButton extends StatelessWidget {
  const _QuickRangeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _kGold.withValues(alpha: 0.18) : _kBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kGold : _kBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kGold : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Withdrawal tab card (Pending + History) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WithdrawalTabCard extends StatelessWidget {
  const _WithdrawalTabCard({
    required this.pendingList,
    required this.historyList,
    required this.canFinance,
    required this.onApprove,
    required this.onReject,
    required this.onRefresh,
  });

  final List<AdminWithdrawalRequest> pendingList;
  final List<AdminWithdrawalRequest> historyList;
  final bool canFinance;
  final void Function(AdminWithdrawalRequest) onApprove;
  final void Function(AdminWithdrawalRequest) onReject;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Withdrawal Requests',
                      style: TextStyle(
                        color: _kTxt,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: _kMuted, size: 18),
                      onPressed: onRefresh,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TabBar(
                  indicatorColor: _kGold,
                  labelColor: _kGold,
                  unselectedLabelColor: _kMuted,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                  tabs: [
                    Tab(text: 'Pending (${pendingList.length})'),
                    Tab(text: 'History (${historyList.length})'),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  child: TabBarView(
                    children: [
                      // Pending tab
                      pendingList.isEmpty
                          ? const _AdminEmptyState(
                              icon: Icons.verified_rounded,
                              title: 'All clear',
                              subtitle: 'No pending withdrawal requests.',
                            )
                          : ListView(
                              children: pendingList
                                  .map((w) => _WithdrawalRequestTile(
                                        request: w,
                                        canFinance: canFinance,
                                        onApprove: () => onApprove(w),
                                        onReject: () => onReject(w),
                                      ))
                                  .toList(),
                            ),
                      // History tab
                      historyList.isEmpty
                          ? const _AdminEmptyState(
                              icon: Icons.history_rounded,
                              title: 'No history',
                              subtitle: 'Approved and rejected withdrawals appear here.',
                            )
                          : ListView(
                              children: historyList
                                  .map((w) => _WithdrawalHistoryTile(request: w))
                                  .toList(),
                            ),
                    ],
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

class _WithdrawalHistoryTile extends StatelessWidget {
  const _WithdrawalHistoryTile({required this.request});
  final AdminWithdrawalRequest request;

  @override
  Widget build(BuildContext context) {
    final isApproved = request.status == 'approved';
    final statusColor = isApproved ? Colors.greenAccent : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.displayName ?? request.userId,
                  style: const TextStyle(
                      color: _kTxt, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${request.diamondsAmount} diamonds Â· ${request.status.toUpperCase()}',
                  style: TextStyle(color: statusColor, fontSize: 11),
                ),
              ],
            ),
          ),
          if (request.createdAt != null)
            Text(
              _fmtDate(request.createdAt!),
              style: const TextStyle(color: _kMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';
}

// â”€â”€ Agency edit dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AgencyEditResult {
  const _AgencyEditResult({
    required this.name,
    required this.whatsapp,
    required this.country,
    this.commissionRate,
  });
  final String name;
  final String whatsapp;
  final String country;
  final double? commissionRate;
}

class _AgencyEditDialog extends StatefulWidget {
  const _AgencyEditDialog({
    required this.agency,
    required this.canEditCommission,
  });
  final AdminAgency agency;
  final bool canEditCommission;

  @override
  State<_AgencyEditDialog> createState() => _AgencyEditDialogState();
}

class _AgencyEditDialogState extends State<_AgencyEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _whatsapp;
  late final TextEditingController _country;
  late final TextEditingController _commission;

  @override
  void initState() {
    super.initState();
    _name       = TextEditingController(text: widget.agency.name);
    _whatsapp   = TextEditingController(text: widget.agency.whatsapp ?? '');
    _country    = TextEditingController(text: widget.agency.country ?? '');
    _commission = TextEditingController(
        text: (widget.agency.commissionRate * 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _name.dispose();
    _whatsapp.dispose();
    _country.dispose();
    _commission.dispose();
    super.dispose();
  }

  void _submit() {
    double? rate;
    if (widget.canEditCommission && _commission.text.trim().isNotEmpty) {
      final pct = double.tryParse(_commission.text.trim());
      if (pct == null || pct < 0 || pct > 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Commission must be 0â€“100')));
        return;
      }
      rate = pct / 100;
    }
    Navigator.of(context).pop(_AgencyEditResult(
      name: _name.text,
      whatsapp: _whatsapp.text,
      country: _country.text,
      commissionRate: rate,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _kSurface,
      title: const Text('Edit Agency',
          style: TextStyle(color: _kTxt, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_name, 'Name'),
            const SizedBox(height: 12),
            _field(_whatsapp, 'WhatsApp'),
            const SizedBox(height: 12),
            _field(_country, 'Country'),
            if (widget.canEditCommission) ...[
              const SizedBox(height: 12),
              _field(_commission, 'Commission % (0â€“100)',
                  type: TextInputType.number),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: _kMuted)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: c,
      keyboardType: type,
      style: const TextStyle(color: _kTxt, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kMuted, fontSize: 13),
        filled: true,
        fillColor: _kBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kGold)),
      ),
    );
  }
}

// â”€â”€ Report tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ReportTile extends StatefulWidget {
  const _ReportTile({
    required this.report,
    required this.onProcess,
    this.onAction,
  });
  final AdminReport report;
  final void Function(String status) onProcess;
  final VoidCallback? onAction;

  @override
  State<_ReportTile> createState() => _ReportTileState();
}

class _ReportTileState extends State<_ReportTile> {
  final _adminService = const AdminService();
  List<ModerationEvidence>? _evidence;
  bool _evidenceExpanded = false;
  bool _evidenceLoading = false;

  Future<void> _loadEvidence() async {
    if (_evidence != null) {
      setState(() => _evidenceExpanded = !_evidenceExpanded);
      return;
    }
    setState(() { _evidenceLoading = true; _evidenceExpanded = true; });
    try {
      final rows = await _adminService.fetchReportEvidence(widget.report.id);
      if (mounted) setState(() { _evidence = rows; _evidenceLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _evidence = const []; _evidenceLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final statusColor = switch (report.status) {
      'pending'         => Colors.orangeAccent,
      'reviewing'       => Colors.blueAccent,
      'resolved'        => Colors.greenAccent,
      'rejected'        => Colors.redAccent,
      'needs_more_info' => Colors.purpleAccent,
      _                 => _kMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ───────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  report.status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  report.targetType,
                  style: const TextStyle(color: _kMuted, fontSize: 10),
                ),
              ),
              const Spacer(),
              if (report.createdAt != null)
                Text(
                  '${report.createdAt!.month}/${report.createdAt!.day}/${report.createdAt!.year}',
                  style: const TextStyle(color: _kMuted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Report reason & details ───────────────────────────────────────────
          Text(
            report.reason,
            style: const TextStyle(color: _kTxt, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (report.details != null) ...[
            const SizedBox(height: 4),
            Text(report.details!, style: const TextStyle(color: _kMuted, fontSize: 12)),
          ],
          const SizedBox(height: 4),
          Text(
            'Reporter: ${report.reporterName ?? report.reporterId}',
            style: const TextStyle(color: _kMuted, fontSize: 11),
          ),
          Text(
            'Reported: ${report.targetId}',
            style: const TextStyle(color: _kMuted, fontSize: 11),
          ),

          // ── Evidence toggle ───────────────────────────────────────────────────
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _loadEvidence,
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, size: 13, color: _kBlue),
                const SizedBox(width: 6),
                Text(
                  _evidenceExpanded ? 'Hide Evidence Snapshot' : 'Show Evidence Snapshot',
                  style: const TextStyle(color: _kBlue, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                Icon(
                  _evidenceExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 14,
                  color: _kBlue,
                ),
              ],
            ),
          ),

          if (_evidenceExpanded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: _evidenceLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue),
                        ),
                      ),
                    )
                  : _evidence == null || _evidence!.isEmpty
                      ? const Text(
                          'No chat evidence captured.',
                          style: TextStyle(color: _kMuted, fontSize: 12),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shield_outlined, size: 12, color: _kMuted),
                                const SizedBox(width: 4),
                                Text(
                                  'Evidence Snapshot — ${_evidence!.length} message${_evidence!.length == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    color: _kMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_evidence!.isNotEmpty && _evidence!.first.roomId != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    'Room: ${_evidence!.first.roomId!.substring(0, 8)}…',
                                    style: const TextStyle(color: _kMuted, fontSize: 10),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._evidence!.map((e) => _EvidenceMessageRow(evidence: e)),
                          ],
                        ),
            ),
          ],

          // ── Action buttons ────────────────────────────────────────────────────
          if (report.isPending || report.status == 'reviewing') ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                if (report.isPending)
                  _ReportActionButton(
                    label: 'Reviewing',
                    color: Colors.blueAccent,
                    onTap: () => widget.onProcess('reviewing'),
                  ),
                _ReportActionButton(
                  label: 'Resolve',
                  color: Colors.greenAccent,
                  onTap: () => widget.onProcess('resolved'),
                ),
                _ReportActionButton(
                  label: 'Reject',
                  color: Colors.redAccent,
                  onTap: () => widget.onProcess('rejected'),
                ),
                _ReportActionButton(
                  label: 'Needs Info',
                  color: Colors.purpleAccent,
                  onTap: () => widget.onProcess('needs_more_info'),
                ),
                if (widget.onAction != null)
                  _ReportActionButton(
                    label: 'Take Action',
                    color: _kAmber,
                    onTap: widget.onAction!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceMessageRow extends StatelessWidget {
  const _EvidenceMessageRow({required this.evidence});
  final ModerationEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final isReported = evidence.isReportedUser;
    final senderName = evidence.senderDisplayName ?? evidence.senderId?.substring(0, 8) ?? '?';
    final timeStr = evidence.messageCreatedAt != null
        ? '${evidence.messageCreatedAt!.hour.toString().padLeft(2, '0')}:'
          '${evidence.messageCreatedAt!.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isReported
            ? const Color(0xFF7F1D1D).withValues(alpha: 0.35)
            : const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isReported
              ? const Color(0xFFEF4444).withValues(alpha: 0.45)
              : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isReported)
            const Padding(
              padding: EdgeInsets.only(right: 6, top: 1),
              child: Icon(Icons.flag_rounded, size: 11, color: Color(0xFFEF4444)),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        color: isReported ? const Color(0xFFFCA5A5) : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(timeStr, style: const TextStyle(color: _kMuted, fontSize: 10)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  evidence.messageText ?? '',
                  style: TextStyle(
                    color: isReported ? const Color(0xFFFECACA) : _kTxt,
                    fontSize: 12,
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

class _ReportActionButton extends StatelessWidget {
  const _ReportActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}


// ── Alert chip for dashboard quick alerts panel ──────────────────────────────
class _AlertChip extends StatelessWidget {
  const _AlertChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios_rounded, size: 10, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

// ── Quick navigation chip on dashboard ──────────────────────────────────────
class _DashQuickLink extends StatelessWidget {
  const _DashQuickLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _kNavActive,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _kGold),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: _kTxt, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── VIP Feature Matrix ───────────────────────────────────────────────────────
class _VipFeatureMatrix extends StatelessWidget {
  const _VipFeatureMatrix();

  static const _features = [
    _VipFeature('Send images in room chat',   minLevel: 7),
    _VipFeature('Gold entrance banner',       minLevel: 5),
    _VipFeature('Diamond entrance banner',    minLevel: 7),
    _VipFeature('Exclusive avatar frame',     minLevel: 3),
    _VipFeature('Premium chat frame',         minLevel: 2),
    _VipFeature('Mic wave animation',         minLevel: 4),
    _VipFeature('Room creation (any type)',   minLevel: 1),
    _VipFeature('VIP badge on profile',       minLevel: 1),
    _VipFeature('Priority room mic seat',     minLevel: 6),
    _VipFeature('Owner game controls',        minLevel: 9),
  ];

  @override
  Widget build(BuildContext context) {
    return _AdminSectionCard(
      title: 'VIP Feature Access Matrix',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Which features unlock at each VIP level. Users at or above the required level have access.',
            style: _mutedStyle,
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: _kBorder, width: 0.5),
              children: [
                // Header row
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFF1A2040)),
                  children: [
                    _MatrixCell('Feature', isHeader: true),
                    for (int vip = 1; vip <= 9; vip++)
                      _MatrixCell('VIP $vip', isHeader: true),
                  ],
                ),
                // Feature rows
                for (final feature in _features)
                  TableRow(
                    children: [
                      _MatrixCell(feature.name),
                      for (int vip = 1; vip <= 9; vip++)
                        _MatrixCheckCell(unlocked: vip >= feature.minLevel),
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

class _VipFeature {
  const _VipFeature(this.name, {required this.minLevel});
  final String name;
  final int minLevel;
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell(this.text, {this.isHeader = false});
  final String text;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          color: isHeader ? _kGold : _kTxt,
          fontSize: isHeader ? 11 : 12,
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _MatrixCheckCell extends StatelessWidget {
  const _MatrixCheckCell({required this.unlocked});
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: Icon(
          unlocked ? Icons.check_circle_rounded : Icons.remove_rounded,
          size: 16,
          color: unlocked ? _kGreen : _kBorder,
        ),
      ),
    );
  }
}

// ── Simple labeled dropdown for dialog use (avoids deprecated FormField.value) ─

class _DialogDropdown<T> extends StatelessWidget {
  const _DialogDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _kMuted, fontSize: 12)),
        const SizedBox(height: 4),
        DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: _kSurface,
          style: const TextStyle(color: _kTxt, fontSize: 14),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ── Auto-mod event model ─────────────────────────────────────────────────────

class _ModEvent {
  const _ModEvent({
    required this.id,
    required this.userId,
    required this.userName,
    required this.roomId,
    required this.source,
    required this.violationType,
    required this.severity,
    required this.originalText,
    required this.matchedRule,
    required this.actionTaken,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String? roomId;
  final String source;
  final String violationType;
  final int severity;
  final String? originalText;
  final String? matchedRule;
  final String? actionTaken;
  final String status;
  final DateTime createdAt;

  factory _ModEvent.fromJson(Map<String, dynamic> j) => _ModEvent(
    id:            j['id'] as String,
    userId:        j['user_id'] as String,
    userName:      j['user_name'] as String? ?? 'Unknown',
    roomId:        j['room_id'] as String?,
    source:        j['source'] as String? ?? 'chat',
    violationType: j['violation_type'] as String? ?? 'other',
    severity:      (j['severity'] as num?)?.toInt() ?? 1,
    originalText:  j['original_text'] as String?,
    matchedRule:   j['matched_rule'] as String?,
    actionTaken:   j['action_taken'] as String?,
    status:        j['status'] as String? ?? 'open',
    createdAt:     j['created_at'] != null
        ? DateTime.parse(j['created_at'] as String)
        : DateTime.now(),
  );
}

// ── Auto-mod event tile ───────────────────────────────────────────────────────

class _ModEventTile extends StatelessWidget {
  const _ModEventTile({required this.event, required this.onAction});
  final _ModEvent event;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (event.severity) {
      1 => _kAmber,
      2 => Colors.orangeAccent,
      3 => _kRed,
      _ => const Color(0xFFDC2626),
    };
    final statusColor = switch (event.status) {
      'open'      => _kAmber,
      'reviewed'  => _kGreen,
      'dismissed' => _kMuted,
      _           => _kMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: event.status == 'open'
              ? severityColor.withValues(alpha: 0.3)
              : _kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: severityColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'S${event.severity} · ${event.violationType.replaceAll('_', ' ')}',
                  style: TextStyle(
                      color: severityColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  event.status.toUpperCase(),
                  style: TextStyle(
                      color: statusColor, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Text(
                '${event.createdAt.month}/${event.createdAt.day}'
                ' ${event.createdAt.hour.toString().padLeft(2, '0')}'
                ':${event.createdAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: _kMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'User: ${event.userName}',
            style: const TextStyle(
                color: _kTxt, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (event.originalText != null) ...[
            const SizedBox(height: 4),
            Text(
              '"${event.originalText}"',
              style: const TextStyle(
                  color: _kMuted, fontSize: 12, fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (event.matchedRule != null) ...[
            const SizedBox(height: 2),
            Text(
              'Matched: ${event.matchedRule}',
              style: const TextStyle(color: _kMuted, fontSize: 11),
            ),
          ],
          if (event.status == 'open') ...[
            const SizedBox(height: 10),
            _ReportActionButton(
              label: 'Take Action',
              color: _kAmber,
              onTap: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Startup Promo — local data row ────────────────────────────────────────────

class _AdminStartupPromoRow {
  const _AdminStartupPromoRow({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.isActive,
    this.startsAt,
    this.endsAt,
    required this.durationSeconds,
    required this.frequency,
    required this.priority,
  });

  final String id;
  final String title;
  final String imageUrl;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int durationSeconds;
  final String frequency;
  final int priority;

  factory _AdminStartupPromoRow.fromModel(AdminStartupPromo m) {
    return _AdminStartupPromoRow(
      id: m.id,
      title: m.title,
      imageUrl: m.imageUrl,
      isActive: m.isActive,
      startsAt: m.startsAt,
      endsAt: m.endsAt,
      durationSeconds: m.durationSeconds,
      frequency: m.frequency,
      priority: m.priority,
    );
  }
}

// ── Startup Promo — Edit Dialog ───────────────────────────────────────────────

class _StartupPromoEditDialog extends StatefulWidget {
  const _StartupPromoEditDialog({
    required this.adminService,
    this.existing,
  });

  final AdminService adminService;
  final _AdminStartupPromoRow? existing;

  @override
  State<_StartupPromoEditDialog> createState() =>
      _StartupPromoEditDialogState();
}

class _StartupPromoEditDialogState extends State<_StartupPromoEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _imageUrlCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _priorityCtrl;
  late bool _isActive;
  late String _frequency;
  bool _uploading = false;
  String? _uploadError;

  static const _frequencies = [
    ('once_per_day',    'Once per day'),
    ('every_open',      'Every open'),
    ('once_per_session','Once per session'),
    ('once_only',       'Once only'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl    = TextEditingController(text: e?.title ?? '');
    _imageUrlCtrl = TextEditingController(text: e?.imageUrl ?? '');
    _durationCtrl = TextEditingController(
        text: (e?.durationSeconds ?? 5).toString());
    _priorityCtrl = TextEditingController(
        text: (e?.priority ?? 0).toString());
    _isActive  = e?.isActive ?? false;
    _frequency = e?.frequency ?? 'once_per_day';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _imageUrlCtrl.dispose();
    _durationCtrl.dispose();
    _priorityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    final ext   = picked.name.split('.').last.toLowerCase();

    if (bytes.length > 2 * 1024 * 1024) {
      setState(() =>
          _uploadError = 'File too large (max 2MB). Use compressed WebP.');
      return;
    }
    if (!['webp', 'jpg', 'jpeg', 'png'].contains(ext)) {
      setState(() =>
          _uploadError = 'Unsupported format. Use WebP, JPG, or PNG.');
      return;
    }

    setState(() { _uploading = true; _uploadError = null; });

    try {
      final contentType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';

      String url;
      try {
        url = await const StartupPromoService().uploadPromoImage(
          bytes: bytes,
          filename: picked.name,
          contentType: contentType,
        );
      } catch (_) {
        url = await widget.adminService.uploadAdminAsset(
          bytes: bytes,
          filename: picked.name,
          contentType: contentType,
        );
      }

      if (!mounted) return;
      _imageUrlCtrl.text = url;
      final sizeKb = bytes.length ~/ 1024;
      setState(() {
        _uploadError = sizeKb > 700
            ? 'Uploaded (${sizeKb}KB). Consider compressing below 700KB.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadError = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  bool get _canSave =>
      _titleCtrl.text.trim().isNotEmpty &&
      _imageUrlCtrl.text.trim().isNotEmpty &&
      !_uploading;

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kMuted, fontSize: 12),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _kBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _kGold),
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  void _save() {
    final duration = int.tryParse(_durationCtrl.text.trim()) ?? 5;
    if (duration < 3 || duration > 10) {
      setState(() =>
          _uploadError = 'Duration must be between 3 and 10 seconds.');
      return;
    }
    Navigator.of(context).pop(
      _AdminStartupPromoRow(
        id: widget.existing?.id ?? '',
        title: _titleCtrl.text.trim(),
        imageUrl: _imageUrlCtrl.text.trim(),
        isActive: _isActive,
        durationSeconds: duration,
        frequency: _frequency,
        priority: int.tryParse(_priorityCtrl.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _imageUrlCtrl.text.trim();
    final isNew = widget.existing == null;

    return AlertDialog(
      backgroundColor: _kSurface,
      title: Text(
        isNew ? 'New Startup Promo' : 'Edit Startup Promo',
        style: const TextStyle(
            color: _kTxt, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Spec hint
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _kGold.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Recommended: 1080×1920 px, 9:16 ratio, WebP preferred, under 700KB\n'
                  'Safe zones: top 160px and bottom 180px reserved.\n'
                  'Maximum file size: 2MB.',
                  style: TextStyle(
                      color: _kGold, fontSize: 11, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: _kTxt),
                decoration: _inputDeco('Title *'),
              ),
              const SizedBox(height: 10),

              // Image URL + upload button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _imageUrlCtrl,
                      style: const TextStyle(color: _kTxt, fontSize: 12),
                      decoration: _inputDeco('Image URL *'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_uploading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kGold),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.upload_rounded, color: _kGold),
                      tooltip: 'Pick & upload image',
                      onPressed: _pickAndUpload,
                    ),
                ],
              ),

              if (_uploadError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _uploadError!,
                  style: TextStyle(
                    color: _uploadError!.contains('Uploaded')
                        ? _kAmber
                        : _kRed,
                    fontSize: 11,
                  ),
                ),
              ],

              if (previewUrl.startsWith('http')) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    previewUrl,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 140,
                      color: const Color(0xFF1E2435),
                      child: const Center(
                        child: Icon(Icons.broken_image_rounded,
                            color: _kMuted),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),

              TextField(
                controller: _durationCtrl,
                style: const TextStyle(color: _kTxt),
                keyboardType: TextInputType.number,
                decoration: _inputDeco('Duration seconds (3–10)'),
              ),
              const SizedBox(height: 10),

              DropdownButton<String>(
                value: _frequency,
                dropdownColor: _kSurface,
                style: const TextStyle(color: _kTxt),
                isExpanded: true,
                items: _frequencies
                    .map((f) => DropdownMenuItem(
                          value: f.$1,
                          child: Text(f.$2),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _frequency = v);
                },
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _priorityCtrl,
                style: const TextStyle(color: _kTxt),
                keyboardType: TextInputType.number,
                decoration:
                    _inputDeco('Priority (higher = shown first)'),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Switch(
                    value: _isActive,
                    activeThumbColor: _kGreen,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isActive
                        ? 'Active — visible to users'
                        : 'Inactive',
                    style: TextStyle(
                      color: _isActive ? _kGreen : _kMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
          style: FilledButton.styleFrom(
              backgroundColor: _kGold, foregroundColor: _kBg),
          onPressed: _canSave ? _save : null,
          child: Text(isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

// ── Startup Promo — Admin Preview ─────────────────────────────────────────────

class _StartupPromoPreviewPage extends StatefulWidget {
  const _StartupPromoPreviewPage({required this.promoRow});

  final _AdminStartupPromoRow promoRow;

  @override
  State<_StartupPromoPreviewPage> createState() =>
      _StartupPromoPreviewPageState();
}

class _StartupPromoPreviewPageState
    extends State<_StartupPromoPreviewPage> {
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.promoRow.durationSeconds.clamp(3, 10);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.promoRow.imageUrl;

    return Scaffold(
      backgroundColor: const Color(0xFF08060F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (url.startsWith('http'))
            Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: Color(0xFF12061F)),
            )
          else
            const ColoredBox(color: Color(0xFF12061F)),

          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.2, 0.75, 1.0],
                ),
              ),
            ),
          ),

          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'ADMIN PREVIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      'Skip ${_remaining}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
