import 'package:flutter/material.dart';

import '../../../core/utils/vip_visuals.dart';
import '../../../shared/widgets/vip_framed_avatar.dart';
import '../services/gamification_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final plans = await _service.getVipPlans();
      if (!mounted) return;
      setState(() { _plans = plans; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
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
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
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
          textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            ),
            Text(
              widget.isArabic ? 'مركز VIP' : 'VIP Center',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFF0C15A), strokeWidth: 2.5));
    if (_error != null) return _buildError();

    return RefreshIndicator(
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _CurrentStatusCard(
            vipLevel: widget.currentVipLevel,
            expiresAt: widget.vipExpiresAt,
            isArabic: widget.isArabic,
          ),
          const SizedBox(height: 20),
          Text(
            widget.isArabic ? 'خطط VIP' : 'VIP Plans',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ..._plans.map((plan) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _VipPlanCard(
                  plan: plan,
                  isCurrent: (plan['level'] as int?) == widget.currentVipLevel &&
                      widget.currentVipLevel > 0,
                  isArabic: widget.isArabic,
                  onTap: () => _showUpgradeInfo(plan),
                ),
              )),
          const SizedBox(height: 8),
          _ContactSupportButton(isArabic: widget.isArabic),
        ],
      ),
    );
  }

  void _showUpgradeInfo(Map<String, dynamic> plan) {
    final level = (plan['level'] as int?) ?? 0;
    final name = plan['name']?.toString() ?? 'VIP $level';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _UpgradeInfoSheet(
        plan: plan,
        planName: name,
        isArabic: widget.isArabic,
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5C7A), size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _load,
              child: Text(widget.isArabic ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(color: Color(0xFFF0C15A))),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Current status card
// ---------------------------------------------------------------------------

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({required this.vipLevel, required this.expiresAt, required this.isArabic});
  final int vipLevel;
  final DateTime? expiresAt;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final style = getVipVisualStyle(vipLevel);
    final isActive = vipLevel > 0;
    final expired = expiresAt != null && expiresAt!.isBefore(DateTime.now());
    final reallyActive = isActive && !expired;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: reallyActive
            ? LinearGradient(
                colors: [
                  style?.glowColor.withValues(alpha: 0.3) ?? const Color(0xFF4B168C),
                  const Color(0xFF1B102A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(colors: [Color(0xFF1B102A), Color(0xFF12091D)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: reallyActive
              ? style?.glowColor.withValues(alpha: 0.5) ?? const Color(0xFFF0C15A)
              : const Color(0xFF4A3470),
          width: reallyActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          VipFramedAvatar(size: 64, vipLevel: reallyActive ? vipLevel : null),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  reallyActive
                      ? (isArabic ? 'VIP $vipLevel نشط' : 'VIP $vipLevel Active')
                      : (isArabic ? 'لا يوجد VIP نشط' : 'No Active VIP'),
                  style: TextStyle(
                    color: reallyActive ? const Color(0xFFF0C15A) : const Color(0xFF7A6890),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (reallyActive && expiresAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    isArabic
                        ? 'ينتهي: ${_fmtDate(expiresAt!)}'
                        : 'Expires: ${_fmtDate(expiresAt!)}',
                    style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 12),
                  ),
                ],
                if (!reallyActive) ...[
                  const SizedBox(height: 4),
                  Text(
                    isArabic ? 'تواصل مع الدعم للحصول على VIP' : 'Contact support to get VIP',
                    style: const TextStyle(color: Color(0xFF7A6890), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ---------------------------------------------------------------------------
// VIP plan card
// ---------------------------------------------------------------------------

class _VipPlanCard extends StatelessWidget {
  const _VipPlanCard({
    required this.plan,
    required this.isCurrent,
    required this.isArabic,
    required this.onTap,
  });
  final Map<String, dynamic> plan;
  final bool isCurrent;
  final bool isArabic;
  final VoidCallback onTap;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final level = (plan['level'] as int?) ?? 0;
    final name = plan['name']?.toString() ?? 'VIP $level';
    final priceCoins = (plan['price_coins'] as num?)?.toInt() ?? 0;
    final duration = (plan['duration_days'] as num?)?.toInt() ?? 30;
    final benefits = (plan['benefits'] as List<dynamic>?) ?? [];
    final style = getVipVisualStyle(level);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF12091D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFFF0C15A)
                : style?.glowColor.withValues(alpha: 0.3) ?? const Color(0xFF4A3470),
            width: isCurrent ? 1.5 : 1,
          ),
          boxShadow: isCurrent
              ? [BoxShadow(color: const Color(0xFFF0C15A).withValues(alpha: 0.1), blurRadius: 12)]
              : null,
        ),
        child: Row(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level badge
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: style != null
                      ? [style.glowColor, style.glowColor.withValues(alpha: 0.5)]
                      : [const Color(0xFF4B168C), const Color(0xFF8B26D9)],
                ),
              ),
              child: Center(
                child: Text(
                  '$level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            color: style?.nameColor ?? Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0C15A).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFF0C15A).withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            isArabic ? 'نشط' : 'Active',
                            style: const TextStyle(
                                color: Color(0xFFF0C15A), fontSize: 11, fontWeight: FontWeight.w900),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: Color(0xFFF0C15A), size: 14),
                      const SizedBox(width: 3),
                      Text(
                        _fmt(priceCoins),
                        style: const TextStyle(color: Color(0xFFF0C15A), fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isArabic ? '· $duration يوم' : '· $duration days',
                        style: const TextStyle(color: Color(0xFF7A6890), fontSize: 12),
                      ),
                    ],
                  ),
                  if (benefits.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: benefits.take(3).map((b) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B102A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF3D2260)),
                            ),
                            child: Text(
                              b.toString(),
                              style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 11),
                            ),
                          )).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF4A3470), size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upgrade info sheet (VIP is admin-granted, no direct purchase)
