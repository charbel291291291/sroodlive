import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/vip/vip_privileges.dart';
import '../../../core/vip/vip_spec.dart';
import '../../../features/admin/services/admin_access_service.dart';
import '../../../shared/theme/vip_tier_colors.dart';
import '../../../shared/widgets/vip_framed_avatar.dart';
import '../../vip/models/user_vip.dart';
import '../../vip/screens/vip_settings_screen.dart';
import '../../vip/services/vip_service.dart';
import '../services/gamification_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// ── Palette ───────────────────────────────────────────────────────────────────

const _kBg         = Color(0xFF07030D);
const _kCard       = Color(0xFF12091D);
const _kCardBorder = Color(0xFF2A1845);
const _kGold       = Color(0xFFF0C15A);
const _kSubtext    = Color(0xFF7A6890);
const _kText       = Color(0xFFD8CFEA);
const _kPurpleDeep = Color(0xFF4B168C);
const _kPurpleMid  = Color(0xFF8B26D9);
const _kGreen      = Color(0xFF2ECC71);
const _kRed        = Color(0xFFFF5C7A);

// ─────────────────────────────────────────────────────────────────────────────

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
        _plans   = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
      return;
    }
    // VIP EXP data is supplementary — a failure here must not block the screen.
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
              _buildHeader(),
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
          context.isArabic ? 'مركز VIP' : 'VIP Center',
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
            label: context.isArabic ? 'استكشاف مستويات VIP' : 'Explore VIP Tiers',
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
            isCurrent: _selectedTier == widget.currentVipLevel &&
                widget.currentVipLevel > 0,
          ),
          const SizedBox(height: 16),
          _BenefitsList(
            level: _selectedTier,
            isArabic: context.isArabic,
          ),
          const SizedBox(height: 20),
          _ContactAdminButton(isArabic: context.isArabic),
          if (!_adminLoading && _adminRole.hasPermission(kPermVipGrant)) ...[
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
            context.isArabic ? 'إعادة المحاولة' : 'Retry',
            style: const TextStyle(color: _kGold),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Current status card
// ─────────────────────────────────────────────────────────────────────────────

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
                  textDirection:
                      isArabic ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    if (_isActive)
                      _StatusPill(
                        label: isArabic ? 'نشط' : 'Active',
                        color: const Color(0xFF22C55E),
                      )
                    else if (_isExpired)
                      _StatusPill(
                        label: isArabic ? 'منتهي' : 'Expired',
                        color: _kRed,
                      )
                    else
                      _StatusPill(
                        label: isArabic ? 'غير مفعّل' : 'No VIP',
                        color: _kSubtext,
                      ),
                    if (_isActive && _isMax) ...[
                      const SizedBox(width: 6),
                      _StatusPill(
                        label: isArabic ? 'الحد الأقصى' : 'MAX',
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
                      : (isArabic ? 'لا يوجد VIP نشط' : 'No Active VIP'),
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
                        ? 'ينتهي: ${_fmtDate(expiresAt!)}'
                        : 'Expires: ${_fmtDate(expiresAt!)}',
                    color: _kText,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(
                    icon: Icons.timer_rounded,
                    text: isArabic
                        ? 'المتبقي: $_remainingDays يوم'
                        : 'Remaining: $_remainingDays day${_remainingDays == 1 ? '' : 's'}',
                    color: _remainingDaysColor,
                  ),
                ] else if (_isExpired && expiresAt != null)
                  _InfoRow(
                    icon: Icons.timer_off_rounded,
                    text: isArabic
                        ? 'انتهى في: ${_fmtDate(expiresAt!)}'
                        : 'Expired on: ${_fmtDate(expiresAt!)}',
                    color: _kRed,
                  )
                else if (!_hasVip)
                  _InfoRow(
                    icon: Icons.info_outline_rounded,
                    text: isArabic
                        ? 'تواصل مع الإدارة للحصول على VIP'
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

// ─────────────────────────────────────────────────────────────────────────────
// VIP Level Progress section
// ─────────────────────────────────────────────────────────────────────────────

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
    final bool hasExp = vip != null && (vip.rechargeExp > 0 || vip.vipLevel > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCardBorder),
      ),
      child: Column(
        crossAxisAlignment:
            isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(Icons.trending_up_rounded, color: _kGold, size: 16),
              const SizedBox(width: 7),
              Text(
                isArabic ? 'تقدم VIP' : 'VIP Progress',
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

          // ── 9-segment tier bar ───────────────────────────────────────────────
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

          // ── EXP stats ────────────────────────────────────────────────────────
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
            // No EXP data yet — show journey start prompt
            _ExpStatRow(
              icon: Icons.rocket_launch_rounded,
              text: vipLevel <= 0
                  ? (isArabic ? 'ابدأ رحلة VIP بالشحن' : 'Start your VIP journey by recharging')
                  : (isArabic ? 'استمر بالشحن للحفاظ على VIP' : 'Keep recharging to maintain your VIP'),
              color: _kSubtext,
              isArabic: isArabic,
            ),
          ],
        ],
      ),
    );
  }
}

