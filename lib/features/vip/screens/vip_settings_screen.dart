import 'package:flutter/material.dart';

import '../../../core/vip/vip_privileges.dart';
import '../../../shared/theme/vip_tier_colors.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_tier_chip.dart';
import '../services/vip_privilege_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// ---------------------------------------------------------------------------
// VIP Settings Screen
// ---------------------------------------------------------------------------

class VipSettingsScreen extends StatefulWidget {
  const VipSettingsScreen({
    required this.isArabic,
    required this.effectiveVipLevel,
    super.key,
  });

  final bool isArabic;
  final int effectiveVipLevel;

  @override
  State<VipSettingsScreen> createState() => _VipSettingsScreenState();
}

class _VipSettingsScreenState extends State<VipSettingsScreen> {
  final _svc = const VipPrivilegeService();

  bool _loading = true;
  bool _saving = false;
  Map<VipPrivilege, bool> _settings = {};

  String _t(String ar, String en) => context.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _svc.loadSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(VipPrivilege privilege, bool newValue) async {
    final oldValue = _settings[privilege] ?? false;
    final canUse = VipPrivileges.canUse(
      widget.effectiveVipLevel,
      privilege.privilegeKey,
    );

    if (!canUse) {
      _showLockedSnack(privilege);
      return;
    }

    setState(() {
      _settings[privilege] = newValue;
      _saving = true;
    });

    try {
      await _svc.setSetting(
        privilege: privilege,
        enabled: newValue,
        effectiveVipLevel: widget.effectiveVipLevel,
      );
      if (mounted) _showSuccessSnack(privilege, newValue);
    } catch (e) {
      if (mounted) setState(() => _settings[privilege] = oldValue);
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showLockedSnack(VipPrivilege privilege) {
    final minLevel = privilege.minVipLevel;
    final style = VipTierColors.of(minLevel);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Text(
                _t(
                  'Ù…ØªØ§Ø­Ø© Ù…Ù† VIP$minLevel ÙÙ…Ø§ ÙÙˆÙ‚',
                  'Available from VIP$minLevel and above',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1A0D33),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: style.border.withValues(alpha: 0.6)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  void _showSuccessSnack(VipPrivilege privilege, bool enabled) {
    final pSpec = VipPrivileges.spec(privilege.privilegeKey);
    final label = context.isArabic ? pSpec.labelAr : pSpec.label;
    final msg = enabled
        ? _t('ØªÙ… ØªÙØ¹ÙŠÙ„ $label', '$label enabled')
        : _t('ØªÙ… Ø¥ÙŠÙ‚Ø§Ù $label', '$label disabled');

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22C55E),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(msg, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0D2A1A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: const Color(0xFF22C55E).withValues(alpha: 0.4),
            ),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  void _showError() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_rounded,
                color: Color(0xFFEF4444),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(
                    'Ø­Ø¯Ø« Ø®Ø·Ø£ØŒ ÙŠØ±Ø¬Ù‰ Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø© Ù…Ø¬Ø¯Ø¯Ø§Ù‹',
                    'Something went wrong. Setting reverted.',
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2A0F1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
            ),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  static const _privilegeIcons = <VipPrivilege, IconData>{
    VipPrivilege.notBeingFollowed: Icons.person_off_rounded,
    VipPrivilege.antiEnteringRoom: Icons.meeting_room_rounded,
    VipPrivilege.privateBrowsing: Icons.visibility_off_rounded,
    VipPrivilege.doNotDisturb: Icons.notifications_off_rounded,
    VipPrivilege.invisibility: Icons.blur_on_rounded,
    VipPrivilege.antiKick: Icons.shield_rounded,
  };

  List<Widget> _buildPrivilegeCards(bool isArabic) {
    final cards = <Widget>[];
    for (final privilege in VipPrivilege.values) {
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 10));
      final pSpec = VipPrivileges.spec(privilege.privilegeKey);
      cards.add(
        _PrivilegeCard(
          privilege: privilege,
          label: isArabic ? pSpec.labelAr : pSpec.label,
          description: isArabic ? pSpec.descriptionAr : pSpec.description,
          icon: _privilegeIcons[privilege] ?? Icons.lock_rounded,
          isEnabled: _settings[privilege] ?? false,
          userVipLevel: widget.effectiveVipLevel,
          isArabic: isArabic,
          onChanged: (v) => _toggle(privilege, v),
        ),
      );
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0D1A),
          elevation: 0,
          centerTitle: true,
          title: Text(
            _t('Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª VIP', 'VIP Settings'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 18,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFF0C15A),
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFF0C15A)),
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _VipLevelBanner(
                      vipLevel: widget.effectiveVipLevel,
                      isArabic: isArabic,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        _t('Ù…Ø²Ø§ÙŠØ§ VIP', 'VIP Privileges'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(
                        _buildPrivilegeCards(isArabic),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIP level banner at the top â€” tinted with real tier color
// ---------------------------------------------------------------------------

class _VipLevelBanner extends StatelessWidget {
  const _VipLevelBanner({required this.vipLevel, required this.isArabic});

  final int vipLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final hasVip = vipLevel > 0;
    final tierStyle = hasVip ? VipTierColors.of(vipLevel) : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: tierStyle != null
              ? [
                  tierStyle.start.withValues(alpha: 0.18),
                  tierStyle.end.withValues(alpha: 0.07),
                ]
              : [const Color(0xFF1A0D33), const Color(0xFF2A1547)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: tierStyle != null
              ? tierStyle.border.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          if (hasVip)
            VipBadge(vipLevel: vipLevel, compact: false)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Text(
                isArabic ? 'Ø¨Ø¯ÙˆÙ† VIP' : 'No VIP',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasVip
                  ? (isArabic
                        ? 'ÙØ¹Ù‘Ù„ Ø£Ùˆ Ø£ÙˆÙ‚Ù Ø§Ù„Ù…Ø²Ø§ÙŠØ§ Ø§Ù„Ù…ØªØ§Ø­Ø© Ù„Ù…Ø³ØªÙˆØ§Ùƒ'
                        : 'Toggle the privileges available for your VIP level')
                  : (isArabic
                        ? 'Ø§Ø­ØµÙ„ Ø¹Ù„Ù‰ VIP Ù„ØªÙØ¹ÙŠÙ„ Ø§Ù„Ù…Ø²Ø§ÙŠØ§'
                        : 'Get VIP to unlock privileges'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual privilege card
// ---------------------------------------------------------------------------

class _PrivilegeCard extends StatelessWidget {
  const _PrivilegeCard({
    required this.privilege,
    required this.label,
    required this.description,
    required this.icon,
    required this.isEnabled,
    required this.userVipLevel,
    required this.isArabic,
    required this.onChanged,
  });

  final VipPrivilege privilege;
  final String label;
  final String description;
  final IconData icon;
  final bool isEnabled;
  final int userVipLevel;
  final bool isArabic;
  final ValueChanged<bool> onChanged;

  bool get _unlocked =>
      VipPrivileges.canUse(userVipLevel, privilege.privilegeKey);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isEnabled && _unlocked
            ? const Color(0xFF0D2A3A)
            : const Color(0xFF12091D),
        border: Border.all(
          color: isEnabled && _unlocked
              ? const Color(0xFF1A8CB0).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _unlocked ? () => onChanged(!isEnabled) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon container
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _unlocked
                        ? const Color(0xFF1A5C78).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: _unlocked ? const Color(0xFF5DDCFF) : Colors.white38,
                  ),
                ),
                const SizedBox(width: 12),
                // Label + description + VIP requirement pill
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: _unlocked ? Colors.white : Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          color: _unlocked
                              ? Colors.white.withValues(alpha: 0.50)
                              : Colors.white.withValues(alpha: 0.28),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _VipRequirementPill(
                        minLevel: privilege.minVipLevel,
                        userVipLevel: userVipLevel,
                        isArabic: isArabic,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Toggle or lock icon
                if (_unlocked)
                  Switch(
                    value: isEnabled,
                    onChanged: onChanged,
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF1A8CB0),
                    inactiveThumbColor: Colors.white38,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                else
                  const Icon(
                    Icons.lock_rounded,
                    color: Colors.white24,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIP requirement pill â€” real tier color for locked, green check for unlocked
// ---------------------------------------------------------------------------

class _VipRequirementPill extends StatelessWidget {
  const _VipRequirementPill({
    required this.minLevel,
    required this.userVipLevel,
    required this.isArabic,
  });

  final int minLevel;
  final int userVipLevel;
  final bool isArabic;

  bool get _unlocked => userVipLevel >= minLevel;

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 12,
            color: Color(0xFF22C55E),
          ),
          const SizedBox(width: 4),
          Text(
            isArabic ? 'Ù…ØªØ§Ø­Ø©' : 'Unlocked',
            style: const TextStyle(
              color: Color(0xFF22C55E),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isArabic ? 'Ù…Ù† ' : 'From ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        VipTierChip(level: minLevel, compact: true),
      ],
    );
  }
}