// ---------------------------------------------------------------------------

class _UpgradeInfoSheet extends StatelessWidget {
  const _UpgradeInfoSheet({
    required this.plan,
    required this.planName,
    required this.isArabic,
  });
  final Map<String, dynamic> plan;
  final String planName;
  final bool isArabic;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final level = (plan['level'] as int?) ?? 0;
    final priceCoins = (plan['price_coins'] as num?)?.toInt() ?? 0;
    final duration = (plan['duration_days'] as num?)?.toInt() ?? 30;
    final benefits = (plan['benefits'] as List<dynamic>?) ?? [];
    final style = getVipVisualStyle(level);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12091D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A3470),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: [
                    // VIP level circle
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: style != null
                              ? [style.glowColor, style.glowColor.withValues(alpha: 0.5)]
                              : [const Color(0xFF4B168C), const Color(0xFF8B26D9)],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$level',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      planName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.monetization_on_rounded,
                            color: Color(0xFFF0C15A), size: 18),
                        const SizedBox(width: 4),
                        Text(
                          _fmt(priceCoins),
                          style: const TextStyle(
                            color: Color(0xFFF0C15A),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isArabic ? '/ $duration يوم' : '/ $duration days',
                          style: const TextStyle(color: Color(0xFF7A6890), fontSize: 14),
                        ),
                      ],
                    ),
                    if (benefits.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ...benefits.map(
                        (b) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            textDirection:
                                isArabic ? TextDirection.rtl : TextDirection.ltr,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded,
                                  color: Color(0xFF2ECC71), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  b.toString(),
                                  style: const TextStyle(
                                    color: Color(0xFFD8CFEA),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B102A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF4A3470)),
                      ),
                      child: Row(
                        textDirection:
                            isArabic ? TextDirection.rtl : TextDirection.ltr,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: Color(0xFFF0C15A), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isArabic
                                  ? 'يتم منح VIP من قِبل الإدارة. تواصل مع وكيل الشحن أو الدعم للترقية.'
                                  : 'VIP is granted by admins. Contact a recharge agent or support to upgrade.',
                              style: const TextStyle(
                                color: Color(0xFFD8CFEA),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // Fixed CTA button — always visible, never pushed off screen
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4B168C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isArabic ? 'حسناً' : 'Got it',
                      style: const TextStyle(fontWeight: FontWeight.w900),
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

// ---------------------------------------------------------------------------
// Contact support button
// ---------------------------------------------------------------------------

class _ContactSupportButton extends StatelessWidget {
  const _ContactSupportButton({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4B168C), Color(0xFF8B26D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.3),
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
            child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'تواصل مع الدعم' : 'Contact Support',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                ),
                Text(
                  isArabic ? 'للاستفسار عن VIP والشحن' : 'For VIP & recharge enquiries',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
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