// ── EXP helper widgets ────────────────────────────────────────────────────────

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
    crossAxisAlignment:
        isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      // Lifetime EXP + Monthly EXP stat row
      Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Expanded(
            child: _ExpStat(
              label: isArabic ? 'إجمالي الشحن' : 'Total Recharge EXP',
              value: fmtExp(vip.rechargeExp),
              icon: Icons.bolt_rounded,
              color: _kGold,
              isArabic: isArabic,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ExpStat(
              label: isArabic ? 'EXP هذا الشهر' : 'Monthly EXP',
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
              ? 'نحو VIP ${vipLevel + 1}'
              : 'Progress to VIP ${vipLevel + 1}',
          progress: vip.nextTierProgress ?? 0.0,
          remaining: vip.expToNextTier,
          remainingLabel: isArabic ? 'متبقي' : 'remaining',
          gradientColors: const [_kPurpleDeep, _kPurpleMid],
          isArabic: isArabic,
          fmtExp: fmtExp,
        ),
        const SizedBox(height: 10),
      ] else ...[
        _ExpStatRow(
          icon: Icons.emoji_events_rounded,
          text: isArabic
              ? 'وصلت إلى أعلى مستوى VIP!'
              : 'Maximum VIP tier reached!',
          color: _kGold,
          isArabic: isArabic,
        ),
        const SizedBox(height: 10),
      ],

      // Monthly maintain progress (VIP > 0 only)
      if (vipLevel > 0)
        _ExpProgressBar(
          label: isArabic ? 'تجديد الشهر الحالي' : 'Monthly Renewal',
          progress: vip.monthlyMaintainProgress ?? 0.0,
          remaining: vip.expToMaintain,
          remainingLabel: isArabic ? 'للتجديد' : 'to renew',
          gradientColors: vip.isMonthlyMaintainMet
              ? const [Color(0xFF16A34A), Color(0xFF22C55E)]
              : const [Color(0xFF9A3412), Color(0xFFF59E0B)],
          isArabic: isArabic,
          fmtExp: fmtExp,
          metLabel: isArabic ? 'تجديد مضمون ✓' : 'Renewal secured ✓',
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
      crossAxisAlignment:
          isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
      crossAxisAlignment:
          isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                color: isMet
                    ? const Color(0xFF22C55E)
                    : gradientColors.last,
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

// ─────────────────────────────────────────────────────────────────────────────
// VIP settings shortcut
// ─────────────────────────────────────────────────────────────────────────────

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
            const Icon(Icons.settings_rounded, color: Color(0xFF5DDCFF), size: 20),
            const SizedBox(width: 12),
            Text(
              isArabic ? 'إعدادات VIP' : 'VIP Settings',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier selector — horizontal scroll VIP 1..9 (premium tier cards)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Tier preview card
// ─────────────────────────────────────────────────────────────────────────────

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
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kGold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isArabic ? 'أنت' : 'You',
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
                      label: isArabic ? 'إطار' : 'Frame',
                      active: spec.hasFrame,
                    ),
                    _FeatureChip(
                      icon: Icons.verified_rounded,
                      label: isArabic ? 'شارة' : 'Badge',
                      active: spec.hasBadge,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  textDirection:
                      isArabic ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    _ColorDot(
                      color: spec.glowColor,
                      label: isArabic ? 'توهج' : 'Glow',
                    ),
                    const SizedBox(width: 10),
                    _ColorDot(
                      color: spec.nameColor,
                      label: isArabic ? 'اسم' : 'Name',
                    ),
                    if (spec.bannerGradient.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _ColorDot(
                        color: spec.bannerGradient.first,
                        label: isArabic ? 'لافتة' : 'Banner',
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

// ─────────────────────────────────────────────────────────────────────────────
// Benefits list
// ─────────────────────────────────────────────────────────────────────────────

class _BenefitsList extends StatelessWidget {
  const _BenefitsList({required this.level, required this.isArabic});
  final int level;
  final bool isArabic;

  // Icon mapping for known privilege keys
  static const Map<VipPrivilegeKey, IconData> _icons = {
    VipPrivilegeKey.profileGlow:       Icons.flare_rounded,
    VipPrivilegeKey.vipBadge:          Icons.verified_rounded,
    VipPrivilegeKey.vipFrame:          Icons.crop_portrait_rounded,
    VipPrivilegeKey.micWave:           Icons.graphic_eq_rounded,
    VipPrivilegeKey.entranceEffect:    Icons.auto_awesome_rounded,
    VipPrivilegeKey.kickProtection:    Icons.shield_outlined,
    VipPrivilegeKey.kickConfirmation:  Icons.gavel_rounded,
    VipPrivilegeKey.strongAntiKick:    Icons.shield_rounded,
    VipPrivilegeKey.notBeingFollowed:  Icons.person_off_rounded,
    VipPrivilegeKey.antiEnteringRoom:  Icons.meeting_room_rounded,
    VipPrivilegeKey.privateBrowsing:   Icons.visibility_off_rounded,
    VipPrivilegeKey.doNotDisturb:      Icons.notifications_off_rounded,
    VipPrivilegeKey.antiKick:          Icons.block_rounded,
    VipPrivilegeKey.invisibility:      Icons.blur_on_rounded,
    VipPrivilegeKey.sendRoomChatImage: Icons.image_rounded,
    VipPrivilegeKey.silentEntry:       Icons.volume_off_rounded,
  };

  static IconData _iconFor(VipPrivilegeKey key) =>
      _icons[key] ?? Icons.star_rounded;

  @override
  Widget build(BuildContext context) {
    final unlocked = VipPrivileges.unlockedFor(level);
    final locked   = VipPrivileges.lockedFor(level);
    final total    = unlocked.length + locked.length;

    // Tier color for the header counter — use the viewed tier, fall back to gold
    final headerColor = level > 0
        ? VipTierColors.of(level).border
        : _kGold;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    color: headerColor, size: 17),
                const SizedBox(width: 8),
                Text(
                  isArabic ? 'المزايا' : 'Benefits',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                // unlocked / total counter
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                    border:
                        Border.all(color: headerColor.withValues(alpha: 0.35)),
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

          // ── Unlocked section ───────────────────────────────────────────────
          if (unlocked.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _BenefitSectionLabel(
                icon: Icons.check_circle_rounded,
                label: isArabic ? 'مفعّلة' : 'Unlocked',
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

          // ── Divider + locked section ───────────────────────────────────────
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
                label: isArabic ? 'مزايا أعلى' : 'Higher Tier',
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
    final label    = isArabic ? spec.labelAr : spec.label;
    final desc     = isArabic ? spec.descriptionAr : spec.description;
    final reqTier  = VipTierColors.of(spec.minVipLevel);

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: reqTier.start.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: reqTier.border.withValues(alpha: 0.45)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Contact admin CTA
// ─────────────────────────────────────────────────────────────────────────────

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
                  isArabic ? 'تواصل مع الإدارة' : 'Contact Admin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  isArabic
                      ? 'للترقية إلى VIP عبر وكيل الشحن'
                      : 'Upgrade VIP through a recharge agent',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin VIP management panel
// ─────────────────────────────────────────────────────────────────────────────

class _AdminVipPanel extends StatefulWidget {
  const _AdminVipPanel({required this.isArabic});
  final bool isArabic;

  @override
  State<_AdminVipPanel> createState() => _AdminVipPanelState();
}

class _AdminVipPanelState extends State<_AdminVipPanel> {
  final _uidController      = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  int _grantLevel = 1;
  bool _busy = false;
  String? _result;
  bool _resultIsError = false;

  bool _goldenEnabled = true;
  final _goldenDurationController = TextEditingController();

  bool get isArabic => widget.isArabic;

  @override
  void dispose() {
    _uidController.dispose();
    _durationController.dispose();
    _goldenDurationController.dispose();
    super.dispose();
  }

  Future<void> _grantVip() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) {
      _setResult(isArabic ? 'أدخل معرّف المستخدم' : 'Enter a user ID', error: true);
      return;
    }
    final days = int.tryParse(_durationController.text.trim()) ?? 30;
    setState(() { _busy = true; _result = null; });
    try {
      await VipService().grantVip(
        userId: uid,
        vipLevel: _grantLevel,
        durationDays: days,
      );
      _setResult(
        isArabic
            ? 'تم منح VIP $_grantLevel لمدة $days يوم'
            : 'Granted VIP $_grantLevel for $days days',
      );
    } catch (e) {
      _setResult(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeVip() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) {
      _setResult(isArabic ? 'أدخل معرّف المستخدم' : 'Enter a user ID', error: true);
      return;
    }
    setState(() { _busy = true; _result = null; });
    try {
      await VipService().revokeVip(uid);
      _setResult(isArabic ? 'تم إلغاء VIP' : 'VIP revoked');
    } catch (e) {
      _setResult(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyGoldenId() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) {
      _setResult(isArabic ? 'أدخل معرّف المستخدم' : 'Enter a user ID', error: true);
      return;
    }
    final daysText = _goldenDurationController.text.trim();
    final days = daysText.isEmpty ? null : int.tryParse(daysText);
    setState(() { _busy = true; _result = null; });
    try {
      await VipService().setGoldenId(
        userId: uid,
        enabled: _goldenEnabled,
        durationDays: days,
      );
      _setResult(
        _goldenEnabled
            ? (isArabic ? 'تم تفعيل Golden ID' : 'Golden ID activated')
            : (isArabic ? 'تم إلغاء Golden ID' : 'Golden ID removed'),
      );
    } catch (e) {
      _setResult(e.toString(), error: true);
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

  @override
  Widget build(BuildContext context) {
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
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kPurpleDeep.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_rounded, color: _kGold, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                isArabic ? 'لوحة إدارة VIP' : 'VIP Admin Panel',
                style: const TextStyle(
                  color: _kGold,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _AdminField(
            controller: _uidController,
            label: isArabic ? 'معرّف المستخدم (UUID)' : 'User ID (UUID)',
            isArabic: isArabic,
          ),
          const SizedBox(height: 16),

          _SubLabel(
            label: isArabic ? 'منح / إلغاء VIP' : 'Grant / Revoke VIP',
            isArabic: isArabic,
          ),
          const SizedBox(height: 8),

          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Text(
                isArabic ? 'المستوى:' : 'Level:',
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
            label: isArabic ? 'المدة (أيام)' : 'Duration (days)',
            isArabic: isArabic,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),

          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: _AdminButton(
                  label: isArabic ? 'منح VIP' : 'Grant VIP',
                  color: _kGreen,
                  icon: Icons.workspace_premium_rounded,
                  busy: _busy,
                  onTap: _grantVip,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AdminButton(
                  label: isArabic ? 'إلغاء VIP' : 'Revoke VIP',
                  color: _kRed,
                  icon: Icons.remove_circle_outline_rounded,
                  busy: _busy,
                  onTap: _revokeVip,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Divider(color: _kCardBorder, height: 1),
          const SizedBox(height: 16),

          _SubLabel(label: 'Golden ID', isArabic: isArabic),
          const SizedBox(height: 8),

          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Text(
                isArabic ? 'تفعيل' : 'Enable',
                style: const TextStyle(color: _kText, fontSize: 13),
              ),
              Switch(
                value: _goldenEnabled,
                onChanged: (v) => setState(() => _goldenEnabled = v),
                activeThumbColor: _kGold,
                inactiveTrackColor: _kCardBorder,
              ),
              if (_goldenEnabled) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _AdminField(
                    controller: _goldenDurationController,
                    label: isArabic
                        ? 'أيام (فارغ = دائم)'
                        : 'Days (blank = permanent)',
                    isArabic: isArabic,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: _AdminButton(
              label: isArabic ? 'تطبيق Golden ID' : 'Apply Golden ID',
              color: _kGold,
              icon: Icons.star_rounded,
              busy: _busy,
              onTap: _applyGoldenId,
            ),
          ),

          if (_result != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_resultIsError ? _kRed : _kGreen).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_resultIsError ? _kRed : _kGreen).withValues(alpha: 0.4),
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

// ── Admin panel helpers ───────────────────────────────────────────────────────

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
