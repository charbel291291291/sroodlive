import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/vip/vip_frame_layout.dart';
import '../../../core/vip/vip_privileges.dart';
import '../../../core/vip/vip_spec.dart';
import '../../../features/admin/models/admin_models.dart';
import '../../../features/admin/services/admin_access_service.dart';
import '../../../features/admin/services/admin_service.dart';
import '../../../shared/theme/vip_tier_colors.dart';
import '../../../shared/widgets/premium_country_flag.dart';
import '../../../shared/widgets/vip_framed_avatar.dart';
import '../../profile/utils/vip_assets.dart';
import '../../vip/models/user_vip.dart';
import '../../vip/screens/vip_settings_screen.dart';
import '../../vip/services/vip_service.dart';
import '../services/gamification_service.dart';
import 'vip_rules_screen.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// â”€â”€ Palette â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

const _kBg = Color(0xFF07030D);
const _kCard = Color(0xFF12091D);
const _kCardBorder = Color(0xFF2A1845);
const _kGold = Color(0xFFF0C15A);
const _kSubtext = Color(0xFF7A6890);
const _kText = Color(0xFFD8CFEA);
const _kPurpleDeep = Color(0xFF4B168C);
const _kPurpleMid = Color(0xFF8B26D9);
const _kGreen = Color(0xFF2ECC71);
const _kRed = Color(0xFFFF5C7A);

// â”€â”€ VIP Center 2.0 (Srood VIP Prestige) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Phase V1: presentational reskin. Flip this flag to false to instantly fall
// back to the legacy VIP Center layout (kept fully intact below).
final bool _kUseVip2Shell = true;

const _v2Gold = Color(0xFFF7E2A0);
const _v2GoldDim = Color(0xFFE8C25A);
const _v2Lilac = Color(0xFFB7AAE0);
const _v2Sub = Color(0xFF9C8FCB);
const _v2Green = Color(0xFF86E0B6);

/// Approved Srood Live monthly *maintain* EXP per VIP tier (1 coin = 1 EXP).
/// Display-only source for the recharge card so it never shows a legacy server
/// legacy server value and mirrors the published VIP Rules table.
const Map<int, int> _kVipMaintainExp = {
  1: 60000,
  2: 100000,
  3: 200000,
  4: 400000,
  5: 750000,
  6: 1500000,
  7: 3000000,
  8: 6000000,
  9: 12000000,
};

/// Comma-groups an integer for display (1234567 -> "1,234,567").
String _v2Fmt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class VipCenterScreen extends StatefulWidget {
  const VipCenterScreen({
    required this.isArabic,
    this.currentVipLevel = 0,
    this.vipExpiresAt,
    super.key,
  });

  final bool isArabic;
  final int currentVipLevel;
  final DateTime? vipExpiresAt;

  @override
  State<VipCenterScreen> createState() => _VipCenterScreenState();
}

class _VipCenterScreenState extends State<VipCenterScreen> {
  final _service = const GamificationService();

  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;

  late int _selectedTier;

  AdminRole _adminRole = AdminRole.empty;
  bool _adminLoading = true;

