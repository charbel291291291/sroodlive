import 'package:flutter/material.dart';

import '../../../shared/branding/branding_assets.dart';
import '../models/admin_models.dart';
import '../services/admin_access_service.dart';
import '../services/admin_service.dart';

enum _AdminModule { overview, finance, users, bd, content, rooms, audit }

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

  _AdminModule _module = _AdminModule.overview;
  bool _isLoading = true;
  bool _canAccess = false;
  List<String> _roles = const [];
  String? _error;

  AdminOverview? _overview;
  List<AdminRechargeRequest> _pending = const [];
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
  AdminWalletSummary? _walletLookup;

  bool get _isSuper => _roles.contains('super_admin');
  bool get _canFinance => _isSuper || _roles.contains('finance_admin');
  bool get _canBd => _isSuper || _roles.contains('bd_admin');
  bool get _canContent => _isSuper || _roles.contains('content_admin');
  bool get _canRooms =>
      _isSuper || _roles.contains('room_admin') || _roles.contains('moderator');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _walletLookupController.dispose();
    _userSearchController.dispose();
    _coinsController.dispose();
    _diamondsController.dispose();
    _noteController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final roles = await _accessService.fetchCurrentUserRoles();
      final canAccess = roles.any(
        (role) => AdminRoleSpec.all.any((spec) => spec.role == role),
      );

      if (!canAccess) {
        if (!mounted) return;
        setState(() {
          _roles = roles;
          _canAccess = false;
          _isLoading = false;
        });
        return;
      }

      final overview = await _adminService.fetchOverview();
      final pending = await _adminService.fetchRechargeRequests(
        status: 'pending',
      );
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

      if (!mounted) return;
      setState(() {
        _roles = roles;
        _canAccess = true;
        _overview = overview;
        _pending = pending;
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
    try {
      await _adminService.approveRecharge(request.id);
      if (!mounted) return;
      _showSnack('Recharge approved');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Approval failed: $error');
    }
  }

  Future<void> _reject(AdminRechargeRequest request) async {
    final reason = await _askForText(title: 'Reject recharge', label: 'Reason');
    if (reason == null || reason.trim().isEmpty) return;

    try {
      await _adminService.rejectRecharge(request.id, reason.trim());
      if (!mounted) return;
      _showSnack('Recharge rejected');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Rejection failed: $error');
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
    final wallet = _walletLookup;
    if (wallet == null || !_canFinance) return;

    final coins = int.tryParse(_coinsController.text.trim()) ?? 0;
    final diamonds = int.tryParse(_diamondsController.text.trim()) ?? 0;
    final note = _noteController.text.trim();

    if (coins == 0 && diamonds == 0) {
      _showSnack('Enter a coins or diamonds delta');
      return;
    }

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
      backgroundColor: const Color(0xFF12091D),
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          shrinkWrap: true,
          children: [
            const Text(
              'Assign role',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            ...AdminRoleSpec.all.map(
              (spec) => ListTile(
                enabled: !user.roles.contains(spec.role),
                leading: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFFF0C15A),
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
        backgroundColor: const Color(0xFF09040F),
        builder: (context) => _UserDetailSheet(
          detail: detail,
          ledger: ledger,
          recharges: recharges,
          gifts: gifts,
          canSupport: _isSuper || _roles.contains('support_admin'),
          canModerate: _isSuper || _canRooms,
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
      _showSnack('Restriction failed: $error');
    }
  }

  Future<void> _grantVip(AdminUserDetail detail) async {
    final levelText = await _askForText(
      title: 'Grant VIP',
      label: 'VIP level 0-10',
    );
    if (levelText == null) return;
    final daysText = await _askForText(title: 'Grant VIP', label: 'Days');
    if (daysText == null) return;
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
        backgroundColor: const Color(0xFF140820),
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
        backgroundColor: const Color(0xFF140820),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07030D),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : !_canAccess
            ? _adminService.currentEmail == null
                  ? _AdminLoginPanel(
                      emailController: _adminEmailController,
                      passwordController: _adminPasswordController,
                      onLogin: _adminLogin,
                    )
                  : const _AdminShellMessage(
                      icon: Icons.lock_rounded,
                      title: 'Not authorized',
                      subtitle: 'This dashboard is only for admin roles.',
                    )
            : _error != null
            ? _AdminShellMessage(
                icon: Icons.error_outline_rounded,
                title: 'Could not load dashboard',
                subtitle: _error!,
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
                          onSelected: (module) =>
                              setState(() => _module = module),
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
                              onSelected: (module) =>
                                  setState(() => _module = module),
                            ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _load,
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    12,
                                    18,
                                    36,
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
      _AdminModule.audit => _buildAudit(),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _roles
                      .map((role) => _RoleChip(label: role))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Super Admin controls roles and all modules. Finance, BD, Content, Room, Support, and Viewer roles are scoped.',
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
          subtitle: 'Search users and manage admin access.',
          icon: Icons.manage_accounts_rounded,
          locked: !_isSuper,
        ),
        const SizedBox(height: 14),
        _AdminSectionCard(
          title: 'User Search',
          action: _isSuper ? const _RoleChip(label: 'super only') : null,
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
                          canManageRoles: _isSuper,
                          onOpen: () => _openUserDetail(user),
                          onAssign: () => _assignRole(user),
                          onRemoveRole: (role) => _removeRole(user, role),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _AdminCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AdminBrand(),
              const SizedBox(height: 22),
              Text('Admin Login', style: _titleStyle.copyWith(fontSize: 28)),
              const SizedBox(height: 6),
              Text(
                'Sign in with an account that has an admin role.',
                style: _mutedStyle,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                onSubmitted: (_) => onLogin(),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Enter Admin'),
              ),
            ],
          ),
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

    final stats = [
      ('Approved', item.approvedRecharges, Icons.verified_rounded),
      ('Rejected', item.rejectedRecharges, Icons.cancel_rounded),
      ('Pending', item.pendingRecharges, Icons.pending_actions_rounded),
      ('Coins', item.coinsCharged, Icons.monetization_on_rounded),
      ('Gift spend', item.giftCoinsSpent, Icons.card_giftcard_rounded),
      ('Adjustments', item.manualAdjustmentCount, Icons.tune_rounded),
    ];

    return _AdminSectionCard(
      title: 'Finance Report Today',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: stats
            .map(
              (stat) => SizedBox(
                width: 150,
                child: _AdminStatCard(
                  label: stat.$1,
                  value: stat.$2,
                  icon: stat.$3,
                ),
              ),
            )
            .toList(),
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
                        (item) => _AdminListTile(
                          icon: Icons.block_rounded,
                          title: item.type,
                          subtitle: item.reason ?? _dateLabel(item.createdAt),
                          trailing: canModerate
                              ? TextButton(
                                  onPressed: () =>
                                      onRestriction(item.type, false),
                                  child: const Text('Remove'),
                                )
                              : const _RoleChip(label: 'active'),
                        ),
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
      backgroundColor: const Color(0xFF140820),
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
      backgroundColor: const Color(0xFF140820),
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
  late final TextEditingController _assetUrl;
  late final TextEditingController _gradientStart;
  late final TextEditingController _gradientEnd;
  late final TextEditingController _message;
  late final TextEditingController _sortOrder;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final banner = widget.banner;
    _key = TextEditingController(text: banner.bannerKey);
    _name = TextEditingController(text: banner.name);
    _arabicName = TextEditingController(text: banner.arabicName);
    _vipLevel = TextEditingController(text: banner.vipLevel?.toString());
    _assetUrl = TextEditingController(text: banner.assetUrl);
    _gradientStart = TextEditingController(text: banner.gradientStart);
    _gradientEnd = TextEditingController(text: banner.gradientEnd);
    _message = TextEditingController(text: banner.messageTemplate);
    _sortOrder = TextEditingController(text: banner.sortOrder.toString());
    _isActive = banner.isActive;
  }

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _arabicName.dispose();
    _vipLevel.dispose();
    _assetUrl.dispose();
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
        TextField(
          controller: _assetUrl,
          decoration: const InputDecoration(labelText: 'Asset URL'),
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
            assetUrl: _nullIfEmpty(_assetUrl.text),
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
  late final TextEditingController _assetUrl;
  late final TextEditingController _sortOrder;
  late bool _isActive;
  late bool _isFeatured;

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
    _assetUrl = TextEditingController(text: frame.assetUrl);
    _sortOrder = TextEditingController(text: frame.sortOrder.toString());
    _isActive = frame.isActive;
    _isFeatured = frame.isFeatured;
  }

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _category.dispose();
    _vipLevel.dispose();
    _requiredVipLevel.dispose();
    _assetUrl.dispose();
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
        TextField(
          controller: _assetUrl,
          decoration: const InputDecoration(labelText: 'Asset URL'),
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
            assetUrl: _nullIfEmpty(_assetUrl.text),
            isActive: _isActive,
            isFeatured: _isFeatured,
            sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
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
      backgroundColor: const Color(0xFF140820),
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
    required this.onSelected,
  });

  final _AdminModule selected;
  final List<String> roles;
  final ValueChanged<_AdminModule> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 252,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0614),
        border: Border(right: BorderSide(color: Color(0xFF35204F))),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 10),
          const _AdminBrand(),
          const SizedBox(height: 24),
          ..._AdminModule.values.map(
            (module) => _NavItem(
              module: module,
              selected: selected == module,
              onTap: () => onSelected(module),
            ),
          ),
          const SizedBox(height: 18),
          Text('Current roles', style: _mutedStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: roles.isEmpty
                ? const [_RoleChip(label: 'no role')]
                : roles.map((role) => _RoleChip(label: role)).toList(),
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
    required this.onSelected,
  });

  final List<String> roles;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  final bool showTabs;
  final _AdminModule selected;
  final ValueChanged<_AdminModule> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF09040F),
        border: Border(bottom: BorderSide(color: Color(0xFF35204F))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (showTabs) const _AdminBrand(compact: true),
              if (!showTabs)
                Text(
                  'Admin Console',
                  style: _titleStyle.copyWith(fontSize: 22),
                ),
              const Spacer(),
              _RoleChip(label: roles.isEmpty ? 'no role' : roles.first),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFF0C15A),
                ),
              ),
              IconButton(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded, color: Colors.white70),
              ),
            ],
          ),
          if (showTabs) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _AdminModule.values
                    .map(
                      (module) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: selected == module,
                          label: Text(_moduleLabel(module)),
                          onSelected: (_) => onSelected(module),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
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
            border: Border.all(color: const Color(0xFFF0C15A)),
          ),
          child: Image.asset(
            BrandingAssets.appIcon,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.graphic_eq_rounded, color: Color(0xFFF0C15A)),
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
  });

  final _AdminModule module;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFF2A183D) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _moduleIcon(module),
                  color: selected ? const Color(0xFFF0C15A) : Colors.white70,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _moduleLabel(module),
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFBCAED6),
                      fontWeight: FontWeight.w900,
                    ),
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
    return _AdminCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFFF0C15A).withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: const Color(0xFFF0C15A), size: 28),
          ),
          const SizedBox(width: 14),
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
                        style: _titleStyle,
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 8),
                      const _RoleChip(label: 'view only'),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
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
    final items = [
      ('Pending', overview?.pendingRechargeCount ?? 0, Icons.pending_actions),
      (
        'Approved Today',
        overview?.approvedRechargeCountToday ?? 0,
        Icons.verified,
      ),
      (
        'Coins Today',
        overview?.totalCoinsChargedToday ?? 0,
        Icons.monetization_on,
      ),
      (
        'Gift Spend',
        overview?.totalGiftCoinsSpentToday ?? 0,
        Icons.card_giftcard,
      ),
      ('Diamonds', overview?.totalDiamondsEarnedToday ?? 0, Icons.diamond),
      (
        'Gifts Today',
        overview?.totalGiftTransactionsToday ?? 0,
        Icons.auto_awesome,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1040
            ? 6
            : constraints.maxWidth > 760
            ? 3
            : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: columns == 2 ? 1.55 : 1.9,
          children: items
              .map(
                (item) => _AdminStatCard(
                  label: item.$1,
                  value: item.$2,
                  icon: item.$3,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 22),
          const SizedBox(height: 14),
          Text(
            _formatAdminCount(value),
            style: _titleStyle.copyWith(fontSize: 24),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _mutedStyle.copyWith(fontSize: 12),
          ),
        ],
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
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: _titleStyle)),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
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
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: onApprove,
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
    return _AdminSectionCard(
      title: 'Wallet Lookup',
      child: Column(
        children: [
          _SearchRow(
            controller: lookupController,
            label: 'Public user ID',
            onSearch: onSearch,
          ),
          if (wallet != null) ...[
            const SizedBox(height: 12),
            _AdminListTile(
              icon: Icons.account_balance_wallet_rounded,
              title: wallet!.nickname ?? wallet!.publicUserId ?? wallet!.userId,
              subtitle:
                  'Coins ${wallet!.coinsBalance} - Diamonds ${wallet!.diamondsBalance}',
              trailing: _RoleChip(label: wallet!.publicUserId ?? 'wallet'),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 480;
                final fields = [
                  Expanded(
                    child: TextField(
                      controller: coinsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Coins delta',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8, height: 8),
                  Expanded(
                    child: TextField(
                      controller: diamondsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Diamonds delta',
                      ),
                    ),
                  ),
                ];
                if (narrow) {
                  return Column(
                    children: [fields[0], const SizedBox(height: 8), fields[2]],
                  );
                }
                return Row(children: fields);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canFinance ? onAdjust : null,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Apply adjustment'),
              ),
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
        final field = TextField(
          controller: controller,
          onSubmitted: (_) => onSearch(),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              FilledButton(onPressed: onSearch, child: const Text('Search')),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 10),
            FilledButton(onPressed: onSearch, child: const Text('Search')),
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
    required this.onAssign,
    required this.onRemoveRole,
  });

  final AdminUserSummary user;
  final bool canManageRoles;
  final VoidCallback onOpen;
  final VoidCallback onAssign;
  final ValueChanged<String> onRemoveRole;

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
                onDeleted: canManageRoles ? () => onRemoveRole(role) : null,
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
        color: const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: gift.isActive
              ? const Color(0xFFF0C15A)
              : const Color(0xFF5A3A86),
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
    return const Icon(
      Icons.card_giftcard_rounded,
      color: Color(0xFFF0C15A),
      size: 42,
    );
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
          color: const Color(0xFF1B102B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? const Color(0xFFF0C15A) : const Color(0xFF5A3A86),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.edit_rounded,
                    color: Color(0xFFF0C15A),
                    size: 16,
                  ),
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
        '${transaction.coinsDelta}c / ${transaction.diamondsDelta}d',
        style: const TextStyle(
          color: Color(0xFFF0C15A),
          fontWeight: FontWeight.w900,
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
        color: const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF5A3A86)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final leading = Row(
            children: [
              Icon(icon, color: const Color(0xFFF0C15A)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF5A3A86)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFF0C15A), size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
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
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _AdminEmptyState(icon: icon, title: title, subtitle: subtitle),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0C15A).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF0C15A)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFF0C15A),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF5A3A86)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.11),
            blurRadius: 18,
            offset: const Offset(0, 10),
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
    _AdminModule.audit => Icons.fact_check_rounded,
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
    _AdminModule.audit => 'Audit',
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
  color: Colors.white,
  fontSize: 20,
  fontWeight: FontWeight.w900,
);

const _mutedStyle = TextStyle(
  color: Color(0xFFBCAED6),
  fontWeight: FontWeight.w700,
);
