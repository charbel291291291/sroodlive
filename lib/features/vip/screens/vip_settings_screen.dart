import 'package:flutter/material.dart';

import '../../../core/vip/vip_privileges.dart';
import '../../../shared/theme/vip_tier_colors.dart';
import '../../../shared/widgets/vip_badge.dart';
import '../../../shared/widgets/vip_tier_chip.dart';
import '../services/vip_privilege_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// ---------------------------------------------------------------------------
// Palette (local — keeps the premium dark Srood style)
// ---------------------------------------------------------------------------

const _kBg    = Color(0xFF0D0D1A);
const _kCard  = Color(0xFF12091D);
const _kGreen = Color(0xFF22C55E);

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
  bool _saving  = false;
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
        _loading  = false;
      });
    }
  }

  // ── Toggle — behavior UNCHANGED ──────────────────────────────────────────
  Future<void> _toggle(VipPrivilege privilege, bool newValue) async {
    final oldValue = _settings[privilege] ?? false;
    final canUse   = VipPrivileges.canUse(
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

  // ── Snackbars — behavior UNCHANGED ───────────────────────────────────────
  void _showLockedSnack(VipPrivilege privilege) {
    final minLevel = privilege.minVipLevel;
    final style    = VipTierColors.of(minLevel);
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
                  'متاحة من VIP$minLevel فما فوق',
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
    final msg   = enabled
        ? _t('تم تفعيل $label', '$label enabled')
        : _t('تم إيقاف $label', '$label disabled');

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF22C55E), size: 16),
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
                color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
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
              const Icon(Icons.error_rounded,
                  color: Color(0xFFEF4444), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(
                    'حدث خطأ، يرجى المحاولة مجدداً',
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
                color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  // ── Icon mapping ──────────────────────────────────────────────────────────
  static const _privilegeIcons = <VipPrivilege, IconData>{
    VipPrivilege.notBeingFollowed: Icons.person_off_rounded,
    VipPrivilege.antiEnteringRoom: Icons.meeting_room_rounded,
    VipPrivilege.privateBrowsing:  Icons.visibility_off_rounded,
    VipPrivilege.doNotDisturb:     Icons.notifications_off_rounded,
    VipPrivilege.invisibility:     Icons.blur_on_rounded,
    VipPrivilege.antiKick:         Icons.shield_rounded,
  };

  List<Widget> _buildPrivilegeCards(bool isArabic) {
    final cards = <Widget>[];
    for (final privilege in VipPrivilege.values) {
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 10));
      final pSpec = VipPrivileges.spec(privilege.privilegeKey);
      cards.add(
        _PrivilegeCard(
          privilege:   privilege,
          label:       isArabic ? pSpec.labelAr       : pSpec.label,
          description: isArabic ? pSpec.descriptionAr : pSpec.description,
          icon:        _privilegeIcons[privilege] ?? Icons.lock_rounded,
          isEnabled:   _settings[privilege] ?? false,
          userVipLevel: widget.effectiveVipLevel,
          isArabic:    isArabic,
          onChanged:   (v) => _toggle(privilege, v),
        ),
      );
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final isArabic  = context.isArabic;
    final hasVip    = widget.effectiveVipLevel > 0;
    final tierStyle = hasVip ? VipTierColors.of(widget.effectiveVipLevel) : null;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kBg,
          elevation: 0,
          centerTitle: true,
          title: Text(
            _t('إعدادات VIP', 'VIP Settings'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            if (_saving)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tierStyle?.border ?? const Color(0xFFF0C15A),
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: tierStyle?.border ?? const Color(0xFFF0C15A),
                ),
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
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: _SettingsSectionHeader(
                        isArabic: isArabic,
                        vipLevel: widget.effectiveVipLevel,
                        totalCards: VipPrivilege.values.length,
                        unlockedCards: VipPrivilege.values
                            .where((p) => VipPrivileges.canUse(
                                  widget.effectiveVipLevel,
                                  p.privilegeKey,
                                ))
                            .length,
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
// VIP level banner — tier-tinted header
// ---------------------------------------------------------------------------

class _VipLevelBanner extends StatelessWidget {
  const _VipLevelBanner({required this.vipLevel, required this.isArabic});

  final int vipLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final hasVip    = vipLevel > 0;
    final tierStyle = hasVip ? VipTierColors.of(vipLevel) : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: tierStyle != null
              ? [
                  tierStyle.start.withValues(alpha: 0.22),
                  tierStyle.end.withValues(alpha: 0.08),
                  _kCard,
                ]
              : [const Color(0xFF1A0D33), const Color(0xFF12091D)],
          stops: tierStyle != null ? const [0.0, 0.5, 1.0] : null,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: tierStyle != null
              ? tierStyle.border.withValues(alpha: 0.40)
              : Colors.white.withValues(alpha: 0.08),
          width: hasVip ? 1.3 : 1,
        ),
        boxShadow: hasVip
            ? [
                BoxShadow(
                  color: tierStyle!.shadow,
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Badge / no-VIP chip
          if (hasVip)
            VipBadge(vipLevel: vipLevel, compact: false)
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                isArabic ? 'بدون VIP' : 'No VIP',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
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
                  hasVip
                      ? (isArabic
                          ? 'فعّل أو أوقف مزاياك'
                          : 'Manage your VIP privileges')
                      : (isArabic
                          ? 'احصل على VIP لتفعيل المزايا'
                          : 'Get VIP to unlock privileges'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasVip
                      ? (isArabic
                          ? 'التغييرات تُطبَّق فوراً'
                          : 'Changes apply immediately')
                      : (isArabic
                          ? 'تواصل مع الإدارة للحصول على VIP'
                          : 'Contact admin to get VIP'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.4,
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

// ---------------------------------------------------------------------------
// Settings section header — unlocked / total counter
// ---------------------------------------------------------------------------

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.isArabic,
    required this.vipLevel,
    required this.totalCards,
    required this.unlockedCards,
  });

  final bool isArabic;
  final int vipLevel;
  final int totalCards;
  final int unlockedCards;

  @override
  Widget build(BuildContext context) {
    final hasVip    = vipLevel > 0;
    final tierStyle = hasVip ? VipTierColors.of(vipLevel) : null;
    final accent    = tierStyle?.border ?? Colors.white54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Icon(Icons.tune_rounded, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            isArabic ? 'مزايا قابلة للتفعيل' : 'Toggleable Privileges',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Text(
              '$unlockedCards / $totalCards',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
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
    final tier = VipTierColors.of(privilege.minVipLevel);

    // Colors derived from the privilege's own required VIP tier
    final iconBgColor = _unlocked
        ? tier.start.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.05);
    final iconColor = _unlocked ? tier.border : Colors.white38;

    final cardBg = _unlocked && isEnabled
        ? tier.start.withValues(alpha: 0.10)
        : _kCard;
    final cardBorder = _unlocked && isEnabled
        ? tier.border.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.07);

    final switchTrackColor = tier.start;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cardBg,
        border: Border.all(color: cardBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _unlocked ? () => onChanged(!isEnabled) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Tier-colored icon container
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 12),

                // Label + description + requirement pill
                Expanded(
                  child: Column(
                    crossAxisAlignment: isArabic
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color:
                              _unlocked ? Colors.white : Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          color: _unlocked
                              ? Colors.white.withValues(alpha: 0.50)
                              : Colors.white.withValues(alpha: 0.25),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _VipRequirementPill(
                        minLevel: privilege.minVipLevel,
                        userVipLevel: userVipLevel,
                        isArabic: isArabic,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Right side: toggle or lock icon
                if (_unlocked)
                  Switch(
                    value: isEnabled,
                    onChanged: onChanged,
                    activeThumbColor: Colors.white,
                    activeTrackColor: switchTrackColor,
                    inactiveThumbColor: Colors.white38,
                    inactiveTrackColor:
                        Colors.white.withValues(alpha: 0.10),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                else
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        color: Colors.white24, size: 16),
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
// VIP requirement pill — tier chip for locked, green check for unlocked
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
          const Icon(Icons.check_circle_rounded,
              size: 12, color: _kGreen),
          const SizedBox(width: 4),
          Text(
            isArabic ? 'متاحة' : 'Unlocked',
            style: const TextStyle(
              color: _kGreen,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    // Locked: "Requires" label + tier chip
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isArabic ? 'يتطلب ' : 'Requires ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        VipTierChip(level: minLevel, compact: true),
        Text(
          '+',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