  UserVip? _userVip;

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.currentVipLevel.clamp(1, 9);
    _load();
    _loadAdminRole();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _service.getVipPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return;
    }
    // VIP EXP data is supplementary â€” a failure here must not block the screen.
    try {
      final vip = await VipService().getMyVip();
      if (!mounted) return;
      setState(() => _userVip = vip);
    } catch (_) {
      // _userVip stays null; progress section shows empty-state gracefully.
    }
  }

  Future<void> _loadAdminRole() async {
    try {
      final role = await const AdminAccessService().fetchCurrentAdminRole();
      if (!mounted) return;
      setState(() {
        _adminRole = role;
        _adminLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _adminLoading = false);
    }
  }

  String _planNameForLevel(int level) {
    for (final p in _plans) {
      if ((p['level'] as int?) == level) {
        final name = context.isArabic
            ? (p['arabic_name'] ?? p['name'])
            : p['name'];
        return name?.toString() ?? 'VIP $level';
      }
    }
    return 'VIP $level';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), _kBg, Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _kUseVip2Shell ? _buildVip2Header() : _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
    child: Row(
      textDirection: context.isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        Text(
          context.isArabic ? 'Ù…Ø±ÙƒØ² VIP' : 'VIP Center',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kGold, strokeWidth: 2.5),
      );
    }
    if (_error != null) return _buildError();

    if (_kUseVip2Shell) return _buildVip2Body();

    return RefreshIndicator(
      color: _kGold,
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _CurrentStatusCard(
            vipLevel: widget.currentVipLevel,
            expiresAt: widget.vipExpiresAt,
            isArabic: context.isArabic,
          ),
          const SizedBox(height: 12),
          _VipProgressSection(
            vipLevel: widget.currentVipLevel,
            isArabic: context.isArabic,
            userVip: _userVip,
          ),
          const SizedBox(height: 10),
          _VipSettingsButton(
            vipLevel: widget.currentVipLevel,
            isArabic: context.isArabic,
          ),
          const SizedBox(height: 24),
          _SectionLabel(
            label: context.isArabic
                ? 'Ø§Ø³ØªÙƒØ´Ø§Ù Ù…Ø³ØªÙˆÙŠØ§Øª VIP'
                : 'Explore VIP Tiers',
            isArabic: context.isArabic,
          ),
          const SizedBox(height: 10),
          _TierSelector(
            selected: _selectedTier,
            currentLevel: widget.currentVipLevel,
            onSelect: (t) => setState(() => _selectedTier = t),
          ),
          const SizedBox(height: 16),
          _TierPreviewCard(
            level: _selectedTier,
            isArabic: context.isArabic,
            planName: _planNameForLevel(_selectedTier),
            isCurrent:
                _selectedTier == widget.currentVipLevel &&
                widget.currentVipLevel > 0,
          ),
          const SizedBox(height: 16),
          _BenefitsList(level: _selectedTier, isArabic: context.isArabic),
          const SizedBox(height: 20),
          _ContactAdminButton(isArabic: context.isArabic),
          if (!_adminLoading &&
              (_adminRole.hasPermission(kPermVipGrant) ||
                  _adminRole.isOSuperAdmin ||
                  _adminRole.isPSuperAdmin ||
                  _adminRole.isSuperAdmin)) ...[
            const SizedBox(height: 24),
            _AdminVipPanel(isArabic: context.isArabic),
          ],
        ],
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, color: _kRed, size: 40),
        const SizedBox(height: 12),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kText, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _load,
          child: Text(
            context.isArabic ? 'Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø©' : 'Retry',
            style: const TextStyle(color: _kGold),
          ),
        ),
      ],
    ),
  );

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // VIP Center 2.0 â€” Phase V1 presentational shell (English-only)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildVip2Header() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        const Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'VIP',
                style: TextStyle(
                  color: _v2Gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'SROOD LIVE',
                style: TextStyle(
                  color: _v2Lilac,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _onVip2HelpTap,
          icon: const Icon(Icons.help_outline_rounded, color: Colors.white70),
        ),
      ],
    ),
  );

  void _onVip2HelpTap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VipRulesScreen()),
    );
  }

  // Phase V1 CTA â€” honest, no purchase logic. The existing economy grants VIP
  // through a recharge agent / admin, so this points the user there.
  void _onVip2UpgradeTap() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        // Fixed (docked) behaviour so the snackbar never floats on top of the
        // sticky recharge card the way the old floating snackbar did.
        const SnackBar(
          content: Text('Upgrade your VIP through a recharge agent or admin.'),
          behavior: SnackBarBehavior.fixed,
        ),
      );
  }

  // Real per-tier unlock price (coins) from the vip_plans rules. 0 if unknown.
  int _priceForLevel(int level) {
    for (final p in _plans) {
      if ((p['level'] as int?) == level) {
        final v = p['price_coins'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v) ?? 0;
      }
    }
    return 0;
  }

  Widget _buildVip2Body() {
    // owned = the user's real VIP level; sel = the tier being previewed via the
    // carousel (user tap/swipe). The whole hero/lock/requirement/perks follow
    // the SELECTED tier, while ownership state is computed against `owned`.
    final owned = widget.currentVipLevel.clamp(0, 9);
    final sel = _selectedTier.clamp(1, 9);

    final isCurrent = sel == owned && owned > 0; // exactly the active tier
    final isOwned = owned > 0 && sel <= owned; // reached (this or a lower tier)
    final isMaxSel = sel >= 9;

    // Real privileges granted at the SELECTED tier (never hardcoded).
    final unlocked = VipPrivileges.unlockedFor(sel).length;
    final total = unlocked + VipPrivileges.lockedFor(sel).length;

    // Real per-tier unlock requirement from vip_plans (coins). No fabrication:
    // if a plan has no price we show a neutral prompt instead of a fake number.
    final price = _priceForLevel(sel);
    final reqText = isCurrent
        ? 'Your current tier - VIP $sel'
        : isOwned
        ? 'VIP $sel unlocked'
        : isMaxSel
        ? (price > 0
              ? '${_v2Fmt(price)} coins to reach VIP 9 (max)'
              : 'Top tier - VIP 9')
        : (price > 0
              ? '${_v2Fmt(price)} coins required to unlock VIP $sel'
              : 'Recharge to unlock VIP $sel');

    // Monthly maintenance progress. The target is the approved per-tier maintain
    // EXP (never the server's legacy monthly_maintain_exp, which carried values
    // from legacy server values. No VIP falls back to the VIP-1 goal of 60,000 EXP.
    final vip = _userVip;
    final monthlyExp = vip?.monthlyExp ?? 0;
    final targetLevel = owned <= 0 ? 1 : owned.clamp(1, 9);
    final maintainTarget = _kVipMaintainExp[targetLevel] ?? 60000;
    final progress = maintainTarget > 0
        ? (monthlyExp / maintainTarget).clamp(0.0, 1.0)
        : 0.0;
    final monthText = '${_v2Fmt(monthlyExp)} / ${_v2Fmt(maintainTarget)} EXP';

    // "Max VIP reached" only when truly maxed on both owned AND selected tier.
    final isMaxState = owned >= 9 && sel >= 9;

    // Message text.
    final rechargeHint = owned <= 0
        ? 'Recharge to start your VIP journey.'
        : isMaxState
        ? 'Max VIP reached. Maintain your monthly recharge to keep benefits.'
        : sel > owned
        ? 'Recharge to unlock this VIP tier.'
        : 'Maintain your monthly recharge to keep this tier active.';

    // Button label.
    final btnLabel = owned <= 0
        ? 'Recharge to Unlock'
        : isMaxState
        ? 'Maintain VIP Benefits'
        : sel > owned
        ? 'Recharge to Upgrade'
        : 'Recharge to Maintain';

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    // Single scrolling column — the recharge card is an inline section ABOVE the
    // privileges grid (no floating overlay), so nothing overlaps and the card
    // never sits on the Android navigation bar.
    return RefreshIndicator(
      color: _kGold,
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20 + bottomInset),
        children: [
          const SizedBox(height: 4),
          _Vip2Crest(level: sel),
          const SizedBox(height: 10),
          Center(
            child: _Vip2LockPill(
              state: isCurrent
                  ? _Vip2OwnState.active
                  : isOwned
                  ? _Vip2OwnState.owned
                  : _Vip2OwnState.locked,
            ),
          ),
          const SizedBox(height: 10),
          Center(child: _Vip2Pill(text: reqText)),
          const SizedBox(height: 16),
          // Recharge card — clean standalone section, in flow.
          _Vip2RechargeCard(
            monthText: monthText,
            progress: progress.toDouble(),
            buttonLabel: btnLabel,
            hint: rechargeHint,
            onUpgrade: _onVip2UpgradeTap,
          ),
          const SizedBox(height: 18),
          _Vip2Rail(
            selectedLevel: sel,
            ownedLevel: owned,
            onSelect: (l) => setState(() => _selectedTier = l),
          ),
          const SizedBox(height: 18),
          _Vip2SectionDivider(
            label: 'Privileges',
            counter: '$unlocked / $total',
          ),
          const SizedBox(height: 14),
          _Vip2PerkGrid(selectedLevel: sel),
          if (!_adminLoading &&
              (_adminRole.hasPermission(kPermVipGrant) ||
                  _adminRole.isOSuperAdmin ||
                  _adminRole.isPSuperAdmin ||
                  _adminRole.isSuperAdmin)) ...[
            const SizedBox(height: 24),
            _AdminVipPanel(isArabic: context.isArabic),
          ],
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Section label
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isArabic});
  final String label;
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Align(
    alignment: isArabic ? Alignment.centerRight : Alignment.centerLeft,
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Current status card
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({
    required this.vipLevel,
    required this.expiresAt,
    required this.isArabic,
  });
  final int vipLevel;
  final DateTime? expiresAt;
  final bool isArabic;

  // State helpers
  bool get _hasVip => vipLevel > 0;
  bool get _isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get _isActive => _hasVip && !_isExpired;
  bool get _isMax => vipLevel >= 9;

  int get _remainingDays {
    if (expiresAt == null) return 0;
    return expiresAt!.difference(DateTime.now()).inDays.clamp(0, 9999);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final tier = _isActive ? VipTierColors.of(vipLevel) : null;
    final spec = VipSpecResolver.resolve(vipLevel);

    final borderColor = _isActive
        ? tier!.border.withValues(alpha: 0.55)
        : _kCardBorder;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _isActive
            ? LinearGradient(
                colors: [
                  tier!.start.withValues(alpha: 0.22),
                  tier.end.withValues(alpha: 0.08),
                  const Color(0xFF12091D),
                ],
                stops: const [0.0, 0.45, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF1B102A), Color(0xFF12091D)],
              ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: _isActive ? 1.5 : 1),
        boxShadow: _isActive
            ? [
                BoxShadow(
                  color: spec.glowColor.withValues(alpha: 0.18),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VipFramedAvatar(size: 68, vipLevel: _isActive ? vipLevel : null),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Status badge row
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    if (_isActive)
                      _StatusPill(
                        label: isArabic ? 'Ù†Ø´Ø·' : 'Active',
                        color: const Color(0xFF22C55E),
                      )
                    else if (_isExpired)
                      _StatusPill(
                        label: isArabic ? 'Ù…Ù†ØªÙ‡ÙŠ' : 'Expired',
                        color: _kRed,
                      )
                    else
                      _StatusPill(
                        label: isArabic ? 'ØºÙŠØ± Ù…ÙØ¹Ù‘Ù„' : 'No VIP',
                        color: _kSubtext,
                      ),
                    if (_isActive && _isMax) ...[
                      const SizedBox(width: 6),
                      _StatusPill(
                        label: isArabic ? 'Ø§Ù„Ø­Ø¯ Ø§Ù„Ø£Ù‚ØµÙ‰' : 'MAX',
                        color: tier!.start,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Level label
                Text(
                  _isActive
                      ? 'VIP $_vipLabel'
                      : (isArabic ? 'Ù„Ø§ ÙŠÙˆØ¬Ø¯ VIP Ù†Ø´Ø·' : 'No Active VIP'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _isActive ? (tier?.border ?? _kGold) : _kSubtext,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                // Expiry info
                if (_isActive && expiresAt != null) ...[
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    text: isArabic
                        ? 'ÙŠÙ†ØªÙ‡ÙŠ: ${_fmtDate(expiresAt!)}'
                        : 'Expires: ${_fmtDate(expiresAt!)}',
                    color: _kText,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(
                    icon: Icons.timer_rounded,
                    text: isArabic
                        ? 'Ø§Ù„Ù…ØªØ¨Ù‚ÙŠ: $_remainingDays ÙŠÙˆÙ…'
                        : 'Remaining: $_remainingDays day${_remainingDays == 1 ? '' : 's'}',
                    color: _remainingDaysColor,
                  ),
                ] else if (_isExpired && expiresAt != null)
                  _InfoRow(
                    icon: Icons.timer_off_rounded,
                    text: isArabic
                        ? 'Ø§Ù†ØªÙ‡Ù‰ ÙÙŠ: ${_fmtDate(expiresAt!)}'
                        : 'Expired on: ${_fmtDate(expiresAt!)}',
                    color: _kRed,
                  )
                else if (!_hasVip)
                  _InfoRow(
                    icon: Icons.info_outline_rounded,
                    text: isArabic
                        ? 'ØªÙˆØ§ØµÙ„ Ù…Ø¹ Ø§Ù„Ø¥Ø¯Ø§Ø±Ø© Ù„Ù„Ø­ØµÙˆÙ„ Ø¹Ù„Ù‰ VIP'
                        : 'Contact admin to get VIP',
                    color: _kSubtext,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _vipLabel => '$vipLevel';

  Color get _remainingDaysColor {
    if (_remainingDays <= 7) return _kRed;
    if (_remainingDays <= 30) return const Color(0xFFF59E0B);
    return const Color(0xFF22C55E);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color.withValues(alpha: 0.7)),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 12, height: 1.3),
        ),
      ),
    ],
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// VIP Level Progress section
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _VipProgressSection extends StatelessWidget {
  const _VipProgressSection({
    required this.vipLevel,
    required this.isArabic,
    this.userVip,
  });
  final int vipLevel;
  final bool isArabic;
  final UserVip? userVip;

  bool get _isMax => vipLevel >= 9;

  static String _fmtExp(int n) {
    // Comma-separated: 1,234,567
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final UserVip? vip = userVip;
    final bool hasExp =
        vip != null && (vip.rechargeExp > 0 || vip.vipLevel > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(Icons.trending_up_rounded, color: _kGold, size: 16),
              const SizedBox(width: 7),
              Text(
                isArabic ? 'ØªÙ‚Ø¯Ù… VIP' : 'VIP Progress',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                vipLevel > 0 ? 'VIP $vipLevel / 9' : '0 / 9',
                style: const TextStyle(
                  color: _kSubtext,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // â”€â”€ 9-segment tier bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            children: List.generate(9, (i) {
              final segLevel = i + 1;
              final filled = segLevel <= vipLevel;
              final isCurrent = segLevel == vipLevel;
              final tier = VipTierColors.of(segLevel);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 8 ? 3 : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: isCurrent ? 10 : 7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: filled
                          ? LinearGradient(
                              colors: [tier.start, tier.end],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            )
                          : null,
                      color: filled ? null : _kCardBorder,
                      boxShadow: isCurrent
                          ? [BoxShadow(color: tier.shadow, blurRadius: 6)]
                          : null,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),

          // â”€â”€ EXP stats â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (vip != null && hasExp) ...[
            // Promote to non-null inside builder via local
            _VipExpBlock(
              vip: vip,
              vipLevel: vipLevel,
              isArabic: isArabic,
              isMax: _isMax,
              fmtExp: _fmtExp,
            ),
          ] else ...[
            // No EXP data yet â€” show journey start prompt
            _ExpStatRow(
              icon: Icons.rocket_launch_rounded,
              text: vipLevel <= 0
                  ? (isArabic
                        ? 'Ø§Ø¨Ø¯Ø£ Ø±Ø­Ù„Ø© VIP Ø¨Ø§Ù„Ø´Ø­Ù†'
                        : 'Start your VIP journey by recharging')
                  : (isArabic
                        ? 'Ø§Ø³ØªÙ…Ø± Ø¨Ø§Ù„Ø´Ø­Ù† Ù„Ù„Ø­ÙØ§Ø¸ Ø¹Ù„Ù‰ VIP'
                        : 'Keep recharging to maintain your VIP'),
              color: _kSubtext,
              isArabic: isArabic,
            ),
          ],
        ],
      ),
    );
  }
}

// â”€â”€ EXP helper widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// Separate stateless widget so Dart narrows vip to non-null via the constructor.
class _VipExpBlock extends StatelessWidget {
  const _VipExpBlock({
    required this.vip,
    required this.vipLevel,
    required this.isArabic,
    required this.isMax,
    required this.fmtExp,
  });
  final UserVip vip;
  final int vipLevel;
  final bool isArabic;
  final bool isMax;
  final String Function(int) fmtExp;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: isArabic
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      // Lifetime EXP + Monthly EXP stat row
      Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Expanded(
            child: _ExpStat(
              label: isArabic ? 'Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø´Ø­Ù†' : 'Total Recharge EXP',
              value: fmtExp(vip.rechargeExp),
              icon: Icons.bolt_rounded,
              color: _kGold,
              isArabic: isArabic,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ExpStat(
              label: isArabic ? 'EXP Ù‡Ø°Ø§ Ø§Ù„Ø´Ù‡Ø±' : 'Monthly EXP',
              value: fmtExp(vip.monthlyExp),
              icon: Icons.calendar_month_rounded,
              color: _kPurpleMid,
              isArabic: isArabic,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // Next tier progress
      if (!isMax) ...[
        _ExpProgressBar(
          label: isArabic
              ? 'Ù†Ø­Ùˆ VIP ${vipLevel + 1}'
              : 'Progress to VIP ${vipLevel + 1}',
          progress: vip.nextTierProgress ?? 0.0,
          remaining: vip.expToNextTier,
          remainingLabel: isArabic ? 'Ù…ØªØ¨Ù‚ÙŠ' : 'remaining',
          gradientColors: const [_kPurpleDeep, _kPurpleMid],
          isArabic: isArabic,
          fmtExp: fmtExp,
        ),
        const SizedBox(height: 10),
      ] else ...[
        _ExpStatRow(
          icon: Icons.emoji_events_rounded,
          text: isArabic
              ? 'ÙˆØµÙ„Øª Ø¥Ù„Ù‰ Ø£Ø¹Ù„Ù‰ Ù…Ø³ØªÙˆÙ‰ VIP!'
              : 'Maximum VIP tier reached!',
          color: _kGold,
          isArabic: isArabic,
        ),
        const SizedBox(height: 10),
      ],

      // Monthly maintain progress (VIP > 0 only)
      if (vipLevel > 0)
        _ExpProgressBar(
          label: isArabic ? 'ØªØ¬Ø¯ÙŠØ¯ Ø§Ù„Ø´Ù‡Ø± Ø§Ù„Ø­Ø§Ù„ÙŠ' : 'Monthly Renewal',
          progress: vip.monthlyMaintainProgress ?? 0.0,
          remaining: vip.expToMaintain,
          remainingLabel: isArabic ? 'Ù„Ù„ØªØ¬Ø¯ÙŠØ¯' : 'to renew',
          gradientColors: vip.isMonthlyMaintainMet
              ? const [Color(0xFF16A34A), Color(0xFF22C55E)]
              : const [Color(0xFF9A3412), Color(0xFFF59E0B)],
          isArabic: isArabic,
          fmtExp: fmtExp,
          metLabel: isArabic ? 'ØªØ¬Ø¯ÙŠØ¯ Ù…Ø¶Ù…ÙˆÙ† âœ“' : 'Renewal secured âœ“',
          isMet: vip.isMonthlyMaintainMet,
        ),
    ],
  );
}

class _ExpStat extends StatelessWidget {
  const _ExpStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isArabic,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: isArabic
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color.withValues(alpha: 0.8)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
      ],
    ),
  );
}

