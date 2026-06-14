import 'package:flutter/material.dart';

import '../../../shared/widgets/vip_badge.dart';
import '../services/vip_privilege_service.dart';

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

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _svc.loadSettings();
    if (mounted) setState(() { _settings = settings; _loading = false; });
  }

  Future<void> _toggle(VipPrivilege privilege, bool newValue) async {
    final canUse = VipPrivilegeService.canUsePrivilege(
      widget.effectiveVipLevel,
      privilege,
    );

    if (!canUse) {
      _showLockedSnack(privilege);
      return;
    }

    setState(() { _settings[privilege] = newValue; _saving = true; });

    try {
      await _svc.setSetting(
        privilege: privilege,
        enabled: newValue,
        effectiveVipLevel: widget.effectiveVipLevel,
      );
    } catch (_) {
      // Revert on error.
      if (mounted) setState(() => _settings[privilege] = !newValue);
      _showError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showLockedSnack(VipPrivilege privilege) {
    final minLevel = privilege.minVipLevel;
    final msg = _t(
      'متاحة من VIP$minLevel فما فوق',
      'Available from VIP$minLevel and above',
    );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A0D33),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFF8B26D9).withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_t('حدث خطأ، يرجى المحاولة مجدداً', 'Something went wrong')),
      backgroundColor: const Color(0xFF2A0F1A),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0D1A),
          elevation: 0,
          centerTitle: true,
          title: Text(
            _t('إعدادات VIP', 'VIP Setting'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
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
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFF0C15A)))
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
                        _t('مزايا VIP', 'VIP Privilege'),
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
                      delegate: SliverChildListDelegate([
                        _PrivilegeCard(
                          privilege: VipPrivilege.notBeingFollowed,
                          label: _t('منع المتابعة', 'Not being Followed'),
                          icon: Icons.person_off_rounded,
                          isEnabled: _settings[VipPrivilege.notBeingFollowed] ?? false,
                          userVipLevel: widget.effectiveVipLevel,
                          isArabic: isArabic,
                          onChanged: (v) => _toggle(VipPrivilege.notBeingFollowed, v),
                        ),
                        const SizedBox(height: 10),
                        _PrivilegeCard(
                          privilege: VipPrivilege.antiEnteringRoom,
                          label: _t('منع دخول الغرفة', 'Anti-Entering Room'),
                          icon: Icons.meeting_room_rounded,
                          isEnabled: _settings[VipPrivilege.antiEnteringRoom] ?? false,
                          userVipLevel: widget.effectiveVipLevel,
                          isArabic: isArabic,
                          onChanged: (v) => _toggle(VipPrivilege.antiEnteringRoom, v),
                        ),
                        const SizedBox(height: 10),
                        _PrivilegeCard(
                          privilege: VipPrivilege.privateBrowsing,
                          label: _t('التصفح الخاص', 'Private Browsing'),
                          icon: Icons.visibility_off_rounded,
                          isEnabled: _settings[VipPrivilege.privateBrowsing] ?? false,
                          userVipLevel: widget.effectiveVipLevel,
                          isArabic: isArabic,
                          onChanged: (v) => _toggle(VipPrivilege.privateBrowsing, v),
                        ),
                        const SizedBox(height: 10),
                        _PrivilegeCard(
                          privilege: VipPrivilege.doNotDisturb,
                          label: _t('عدم الإزعاج', 'Do Not Disturb'),
                          icon: Icons.notifications_off_rounded,
                          isEnabled: _settings[VipPrivilege.doNotDisturb] ?? false,
                          userVipLevel: widget.effectiveVipLevel,
                          isArabic: isArabic,
                          onChanged: (v) => _toggle(VipPrivilege.doNotDisturb, v),
                        ),
                        const SizedBox(height: 10),
                        _PrivilegeCard(
                          privilege: VipPrivilege.invisibility,
                          label: _t('التخفي', 'Invisibility'),
                          icon: Icons.blur_on_rounded,
                          isEnabled: _settings[VipPrivilege.invisibility] ?? false,
                          userVipLevel: widget.effectiveVipLevel,
                          isArabic: isArabic,
                          onChanged: (v) => _toggle(VipPrivilege.invisibility, v),
                        ),
                        const SizedBox(height: 10),
                        _PrivilegeCard(
                          privilege: VipPrivilege.antiKick,
                          label: _t('منع الطرد', 'Anti-Kick'),
                          icon: Icons.shield_rounded,
                          isEnabled: _settings[VipPrivilege.antiKick] ?? false,
                          userVipLevel: widget.effectiveVipLevel,
                          isArabic: isArabic,
                          onChanged: (v) => _toggle(VipPrivilege.antiKick, v),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIP level banner at the top
// ---------------------------------------------------------------------------

class _VipLevelBanner extends StatelessWidget {
  const _VipLevelBanner({required this.vipLevel, required this.isArabic});

  final int vipLevel;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final hasVip = vipLevel > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0D33), Color(0xFF2A1547)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: hasVip
              ? const Color(0xFFF0C15A).withValues(alpha: 0.4)
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
                isArabic ? 'بدون VIP' : 'No VIP',
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
                      ? 'يمكنك تفعيل المزايا المتاحة لمستواك'
                      : 'Enable privileges available for your level')
                  : (isArabic
                      ? 'احصل على VIP لتفعيل المزايا'
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
    required this.icon,
    required this.isEnabled,
    required this.userVipLevel,
    required this.isArabic,
    required this.onChanged,
  });

  final VipPrivilege privilege;
  final String label;
  final IconData icon;
  final bool isEnabled;
  final int userVipLevel;
  final bool isArabic;
  final ValueChanged<bool> onChanged;

  bool get _unlocked =>
      VipPrivilegeService.canUsePrivilege(userVipLevel, privilege);

  @override
  Widget build(BuildContext context) {
    final minLevel = privilege.minVipLevel;

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
                // Icon
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
                    color: _unlocked
                        ? const Color(0xFF5DDCFF)
                        : Colors.white38,
                  ),
                ),
                const SizedBox(width: 12),
                // Label + VIP badges
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
                      const SizedBox(height: 6),
                      _VipRequirementBadges(
                        minLevel: minLevel,
                        userVipLevel: userVipLevel,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Toggle or lock
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
                  const Icon(Icons.lock_rounded, color: Colors.white24, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row of small VIP level badges showing requirement
// ---------------------------------------------------------------------------

class _VipRequirementBadges extends StatelessWidget {
  const _VipRequirementBadges({
    required this.minLevel,
    required this.userVipLevel,
  });

  final int minLevel;
  final int userVipLevel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(9 - minLevel + 1, (i) {
        final level = minLevel + i;
        final owned = userVipLevel >= level;
        return _SmallVipBadge(level: level, owned: owned);
      }),
    );
  }
}

class _SmallVipBadge extends StatelessWidget {
  const _SmallVipBadge({required this.level, required this.owned});

  final int level;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: owned
            ? const LinearGradient(
                colors: [Color(0xFFF0C15A), Color(0xFFD99A2B)],
              )
            : null,
        color: owned ? null : Colors.white.withValues(alpha: 0.07),
        border: Border.all(
          color: owned
              ? const Color(0xFFF0C15A).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        'VIP$level',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: owned ? Colors.black87 : Colors.white38,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
