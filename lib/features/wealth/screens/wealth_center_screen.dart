import 'package:flutter/material.dart';
import '../models/wealth_models.dart';
import '../services/wealth_service.dart';
import '../widgets/wealth_badge_widget.dart';

class WealthCenterScreen extends StatefulWidget {
  const WealthCenterScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<WealthCenterScreen> createState() => _WealthCenterScreenState();
}

class _WealthCenterScreenState extends State<WealthCenterScreen> {
  static const _service = WealthService();

  UserWealth? _wealth;
  List<WealthLevelRule> _rules = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Fetch wealth and rules independently so a missing user_wealth row,
    // wealth_level_rules table, or RPC (e.g. schema drift / undeployed
    // migration) degrades gracefully to safe defaults instead of failing the
    // whole screen.
    UserWealth wealth;
    try {
      wealth = await _service.getMyWealth();
    } catch (e) {
      debugPrint('[WealthCenter] getMyWealth failed, using default: $e');
      wealth = UserWealth.empty; // Wealth Level 1 / Bronze
    }

    List<WealthLevelRule> rules;
    try {
      rules = await _service.getWealthRules();
    } catch (e) {
      debugPrint('[WealthCenter] getWealthRules failed, using empty: $e');
      rules = const [];
    }

    if (!mounted) return;
    setState(() {
      _wealth = wealth;
      _rules = rules;
      _error = null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0615),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFFD700),
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💎', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      widget.isArabic ? 'فشل التحميل' : 'Failed to load',
                      style: const TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _load();
                      },
                      child: Text(widget.isArabic ? 'اعادة المحاولة' : 'Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                _buildHeroCard(),
                const SizedBox(height: 20),
                _buildProgressSection(),
                const SizedBox(height: 20),
                _buildHowToEarnSection(),
                const SizedBox(height: 20),
                _buildWhereBadgesSection(),
                const SizedBox(height: 20),
                _buildTierTable(),
                const SizedBox(height: 32),
              ]),
            ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      snap: true,
      backgroundColor: const Color(0xFF0A0615),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_rounded,
          color: Color(0xFFFFD700),
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        widget.isArabic ? 'مركز الثروة' : 'Wealth Center',
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFF3D1F6E)),
      ),
    );
  }

  Widget _buildHeroCard() {
    final w = _wealth ?? UserWealth.empty;
    final tier = w.tier;
    final color = tier.color;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A0C30),
            color.withValues(alpha: 0.12),
            const Color(0xFF1A0C30),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              WealthTierBadgeCard(wealth: w),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isArabic ? 'مستوى الثروة' : 'Wealth Level',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tier.displayName} ${w.wealthLevel}',
                      style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isArabic
                          ? 'المستوى ${w.wealthLevel} من 100'
                          : 'Level ${w.wealthLevel} of 100',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!w.isMaxLevel) ...[
            const SizedBox(height: 18),
            _XpBar(wealth: w, color: color, isArabic: widget.isArabic),
          ] else ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                widget.isArabic
                    ? 'وصلت للمستوى الاقصى - Legend 100'
                    : 'Max Level Reached - Legend 100',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final w = _wealth ?? UserWealth.empty;
    return _Section(
      title: widget.isArabic ? 'تفاصيل التقدم' : 'Progress Details',
      isArabic: widget.isArabic,
      child: Column(
        children: [
          _StatRow(
            label: widget.isArabic ? 'اجمالي XP الثروة' : 'Total Wealth XP',
            value: _fmtXp(w.wealthXp),
            icon: Icons.auto_awesome_rounded,
            color: w.tier.color,
          ),
          const SizedBox(height: 8),
          _StatRow(
            label: widget.isArabic ? 'XP من الشحن' : 'XP from Recharge',
            value: _fmtXp(w.totalRechargedXp),
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF2ECC71),
          ),
          const SizedBox(height: 8),
          _StatRow(
            label: widget.isArabic ? 'XP من الهدايا' : 'XP from Gifts',
            value: _fmtXp(w.totalSpentGiftXp),
            icon: Icons.card_giftcard_rounded,
            color: const Color(0xFFFF6B9D),
          ),
          if (!w.isMaxLevel) ...[
            const SizedBox(height: 8),
            _StatRow(
              label: widget.isArabic
                  ? 'المتبقي للمستوى التالي'
                  : 'Remaining for Next Level',
              value: _fmtXp(w.xpToNextLevel ?? 0),
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF00D4FF),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHowToEarnSection() {
    return _Section(
      title: widget.isArabic
          ? 'كيف ترفع مستوى ثروتك'
          : 'How to Level Up Wealth',
      isArabic: widget.isArabic,
      child: Column(
        children: [
          _EarnRow(
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF2ECC71),
            title: widget.isArabic ? 'اشحن العملات' : 'Recharge Coins',
            subtitle: widget.isArabic
                ? '1 عملة مشحونة = 1 XP ثروة'
                : '1 recharged coin = 1 Wealth XP',
          ),
          const SizedBox(height: 10),
          _EarnRow(
            icon: Icons.card_giftcard_rounded,
            color: const Color(0xFFFF6B9D),
            title: widget.isArabic ? 'ارسل الهدايا' : 'Send Gifts',
            subtitle: widget.isArabic
                ? '1 عملة منفقة = 1 XP ثروة'
                : '1 coin spent on gifts = 1 Wealth XP',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F2A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF2ECC71).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF2ECC71),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isArabic
                        ? 'الثروة منفصلة تماماً عن VIP ومستوى النشاط.'
                        : 'Wealth is fully separate from VIP and activity level.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhereBadgesSection() {
    final locations = widget.isArabic
        ? [
            'الملف الشخصي',
            'قائمة المستخدمين في الغرفة',
            'بطاقة الملف المصغرة',
            'التصنيفات',
          ]
        : ['Profile', 'Room user list', 'Mini profile card', 'Rankings'];
    return _Section(
      title: widget.isArabic
          ? 'اين تظهر شارة الثروة'
          : 'Where Wealth Badge Appears',
      isArabic: widget.isArabic,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: locations
            .map(
              (loc) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D1F6E).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF8B26D9).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      color: Color(0xFFFFD700),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      loc,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTierTable() {
    return _Section(
      title: widget.isArabic
          ? 'جدول المستويات (100 مستوى)'
          : 'Tier Table (100 Levels)',
      isArabic: widget.isArabic,
      child: Column(
        children: WealthTier.values.map((tier) {
          final isCurrentTier = (_wealth?.tierNumber ?? 1) == tier.number;
          final firstRule = _rules
              .where((r) => r.tierNumber == tier.number)
              .firstOrNull;
          final color = tier.color;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCurrentTier
                  ? color.withValues(alpha: 0.15)
                  : const Color(0xFF12091D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrentTier
                    ? color.withValues(alpha: 0.7)
                    : color.withValues(alpha: 0.2),
                width: isCurrentTier ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.18),
                    border: Border.all(
                      color: color.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${tier.number}',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier.displayName,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        widget.isArabic
                            ? 'المستويات ${tier.minLevel}-${tier.maxLevel}'
                            : 'Levels ${tier.minLevel}-${tier.maxLevel}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (firstRule != null)
                  Text(
                    _fmtXp(firstRule.requiredXp),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                if (isCurrentTier)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.isArabic ? 'انت هنا' : 'You',
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fmtXp(int xp) {
    if (xp >= 1000000000) return '${(xp / 1000000000).toStringAsFixed(1)}B';
    if (xp >= 1000000) return '${(xp / 1000000).toStringAsFixed(1)}M';
    if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}K';
    return '$xp';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _XpBar extends StatelessWidget {
  const _XpBar({
    required this.wealth,
    required this.color,
    required this.isArabic,
  });
  final UserWealth wealth;
  final Color color;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final progress = (wealth.levelProgress ?? 0).clamp(0.0, 1.0);
    final String fmtXp = _fmt(wealth.wealthXp);
    final String fmtNext = _fmt(wealth.nextLevelRequiredXp ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isArabic
                  ? 'المستوى ${wealth.wealthLevel}'
                  : 'Level ${wealth.wealthLevel}',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              isArabic
                  ? 'المستوى ${wealth.nextLevel ?? wealth.wealthLevel}'
                  : 'Level ${wealth.nextLevel ?? wealth.wealthLevel}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$fmtXp XP',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
            Text(
              '$fmtNext XP',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmt(int xp) {
    if (xp >= 1000000000) return '${(xp / 1000000000).toStringAsFixed(1)}B';
    if (xp >= 1000000) return '${(xp / 1000000).toStringAsFixed(1)}M';
    if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}K';
    return '$xp';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    required this.isArabic,
  });
  final String title;
  final Widget child;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF12091D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3D1F6E)),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EarnRow extends StatelessWidget {
  const _EarnRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