class _ExpProgressBar extends StatelessWidget {
  const _ExpProgressBar({
    required this.label,
    required this.progress,
    required this.remaining,
    required this.remainingLabel,
    required this.gradientColors,
    required this.isArabic,
    required this.fmtExp,
    this.metLabel,
    this.isMet = false,
  });
  final String label;
  final double progress;
  final int? remaining;
  final String remainingLabel;
  final List<Color> gradientColors;
  final bool isArabic;
  final String Function(int) fmtExp;
  final String? metLabel;
  final bool isMet;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final pctText = '${(clampedProgress * 100).toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: isArabic
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        // Label + percentage
        Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isMet && metLabel != null ? metLabel! : pctText,
              style: TextStyle(
                color: isMet ? const Color(0xFF22C55E) : gradientColors.last,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // Bar
        LayoutBuilder(
          builder: (_, constraints) => Stack(
            children: [
              // Track
              Container(
                height: 7,
                decoration: BoxDecoration(
                  color: _kCardBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              // Fill
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                height: 7,
                width: constraints.maxWidth * clampedProgress,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.last.withValues(alpha: 0.4),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Remaining EXP hint
        if (!isMet && remaining != null && remaining! > 0) ...[
          const SizedBox(height: 3),
          Text(
            '${fmtExp(remaining!)} EXP $remainingLabel',
            style: const TextStyle(
              color: _kSubtext,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _ExpStatRow extends StatelessWidget {
  const _ExpStatRow({
    required this.icon,
    required this.text,
    required this.color,
    required this.isArabic,
  });
  final IconData icon;
  final String text;
  final Color color;
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Row(
    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// VIP settings shortcut
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _VipSettingsButton extends StatelessWidget {
  const _VipSettingsButton({required this.vipLevel, required this.isArabic});
  final int vipLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VipSettingsScreen(
            isArabic: isArabic,
            effectiveVipLevel: vipLevel,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF0D1A2A),
          border: Border.all(
            color: const Color(0xFF1A8CB0).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(
              Icons.settings_rounded,
              color: Color(0xFF5DDCFF),
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              isArabic ? 'Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª VIP' : 'VIP Settings',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white54,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tier selector â€” horizontal scroll VIP 1..9 (premium tier cards)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TierSelector extends StatelessWidget {
  const _TierSelector({
    required this.selected,
    required this.currentLevel,
    required this.onSelect,
  });
  final int selected;
  final int currentLevel;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: 9,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _VipTierCard(
          level: i + 1,
          isSelected: (i + 1) == selected,
          isCurrent: (i + 1) == currentLevel,
          onTap: () => onSelect(i + 1),
        ),
      ),
    );
  }
}

class _VipTierCard extends StatelessWidget {
  const _VipTierCard({
    required this.level,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
  });

  final int level;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tier = VipTierColors.of(level);
    final spec = VipSpecResolver.resolve(level);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isSelected
              ? LinearGradient(
                  colors: [tier.start, tier.end],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    tier.start.withValues(alpha: 0.12),
                    tier.end.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          border: Border.all(
            color: isSelected
                ? tier.border
                : isCurrent
                ? tier.border.withValues(alpha: 0.55)
                : tier.start.withValues(alpha: 0.25),
            width: isSelected ? 1.8 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: spec.glowColor.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 0,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Label
            Text(
              'VIP',
              style: TextStyle(
                color: isSelected
                    ? tier.text.withValues(alpha: 0.75)
                    : tier.border.withValues(alpha: 0.55),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '$level',
              style: TextStyle(
                color: isSelected ? tier.text : tier.border,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            // Indicator row: dot = current level, line = selected-only accent
            if (isCurrent)
              Container(
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: isSelected
                      ? tier.text.withValues(alpha: 0.8)
                      : tier.border,
                ),
              )
            else
              const SizedBox(height: 3),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tier preview card
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TierPreviewCard extends StatelessWidget {
  const _TierPreviewCard({
    required this.level,
    required this.isArabic,
    required this.planName,
    required this.isCurrent,
  });
  final int level;
  final bool isArabic;
  final String planName;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final spec = VipSpecResolver.resolve(level);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [spec.glowColor.withValues(alpha: 0.18), _kCard],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: spec.glowColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              VipFramedAvatar(size: 72, vipLevel: level),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _kGold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isArabic ? 'Ø£Ù†Øª' : 'You',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  planName,
                  style: TextStyle(
                    color: spec.nameColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FeatureChip(
                      icon: Icons.crop_portrait_rounded,
                      label: isArabic ? 'Ø¥Ø·Ø§Ø±' : 'Frame',
                      active: spec.hasFrame,
                    ),
                    _FeatureChip(
                      icon: Icons.verified_rounded,
                      label: isArabic ? 'Ø´Ø§Ø±Ø©' : 'Badge',
                      active: spec.hasBadge,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    _ColorDot(
                      color: spec.glowColor,
                      label: isArabic ? 'ØªÙˆÙ‡Ø¬' : 'Glow',
                    ),
                    const SizedBox(width: 10),
                    _ColorDot(
                      color: spec.nameColor,
                      label: isArabic ? 'Ø§Ø³Ù…' : 'Name',
                    ),
                    if (spec.bannerGradient.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _ColorDot(
                        color: spec.bannerGradient.first,
                        label: isArabic ? 'Ù„Ø§ÙØªØ©' : 'Banner',
                      ),
                    ],
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

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: _kSubtext, fontSize: 11)),
    ],
  );
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.active,
  });
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: active ? _kGold.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: active ? _kGold.withValues(alpha: 0.4) : _kCardBorder,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: active ? _kGold : _kSubtext),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: active ? _kGold : _kSubtext,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Benefits list
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _BenefitsList extends StatelessWidget {
  const _BenefitsList({required this.level, required this.isArabic});
  final int level;
  final bool isArabic;

  // Icon mapping for known privilege keys
  static const Map<VipPrivilegeKey, IconData> _icons = {
    VipPrivilegeKey.profileGlow: Icons.flare_rounded,
    VipPrivilegeKey.vipBadge: Icons.verified_rounded,
    VipPrivilegeKey.vipFrame: Icons.crop_portrait_rounded,
    VipPrivilegeKey.micWave: Icons.graphic_eq_rounded,
    VipPrivilegeKey.entranceEffect: Icons.auto_awesome_rounded,
    VipPrivilegeKey.kickProtection: Icons.shield_outlined,
    VipPrivilegeKey.kickConfirmation: Icons.gavel_rounded,
    VipPrivilegeKey.strongAntiKick: Icons.shield_rounded,
    VipPrivilegeKey.notBeingFollowed: Icons.person_off_rounded,
    VipPrivilegeKey.antiEnteringRoom: Icons.meeting_room_rounded,
    VipPrivilegeKey.privateBrowsing: Icons.visibility_off_rounded,
    VipPrivilegeKey.doNotDisturb: Icons.notifications_off_rounded,
    VipPrivilegeKey.antiKick: Icons.block_rounded,
    VipPrivilegeKey.invisibility: Icons.blur_on_rounded,
    VipPrivilegeKey.sendRoomChatImage: Icons.image_rounded,
    VipPrivilegeKey.silentEntry: Icons.volume_off_rounded,
  };

  static IconData _iconFor(VipPrivilegeKey key) =>
      _icons[key] ?? Icons.star_rounded;

  @override
  Widget build(BuildContext context) {
    final unlocked = VipPrivileges.unlockedFor(level);
    final locked = VipPrivileges.lockedFor(level);
    final total = unlocked.length + locked.length;

    // Tier color for the header counter â€” use the viewed tier, fall back to gold
    final headerColor = level > 0 ? VipTierColors.of(level).border : _kGold;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: headerColor,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Text(
                  isArabic ? 'Ø§Ù„Ù…Ø²Ø§ÙŠØ§' : 'Benefits',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                // unlocked / total counter
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: headerColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '${unlocked.length} / $total',
                    style: TextStyle(
                      color: headerColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // â”€â”€ Unlocked section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (unlocked.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _BenefitSectionLabel(
                icon: Icons.check_circle_rounded,
                label: isArabic ? 'Ù…ÙØ¹Ù‘Ù„Ø©' : 'Unlocked',
                color: const Color(0xFF22C55E),
                isArabic: isArabic,
              ),
            ),
            ...unlocked.map(
              (s) => _BenefitRow(
                spec: s,
                icon: _iconFor(s.key),
                unlocked: true,
                isArabic: isArabic,
              ),
            ),
          ],

          // â”€â”€ Divider + locked section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (locked.isNotEmpty) ...[
            if (unlocked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: _kCardBorder, height: 20),
              )
            else
              const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _BenefitSectionLabel(
                icon: Icons.lock_rounded,
                label: isArabic ? 'Ù…Ø²Ø§ÙŠØ§ Ø£Ø¹Ù„Ù‰' : 'Higher Tier',
                color: _kSubtext,
                isArabic: isArabic,
              ),
            ),
            ...locked.map(
              (s) => _BenefitRow(
                spec: s,
                icon: _iconFor(s.key),
                unlocked: false,
                isArabic: isArabic,
              ),
            ),
          ],

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _BenefitSectionLabel extends StatelessWidget {
  const _BenefitSectionLabel({
    required this.icon,
    required this.label,
    required this.color,
    required this.isArabic,
  });
  final IconData icon;
  final String label;
  final Color color;
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Row(
    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ],
  );
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.spec,
    required this.icon,
    required this.unlocked,
    required this.isArabic,
  });
  final VipPrivilegeSpec spec;
  final IconData icon;
  final bool unlocked;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final label = isArabic ? spec.labelAr : spec.label;
    final desc = isArabic ? spec.descriptionAr : spec.description;
    final reqTier = VipTierColors.of(spec.minVipLevel);

    // Icon container color: tier-tinted when unlocked, plain grey when locked
    final iconBg = unlocked
        ? reqTier.start.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.05);
    final iconColor = unlocked ? reqTier.border : _kSubtext;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: unlocked
              ? reqTier.start.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unlocked
                ? reqTier.border.withValues(alpha: 0.18)
                : _kCardBorder.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon box
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unlocked ? Colors.white : _kSubtext,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: TextStyle(
                        color: unlocked
                            ? _kText.withValues(alpha: 0.75)
                            : _kSubtext.withValues(alpha: 0.6),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Right-side indicator
            if (unlocked)
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: const Color(0xFF22C55E).withValues(alpha: 0.85),
              )
            else
              // "Requires VIP X+" chip using that tier's color
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: reqTier.start.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: reqTier.border.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  isArabic
                      ? 'VIP${spec.minVipLevel}+'
                      : 'VIP${spec.minVipLevel}+',
                  style: TextStyle(
                    color: reqTier.border,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Contact admin CTA
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ContactAdminButton extends StatelessWidget {
  const _ContactAdminButton({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPurpleDeep, _kPurpleMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kPurpleMid.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 24,
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
                  isArabic ? 'ØªÙˆØ§ØµÙ„ Ù…Ø¹ Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©' : 'Contact Admin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  isArabic
                      ? 'Ù„Ù„ØªØ±Ù‚ÙŠØ© Ø¥Ù„Ù‰ VIP Ø¹Ø¨Ø± ÙˆÙƒÙŠÙ„ Ø§Ù„Ø´Ø­Ù†'
                      : 'Upgrade VIP through a recharge agent',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white,
            size: 22,
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Admin VIP management panel
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AdminVipPanel extends StatefulWidget {
  const _AdminVipPanel({required this.isArabic});
  final bool isArabic;

  @override
  State<_AdminVipPanel> createState() => _AdminVipPanelState();
}

class _AdminVipPanelState extends State<_AdminVipPanel> {
  // â”€â”€ Search â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _searchController = TextEditingController();
  List<AdminUserSummary> _searchResults = [];
  AdminUserSummary? _selectedUser;
  bool _searching = false;

  // â”€â”€ Grant / Revoke â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _durationController = TextEditingController(text: '30');
  int _grantLevel = 1;

  // â”€â”€ Golden ID â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _goldenEnabled = true;
  final _goldenIdController = TextEditingController();
  final _goldenDurationController = TextEditingController();
  String _goldenStyle = 'gold';
  String _goldenFrame = 'classic';

  // â”€â”€ Country Flag Style â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _countryCodeController = TextEditingController();
  final _countryNameController = TextEditingController();
  final _flagDurationController = TextEditingController();
  String _flagStyle = 'normal';
  String _flagFrame = 'classic';

  // â”€â”€ Shared â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _busy = false;
  String? _result;
  bool _resultIsError = false;

  bool get isArabic => widget.isArabic;
  bool get _hasUser => _selectedUser != null;

  static const _adminService = AdminService();

  @override
  void dispose() {
    _searchController.dispose();
    _durationController.dispose();
    _goldenIdController.dispose();
    _goldenDurationController.dispose();
    _countryCodeController.dispose();
    _countryNameController.dispose();
    _flagDurationController.dispose();
    super.dispose();
  }

  // â”€â”€ Search â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _searchUser() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchResults = [];
      _selectedUser = null;
      _result = null;
    });
    try {
      final results = await _adminService.findUsersForGrants(q);
      if (!mounted) return;
      setState(() => _searchResults = results);
      if (results.isEmpty) {
        _setResult(
          isArabic ? 'Ù„Ù… ÙŠÙØ¹Ø«Ø± Ø¹Ù„Ù‰ Ù…Ø³ØªØ®Ø¯Ù… Ø¨Ù‡Ø°Ø§ Ø§Ù„Ø¨Ø­Ø«' : 'No user found',
          error: true,
        );
      }
    } catch (e) {
      _setResult(isArabic ? 'ÙØ´Ù„ Ø§Ù„Ø¨Ø­Ø«: $e' : 'Search failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectUser(AdminUserSummary user) {
    setState(() {
      _selectedUser = user;
      _searchResults = [];
      _result = null;
      _searchController.text = user.title;
      // Pre-fill Golden ID fields from the selected user's current data.
      _goldenIdController.text = user.publicUserId ?? '';
      _goldenEnabled = user.isGoldenId;
      _goldenStyle = user.goldenIdStyle;
      _goldenFrame = user.goldenIdFrame;
      // Pre-fill Country Flag fields.
      _countryCodeController.text = user.countryCode ?? '';
      _countryNameController.text = user.country ?? '';
      _flagStyle = user.countryFlagStyle;
      _flagFrame = user.countryFlagFrame;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedUser = null;
      _searchResults = [];
      _searchController.clear();
      _result = null;
    });
  }

  // â”€â”€ Actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _grantVip() async {
    final user = _selectedUser;
    if (user == null) {
      _setResult(
        isArabic ? 'Ø§Ø®ØªØ± Ù…Ø³ØªØ®Ø¯Ù…Ø§Ù‹ Ø£ÙˆÙ„Ø§Ù‹' : 'Select a valid user first',
        error: true,
      );
      return;
    }
    final days = int.tryParse(_durationController.text.trim()) ?? 30;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await VipService().grantVip(
        userId: user.userId,
        vipLevel: _grantLevel,
        durationDays: days,
      );
      _setResult(
        isArabic
            ? 'ØªÙ… Ù…Ù†Ø­ VIP $_grantLevel Ù„Ù€${user.title} Ù„Ù…Ø¯Ø© $days ÙŠÙˆÙ…'
            : 'Granted VIP $_grantLevel to ${user.title} for $days days',
      );
    } catch (e) {
      _setResult(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeVip() async {
    final user = _selectedUser;
    if (user == null) {
      _setResult(
        isArabic ? 'Ø§Ø®ØªØ± Ù…Ø³ØªØ®Ø¯Ù…Ø§Ù‹ Ø£ÙˆÙ„Ø§Ù‹' : 'Select a valid user first',
        error: true,
      );
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await VipService().revokeVip(user.userId);
      _setResult(
        isArabic
            ? 'ØªÙ… Ø¥Ù„ØºØ§Ø¡ VIP Ù„Ù€${user.title}'
            : 'VIP revoked for ${user.title}',
      );
    } catch (e) {
      _setResult(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyGoldenId() async {
    final user = _selectedUser;
    if (user == null) {
      _setResult(
        isArabic ? 'Ø§Ø®ØªØ± Ù…Ø³ØªØ®Ø¯Ù…Ø§Ù‹ Ø£ÙˆÙ„Ø§Ù‹' : 'Select a valid user first',
        error: true,
      );
      return;
    }
    if (_goldenEnabled && _goldenIdController.text.trim().isEmpty) {
      _setResult(
        isArabic ? 'Ø£Ø¯Ø®Ù„ Ø±Ù‚Ù… Golden ID' : 'Enter a Golden ID number',
        error: true,
      );
      return;
    }
    final publicId = _goldenIdController.text.trim();
    final daysText = _goldenDurationController.text.trim();
    final days = daysText.isEmpty ? null : int.tryParse(daysText);
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await VipService().setCustomGoldenId(
        userId: user.userId,
        publicUserId: publicId,
        enabled: _goldenEnabled,
        durationDays: days,
        style: _goldenStyle,
        frame: _goldenFrame,
      );
      _setResult(
        _goldenEnabled
            ? (isArabic
                  ? 'ØªÙ… ØªØ­Ø¯ÙŠØ« Golden ID Ø¥Ù„Ù‰ $publicId'
                  : 'Golden ID updated to $publicId')
            : (isArabic
                  ? 'ØªÙ… Ø¥Ù„ØºØ§Ø¡ Golden ID Ù„Ù€${user.title}'
                  : 'Golden ID removed for ${user.title}'),
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('golden_id_taken')) {
        _setResult(
          isArabic
              ? 'Ù‡Ø°Ø§ Ø§Ù„Ù€ Golden ID Ù…Ø³ØªØ®Ø¯Ù… Ø¨Ø§Ù„ÙØ¹Ù„.'
              : 'This Golden ID is already used.',
          error: true,
        );
      } else if (msg.contains('invalid_golden_id_style') ||
          msg.contains('invalid_golden_id_frame')) {
        _setResult(
          isArabic ? 'Ù†Ù…Ø· Golden ID ØºÙŠØ± ØµØ§Ù„Ø­.' : 'Invalid Golden ID style.',
          error: true,
        );
      } else {
        _setResult(msg, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyCountryFlagStyle() async {
    final user = _selectedUser;
    if (user == null) {
      _setResult(
        isArabic ? 'Ø§Ø®ØªØ± Ù…Ø³ØªØ®Ø¯Ù…Ø§Ù‹ Ø£ÙˆÙ„Ø§Ù‹' : 'Select a valid user first',
        error: true,
      );
      return;
    }
    final code = _countryCodeController.text.trim();
    final name = _countryNameController.text.trim();
    final daysStr = _flagDurationController.text.trim();
    final days = daysStr.isEmpty ? null : int.tryParse(daysStr);
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await _adminService.setUserCountryFlagStyle(
        userId: user.userId,
        countryCode: code.isEmpty ? null : code,
        countryName: name.isEmpty ? null : name,
        style: _flagStyle,
        frame: _flagFrame,
        durationDays: days,
      );
      _setResult(
        isArabic
            ? 'ØªÙ… ØªØ­Ø¯ÙŠØ« Ù†Ù…Ø· Ø§Ù„Ø¹Ù„Ù… Ù„Ù€${user.title}'
            : 'Country flag style updated for ${user.title}',
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('invalid_country_code')) {
        _setResult(
          isArabic
              ? 'Ø±Ù…Ø² Ø§Ù„Ø¨Ù„Ø¯ ØºÙŠØ± ØµØ§Ù„Ø­. Ø§Ø³ØªØ®Ø¯Ù… Ø­Ø±ÙÙŠÙ† Ù…Ø«Ù„ LBØŒ AOØŒ AE.'
              : 'Invalid country code. Use two letters like LB, AO, AE.',
          error: true,
        );
      } else {
        _setResult(msg, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setResult(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _result = msg;
      _resultIsError = error;
    });
  }

  void _noUserResult() => _setResult(
    isArabic ? 'Ø§Ø®ØªØ± Ù…Ø³ØªØ®Ø¯Ù…Ø§Ù‹ Ø£ÙˆÙ„Ø§Ù‹' : 'Select a valid user first',
    error: true,
  );

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0820),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3D0C6B)),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            textDirection: dir,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kPurpleDeep.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: _kGold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isArabic ? 'Ù„ÙˆØ­Ø© Ø¥Ø¯Ø§Ø±Ø© VIP' : 'VIP Admin Panel',
                style: const TextStyle(
                  color: _kGold,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // â”€â”€ User search â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _SubLabel(
            label: isArabic
                ? 'Ø¨Ø­Ø« Ø¹Ù† Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…'
                : 'Search user by ID, Golden ID, username, or name',
            isArabic: isArabic,
          ),
          const SizedBox(height: 8),
          Row(
            textDirection: dir,
            children: [
              Expanded(
                child: _AdminField(
                  controller: _searchController,
                  label: isArabic
                      ? 'UUID Ø£Ùˆ Ù…Ø¹Ø±Ù‘Ù Ø°Ù‡Ø¨ÙŠ Ø£Ùˆ Ø§Ø³Ù… Ù…Ø³ØªØ®Ø¯Ù…'
                      : 'UUID / Golden ID / username / name',
                  isArabic: isArabic,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _searching ? null : _searchUser,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kPurpleDeep.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kCardBorder),
                  ),
                  child: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kGold,
                          ),
                        )
                      : const Icon(
                          Icons.search_rounded,
                          color: _kGold,
                          size: 18,
                        ),
                ),
              ),
              if (_selectedUser != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _clearSelection,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kRed.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: _kRed,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // â”€â”€ Search results â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...(_searchResults.map(
              (u) => _UserResultCard(
                user: u,
                isArabic: isArabic,
                onTap: () => _selectUser(u),
              ),
            )),
          ],

          // â”€â”€ Selected user â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_selectedUser != null) ...[
            const SizedBox(height: 8),
            _SelectedUserCard(user: _selectedUser!, isArabic: isArabic),
          ],

          const SizedBox(height: 16),
          Divider(color: _kCardBorder, height: 1),
          const SizedBox(height: 16),

          // â”€â”€ Grant / Revoke â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _SubLabel(
            label: isArabic ? 'Ù…Ù†Ø­ / Ø¥Ù„ØºØ§Ø¡ VIP' : 'Grant / Revoke VIP',
            isArabic: isArabic,
          ),
          const SizedBox(height: 8),

          Row(
            textDirection: dir,
            children: [
              Text(
                isArabic ? 'Ø§Ù„Ù…Ø³ØªÙˆÙ‰:' : 'Level:',
                style: const TextStyle(color: _kText, fontSize: 13),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 9,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final lvl = i + 1;
                      final sel = lvl == _grantLevel;
                      return GestureDetector(
                        onTap: () => setState(() => _grantLevel = lvl),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 34,
                          decoration: BoxDecoration(
                            color: sel ? _kGold : _kCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sel ? _kGold : _kCardBorder,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$lvl',
                              style: TextStyle(
                                color: sel ? Colors.black : _kSubtext,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          _AdminField(
            controller: _durationController,
            label: isArabic ? 'Ø§Ù„Ù…Ø¯Ø© (Ø£ÙŠØ§Ù…)' : 'Duration (days)',
            isArabic: isArabic,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),

          Row(
            textDirection: dir,
            children: [
              Expanded(
                child: _AdminButton(
                  label: isArabic ? 'Ù…Ù†Ø­ VIP' : 'Grant VIP',
                  color: _hasUser ? _kGreen : _kSubtext,
                  icon: Icons.workspace_premium_rounded,
                  busy: _busy,
                  onTap: _hasUser ? _grantVip : _noUserResult,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AdminButton(
                  label: isArabic ? 'Ø¥Ù„ØºØ§Ø¡ VIP' : 'Revoke VIP',
                  color: _hasUser ? _kRed : _kSubtext,
                  icon: Icons.remove_circle_outline_rounded,
                  busy: _busy,
                  onTap: _hasUser ? _revokeVip : _noUserResult,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Divider(color: _kCardBorder, height: 1),
          const SizedBox(height: 16),

          // â”€â”€ Golden ID â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _SubLabel(label: 'Golden ID', isArabic: isArabic),
          const SizedBox(height: 8),

          // Enable switch + duration
          Row(
            textDirection: dir,
            children: [
              Text(
                isArabic ? 'ØªÙØ¹ÙŠÙ„' : 'Enable',
                style: const TextStyle(color: _kText, fontSize: 13),
              ),
              Switch(
                value: _goldenEnabled,
                onChanged: (v) => setState(() => _goldenEnabled = v),
                activeThumbColor: _kGold,
                inactiveTrackColor: _kCardBorder,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AdminField(
                  controller: _goldenDurationController,
                  label: isArabic
                      ? 'Ø£ÙŠØ§Ù… (ÙØ§Ø±Øº = Ø¯Ø§Ø¦Ù…)'
                      : 'Days (blank = permanent)',
                  isArabic: isArabic,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          if (_goldenEnabled) ...[
            const SizedBox(height: 8),
            // Golden ID number field
            _AdminField(
              controller: _goldenIdController,
              label: isArabic
                  ? 'Ø±Ù‚Ù… / Ù†Øµ Ø§Ù„Ù€ Golden ID'
                  : 'Golden ID number or text',
              isArabic: isArabic,
            ),
            const SizedBox(height: 12),

            // Style selector
            _SubLabel(label: isArabic ? 'Ø§Ù„Ù†Ù…Ø·' : 'Style', isArabic: isArabic),
            const SizedBox(height: 6),
            _GoldenChipRow(
              options: const [
                'gold',
                'diamond',
                'royal',
                'neon',
                'fire',
                'purple',
              ],
              selected: _goldenStyle,
              onSelect: (v) => setState(() => _goldenStyle = v),
            ),
            const SizedBox(height: 10),

            // Frame selector
            _SubLabel(label: isArabic ? 'Ø§Ù„Ø¥Ø·Ø§Ø±' : 'Frame', isArabic: isArabic),
            const SizedBox(height: 6),
            _GoldenChipRow(
              options: const [
                'classic',
                'crown',
                'wings',
                'glow',
                'shield',
                'luxury',
              ],
              selected: _goldenFrame,
              onSelect: (v) => setState(() => _goldenFrame = v),
            ),
            const SizedBox(height: 10),
          ],

          SizedBox(
            width: double.infinity,
            child: _AdminButton(
              label: isArabic ? 'ØªØ·Ø¨ÙŠÙ‚ Golden ID' : 'Apply Golden ID',
              color: _hasUser ? _kGold : _kSubtext,
              icon: Icons.star_rounded,
              busy: _busy,
              onTap: _hasUser ? _applyGoldenId : _noUserResult,
            ),
          ),

          const SizedBox(height: 20),
          Divider(color: _kCardBorder, height: 1),
          const SizedBox(height: 16),

          // â”€â”€ Country Flag Style â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _SubLabel(
            label: isArabic ? 'Ù†Ù…Ø· Ø¹Ù„Ù… Ø§Ù„Ø¨Ù„Ø¯' : 'Country Flag Style',
            isArabic: isArabic,
          ),
          const SizedBox(height: 8),

          Row(
            textDirection: dir,
            children: [
              Expanded(
                child: _AdminField(
                  controller: _countryCodeController,
                  label: isArabic
                      ? 'Ø±Ù…Ø² Ø§Ù„Ø¨Ù„Ø¯ (LBØŒ AOØŒ AE)'
                      : 'Country code (LB, AO, AE)',
                  isArabic: isArabic,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AdminField(
                  controller: _countryNameController,
                  label: isArabic ? 'Ø§Ø³Ù… Ø§Ù„Ø¨Ù„Ø¯' : 'Country name',
                  isArabic: isArabic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AdminField(
            controller: _flagDurationController,
            label: isArabic ? 'Ø£ÙŠØ§Ù… (ÙØ§Ø±Øº = Ø¯Ø§Ø¦Ù…)' : 'Days (blank = permanent)',
            isArabic: isArabic,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 10),

          _SubLabel(label: isArabic ? 'Ø§Ù„Ù†Ù…Ø·' : 'Style', isArabic: isArabic),
          const SizedBox(height: 6),
          _GoldenChipRow(
            options: const [
              'normal',
              'gold',
              'diamond',
              'royal',
              'neon',
              'fire',
              'purple',
            ],
            selected: _flagStyle,
            onSelect: (v) => setState(() => _flagStyle = v),
          ),
          const SizedBox(height: 10),

          _SubLabel(label: isArabic ? 'Ø§Ù„Ø¥Ø·Ø§Ø±' : 'Frame', isArabic: isArabic),
          const SizedBox(height: 6),
          _GoldenChipRow(
            options: const ['classic', 'crown', 'glow', 'shield', 'luxury'],
            selected: _flagFrame,
            onSelect: (v) => setState(() => _flagFrame = v),
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: _AdminButton(
              label: isArabic ? 'ØªØ·Ø¨ÙŠÙ‚ Ù†Ù…Ø· Ø§Ù„Ø¹Ù„Ù…' : 'Apply Country Flag Style',
              color: _hasUser ? const Color(0xFF4DB6AC) : _kSubtext,
              icon: Icons.flag_rounded,
              busy: _busy,
              onTap: _hasUser ? _applyCountryFlagStyle : _noUserResult,
            ),
          ),

          // â”€â”€ Result banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_result != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_resultIsError ? _kRed : _kGreen).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_resultIsError ? _kRed : _kGreen).withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Text(
                _result!,
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  color: _resultIsError ? _kRed : _kGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// â”€â”€ Search result card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _UserResultCard extends StatelessWidget {
  const _UserResultCard({
    required this.user,
    required this.isArabic,
    required this.onTap,
  });
  final AdminUserSummary user;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kCardBorder),
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _kPurpleDeep,
              backgroundImage: user.avatarUrl != null
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
                  ? const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 18,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    user.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (user.publicUserId != null || user.username != null)
                    Text(
                      [
                        if (user.publicUserId != null)
                          'ID: ${user.publicUserId}',
                        if (user.username != null) '@${user.username}',
                      ].join('  '),
                      style: const TextStyle(color: _kSubtext, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (user.countryCode != null || user.country != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: PremiumCountryFlag(
                  countryCode: user.countryCode,
                  countryName: user.country,
                  style: user.countryFlagStyle,
                  frame: user.countryFlagFrame,
                  compact: true,
                ),
              ),
            if (user.vipLevel > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kGold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'VIP ${user.vipLevel}',
                  style: const TextStyle(
                    color: _kGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: _kSubtext, size: 16),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Selected user card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SelectedUserCard extends StatelessWidget {
  const _SelectedUserCard({required this.user, required this.isArabic});
  final AdminUserSummary user;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kGold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGold.withValues(alpha: 0.5)),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _kPurpleDeep,
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Row(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: _kGreen,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        user.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.vipLevel > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _kGold.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'VIP ${user.vipLevel}',
                          style: const TextStyle(
                            color: _kGold,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (user.publicUserId != null || user.username != null)
                  Text(
                    [
                      if (user.publicUserId != null) 'ID: ${user.publicUserId}',
                      if (user.username != null) '@${user.username}',
                    ].join('  '),
                    style: const TextStyle(color: _kSubtext, fontSize: 11),
                  ),
                if (user.countryCode != null || user.country != null) ...[
                  const SizedBox(height: 4),
                  PremiumCountryFlag(
                    countryCode: user.countryCode,
                    countryName: user.country,
                    style: user.countryFlagStyle,
                    frame: user.countryFlagFrame,
                    compact: true,
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

// â”€â”€ Admin panel helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Horizontal scrolling row of option chips (used for style and frame selectors).
class _GoldenChipRow extends StatelessWidget {
  const _GoldenChipRow({
    required this.options,
    required this.selected,
    required this.onSelect,
  });
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  static const _styleColors = <String, Color>{
    'normal': Color(0xFF9E9E9E),
    'gold': Color(0xFFF0C15A),
    'diamond': Color(0xFF8ECFEE),
    'royal': Color(0xFFAB6FE8),
    'neon': Color(0xFF00FFCC),
    'fire': Color(0xFFFF6A00),
    'purple': Color(0xFF8B5CF6),
    'classic': Color(0xFFF0C15A),
    'crown': Color(0xFFFFC107),
    'wings': Color(0xFF64B5F6),
    'glow': Color(0xFFE040FB),
    'shield': Color(0xFF66BB6A),
    'luxury': Color(0xFFFFD700),
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final opt = options[i];
          final sel = opt == selected;
          final color = _styleColors[opt] ?? _kGold;
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: sel ? color.withValues(alpha: 0.2) : _kCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sel ? color : _kCardBorder,
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  opt,
                  style: TextStyle(
                    color: sel ? color : _kSubtext,
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel({required this.label, required this.isArabic});
  final String label;
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Align(
    alignment: isArabic ? Alignment.centerRight : Alignment.centerLeft,
    child: Text(
      label,
      style: const TextStyle(
        color: _kText,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _AdminField extends StatelessWidget {
  const _AdminField({
    required this.controller,
    required this.label,
    required this.isArabic,
    this.keyboardType,
    this.inputFormatters,
  });
  final TextEditingController controller;
  final String label;
  final bool isArabic;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kSubtext, fontSize: 12),
        filled: true,
        fillColor: _kCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGold),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }
}

class _AdminButton extends StatelessWidget {
  const _AdminButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.busy,
    required this.onTap,
  });
  final String label;
  final Color color;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: busy
            ? Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: color,
                    strokeWidth: 2,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// VIP Center 2.0 â€” Phase V1 presentational widgets (Srood VIP Prestige)
// English-only. No new assets. No backend calls.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _Vip2Crest extends StatelessWidget {
  const _Vip2Crest({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final shown = level <= 0 ? 1 : level;
    return Column(
      children: [
        SizedBox(
          height: 152,
          width: 152,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0x66F7E2A0),
                      Color(0x338B5BD6),
                      Color(0x00000000),
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              // VIP hero/logo asset for this tier. Falls back to the stylized
              // plaque if the asset is missing so the screen never breaks.
              Image.asset(
                VipAssets.hero(shown),
                height: 148,
                width: 148,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => _fallbackPlaque(shown),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Clean tier title â€” supports the hero image without competing with it.
        Text(
          'VIP $shown',
          style: const TextStyle(
            color: _v2Gold,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // Stylized plaque used when a tier's hero.webp asset is unavailable.
  Widget _fallbackPlaque(int shown) => Stack(
    alignment: Alignment.center,
    children: [
      const Positioned(
        top: 4,
        child: Icon(
          Icons.workspace_premium_rounded,
          color: _v2Gold,
          size: 36,
        ),
      ),
      Positioned(
        top: 32,
        child: Container(
          width: 98,
          height: 104,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4A2F92), Color(0xFF160E38)],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
              bottom: Radius.circular(46),
            ),
            border: Border.all(color: _v2GoldDim, width: 1.6),
            boxShadow: [
              BoxShadow(
                color: _v2GoldDim.withValues(alpha: 0.30),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'VIP',
                style: TextStyle(
                  color: Color(0xFFFFF6D4),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  height: 1.1,
                ),
              ),
              Text(
                '$shown',
                style: const TextStyle(
                  color: _v2Gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

enum _Vip2OwnState { owned, active, locked }

// Small status pill shown under the main crest (lock when previewing a tier the
// user has not reached, otherwise an owned/active indicator).
class _Vip2LockPill extends StatelessWidget {
  const _Vip2LockPill({required this.state});
  final _Vip2OwnState state;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String label;
    switch (state) {
      case _Vip2OwnState.active:
        icon = Icons.verified_rounded;
        color = _v2Gold;
        label = 'Active';
        break;
      case _Vip2OwnState.owned:
        icon = Icons.check_circle_rounded;
        color = _v2Green;
        label = 'Owned';
        break;
      case _Vip2OwnState.locked:
        icon = Icons.lock_rounded;
        color = _v2Sub;
        label = 'Locked';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Swipeable VIP 1..9 carousel. The centered page is large; neighbours scale
// down and dim. Swiping or tapping a node selects that tier (onSelect), which
// drives the whole screen. State per node derives from ownedLevel.
class _Vip2Rail extends StatefulWidget {
  const _Vip2Rail({
    required this.selectedLevel,
    required this.ownedLevel,
    required this.onSelect,
  });
  final int selectedLevel;
  final int ownedLevel;
  final ValueChanged<int> onSelect;

  @override
  State<_Vip2Rail> createState() => _Vip2RailState();
}

class _Vip2RailState extends State<_Vip2Rail> {
  late PageController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController(
      viewportFraction: 0.30,
      initialPage: (widget.selectedLevel - 1).clamp(0, 8),
    );
  }

  @override
  void didUpdateWidget(covariant _Vip2Rail old) {
    super.didUpdateWidget(old);
    // Keep the carousel in sync if selection changed elsewhere (e.g. node tap).
    if (widget.selectedLevel != old.selectedLevel && _ctrl.hasClients) {
      final target = (widget.selectedLevel - 1).clamp(0, 8);
      final current = (_ctrl.page ?? _ctrl.initialPage.toDouble()).round();
      if (current != target) {
        _ctrl.animateToPage(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 126,
      child: Stack(
        children: [
          // Curved arc behind the level nodes.
          const Positioned.fill(child: CustomPaint(painter: _Vip2ArcPainter())),
          PageView.builder(
            controller: _ctrl,
            itemCount: 9,
            onPageChanged: (i) => widget.onSelect(i + 1),
            itemBuilder: (_, i) {
              final level = i + 1;
              return AnimatedBuilder(
                animation: _ctrl,
                builder: (_, _) {
                  final page = _ctrl.hasClients && _ctrl.page != null
                      ? _ctrl.page!
                      : (widget.selectedLevel - 1).toDouble();
                  final dist = (page - i).abs().clamp(0.0, 1.0);
                  final scale = 1.0 - dist * 0.30;
                  final opacity = 1.0 - dist * 0.45;
                  return Center(
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(scale: scale, child: _node(level)),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _node(int level) {
    final owned = widget.ownedLevel;
    final isSel = level == widget.selectedLevel;
    final isOwned = owned > 0 && level <= owned;

    final border = isSel
        ? _v2Gold
        : isOwned
        ? _v2GoldDim
        : const Color(0x73E8C25A);
    final labelColor = isSel
        ? _v2Gold
        : isOwned
        ? _v2Green
        : _v2Sub;
    final stateText = isOwned ? 'owned' : 'locked';

    final Widget inner = isOwned
        ? const Icon(Icons.check_rounded, color: _v2Green, size: 20)
        : Text(
            '$level',
            style: TextStyle(
              color: isSel ? const Color(0xFFFFF6D4) : _v2Sub,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          );

    // Per-tier calibration so the node disc sits inside this frame's opening,
    // matching the profile avatar composition.
    final frameLayout = VipFrameLayout.of(level);
    const frameBox = 66.0;
    final discSize = frameBox * frameLayout.avatarFillRatio;
    final discDy = frameBox * frameLayout.avatarDyFraction;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (level != widget.selectedLevel && _ctrl.hasClients) {
          _ctrl.animateToPage(
            level - 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar-style node with the tier's VIP frame asset overlaid on top.
          // The inner disc is sized/centred per VipFrameLayout so the frame
          // wraps it cleanly, the same way the profile avatar is composed.
          SizedBox(
            width: frameBox,
            height: frameBox,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: Offset(0, discDy),
                  child: Container(
                    width: discSize,
                    height: discSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSel
                          ? const Color(0xFF2E1D66)
                          : const Color(0x14FFFFFF),
                      border: Border.all(
                        color: border,
                        width: isSel ? 2.4 : 1.4,
                      ),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: _v2Gold.withValues(alpha: 0.38),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: inner,
                  ),
                ),
                // VIP frame asset for this tier. Non-interactive; hidden if the
                // asset is missing so the node still renders cleanly.
                IgnorePointer(
                  child: Image.asset(
                    VipAssets.frame(level),
                    width: frameBox,
                    height: frameBox,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'VIP $level',
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(stateText, style: TextStyle(color: labelColor, fontSize: 9.5)),
        ],
      ),
    );
  }
}

// Shallow upward arc drawn behind the carousel nodes for a premium "path" feel.
class _Vip2ArcPainter extends CustomPainter {
  const _Vip2ArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33E8C25A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final y = size.height * 0.42;
    final path = Path()
      ..moveTo(0, y)
      ..quadraticBezierTo(size.width / 2, y - 28, size.width, y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _Vip2ArcPainter oldDelegate) => false;
}

class _Vip2Pill extends StatelessWidget {
  const _Vip2Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0x8C422C80), Color(0xB3120A2C)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _v2GoldDim.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.diamond_outlined, color: Color(0xFF8FC4F2), size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFE4DAFB),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Vip2RechargeCard extends StatelessWidget {
  const _Vip2RechargeCard({
    required this.monthText,
    required this.progress,
    required this.buttonLabel,
    required this.hint,
    required this.onUpgrade,
  });
  final String monthText;
  final double progress;
  final String buttonLabel;
  final String hint;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x66563AA4), Color(0xB3120A2C)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _v2GoldDim.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row — small label + small leading icon (no giant circle).
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: _v2Gold, size: 15),
              const SizedBox(width: 6),
              const Text(
                "This month's recharge",
                style: TextStyle(
                  color: _v2Lilac,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress number — medium.
          Text(
            monthText,
            style: const TextStyle(
              color: _v2Gold,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          // Thin gold progress bar.
          LayoutBuilder(
            builder: (_, c) => Stack(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Container(
                  height: 6,
                  width: c.maxWidth * progress.clamp(0.03, 1.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF6D4), Color(0xFFE8C25A)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Gold button — slightly shorter.
          GestureDetector(
            onTap: onUpgrade,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF1C9), Color(0xFFEDC25C), Color(0xFFD9A93C)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  color: Color(0xFF3A1F02),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Small helper message.
          Text(
            hint,
            style: const TextStyle(
              color: _v2Lilac,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Vip2SectionDivider extends StatelessWidget {
  const _Vip2SectionDivider({required this.label, required this.counter});
  final String label;
  final String counter;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Divider(color: Color(0x59E8C25A), thickness: 1, endIndent: 10),
      ),
      const Icon(Icons.diamond_outlined, color: _v2Gold, size: 16),
      const SizedBox(width: 7),
      Text(
        label,
        style: const TextStyle(
          color: _v2Gold,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(width: 7),
      Text(counter, style: const TextStyle(color: _v2Sub, fontSize: 13)),
      const Expanded(
        child: Divider(color: Color(0x59E8C25A), thickness: 1, indent: 10),
      ),
    ],
  );
}

// Icon for a VIP privilege key (shared mapping for the perk grid).
IconData _vip2PerkIcon(VipPrivilegeKey key) {
  switch (key) {
    case VipPrivilegeKey.profileGlow:
      return Icons.flare_rounded;
    case VipPrivilegeKey.vipBadge:
      return Icons.verified_rounded;
    case VipPrivilegeKey.vipFrame:
      return Icons.crop_portrait_rounded;
    case VipPrivilegeKey.micWave:
      return Icons.graphic_eq_rounded;
    case VipPrivilegeKey.entranceEffect:
      return Icons.auto_awesome_rounded;
    case VipPrivilegeKey.kickProtection:
      return Icons.shield_outlined;
    case VipPrivilegeKey.kickConfirmation:
      return Icons.gavel_rounded;
    case VipPrivilegeKey.strongAntiKick:
      return Icons.shield_rounded;
    case VipPrivilegeKey.notBeingFollowed:
      return Icons.person_off_rounded;
    case VipPrivilegeKey.antiEnteringRoom:
      return Icons.meeting_room_rounded;
    case VipPrivilegeKey.privateBrowsing:
      return Icons.visibility_off_rounded;
    case VipPrivilegeKey.doNotDisturb:
      return Icons.notifications_off_rounded;
    case VipPrivilegeKey.antiKick:
      return Icons.block_rounded;
    case VipPrivilegeKey.invisibility:
      return Icons.blur_on_rounded;
    case VipPrivilegeKey.sendRoomChatImage:
      return Icons.image_rounded;
    case VipPrivilegeKey.silentEntry:
      return Icons.volume_off_rounded;
  }
}

class _Vip2PerkGrid extends StatelessWidget {
  const _Vip2PerkGrid({required this.selectedLevel});
  final int selectedLevel;

  @override
  Widget build(BuildContext context) {
    // Real privilege data: what the SELECTED tier grants vs what is still
    // locked at that tier. No fabricated ownership.
    final isArabic = context.isArabic;
    final unlocked = VipPrivileges.unlockedFor(selectedLevel);
    final locked = VipPrivileges.lockedFor(selectedLevel);
    final items = <(VipPrivilegeSpec, bool)>[
      for (final s in unlocked) (s, true),
      for (final s in locked) (s, false),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 13,
      crossAxisSpacing: 13,
      childAspectRatio: 1.25,
      children: [
        for (final it in items)
          _Vip2PerkCard(
            icon: _vip2PerkIcon(it.$1.key),
            label: isArabic ? it.$1.labelAr : it.$1.label,
            unlocked: it.$2,
          ),
      ],
    );
  }
}

class _Vip2PerkCard extends StatelessWidget {
  const _Vip2PerkCard({
    required this.icon,
    required this.label,
    required this.unlocked,
  });
  final IconData icon;
  final String label;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final tint = unlocked ? _v2Gold : _v2Sub;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: unlocked
              ? const [Color(0x664A2F92), Color(0xCC140B36)]
              : const [Color(0x33281E4C), Color(0xB30E0922)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? _v2GoldDim.withValues(alpha: 0.6)
              : const Color(0x24C9D2E3),
        ),
        boxShadow: unlocked
            ? [
                BoxShadow(
                  color: _v2GoldDim.withValues(alpha: 0.12),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 52,
            width: double.infinity,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0x0DFFFFFF),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: unlocked
                            ? _v2Gold.withValues(alpha: 0.55)
                            : const Color(0x29C9D2E3),
                      ),
                    ),
                    child: Icon(icon, color: tint, size: 25),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: unlocked
                      ? Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1A3A2C),
                            border: Border.all(
                              color: _v2Green.withValues(alpha: 0.55),
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: _v2Green,
                            size: 12,
                          ),
                        )
                      : const Icon(Icons.lock_rounded, color: _v2Sub, size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unlocked ? const Color(0xFFF6F1FF) : _v2Sub,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

