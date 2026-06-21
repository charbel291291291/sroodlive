import 'package:flutter/material.dart';

// =============================================================================
// VIP Rules â€” explains what VIP is, how VIP Exp is earned, and the per-level
// recharge / upgrade / maintain Exp requirements for Srood Live.
//
// UI/text only. No VIP, wallet, recharge, or Supabase logic lives here â€” the
// numbers below are presentational copy that mirror the Srood Live economy
// (1 coin = 1 VIP Exp). Matches the VIP Center's dark purple / gold styling.
// =============================================================================

const Color _kBg = Color(0xFF07030D);
const Color _kCard = Color(0xFF12091D);
const Color _kCardBorder = Color(0xFF2A1845);
const Color _kGold = Color(0xFFF0C15A);
const Color _kText = Color(0xFFD8CFEA);

/// One row of the VIP Exp requirements table.
class _VipExpRow {
  const _VipExpRow(this.level, this.totalRecharge, this.upgradeExp, this.maintainExp);
  final int level;
  final int totalRecharge;
  final int upgradeExp;
  final int maintainExp;
}

const List<_VipExpRow> _kExpTable = [
  _VipExpRow(1, 100000, 100000, 60000),
  _VipExpRow(2, 300000, 200000, 100000),
  _VipExpRow(3, 700000, 400000, 200000),
  _VipExpRow(4, 1500000, 800000, 400000),
  _VipExpRow(5, 3000000, 1500000, 750000),
  _VipExpRow(6, 6000000, 3000000, 1500000),
  _VipExpRow(7, 12000000, 6000000, 3000000),
  _VipExpRow(8, 24000000, 12000000, 6000000),
  _VipExpRow(9, 50000000, 26000000, 12000000),
];

/// Comma-groups an integer for display (1234567 -> "1,234,567").
String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class VipRulesScreen extends StatelessWidget {
  const VipRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'VIP Rules',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), _kBg, Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 28 + bottomInset),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _RuleSection(
                    title: 'What is VIP?',
                    body:
                        'VIP is a special identity in Srood Live earned through '
                        'recharge activity. After becoming a VIP, you unlock '
                        'premium in-app privileges. The higher your VIP level, '
                        'the more privileges you unlock.',
                  ),
                  SizedBox(height: 18),
                  _RuleSection(
                    title: 'How to get VIP Exp?',
                    body:
                        'You earn VIP Exp through Srood Live recharges. Every '
                        '1 coin equals 1 VIP Exp. If a recharge is refunded, '
                        'the VIP Exp earned from that recharge may be deducted.',
                  ),
                  SizedBox(height: 22),
                  _ExpTable(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _kGold,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            color: _kText,
            fontSize: 14,
            height: 1.6,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _ExpTable extends StatelessWidget {
  const _ExpTable();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VIP Exp Table',
          style: TextStyle(
            color: _kGold,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kCardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header row.
              Container(
                color: _kGold.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                child: const Row(
                  children: [
                    _Cell('Level', flex: 2, header: true),
                    _Cell('Total\nRecharge', flex: 3, header: true),
                    _Cell('Upgrade\nExp', flex: 3, header: true),
                    _Cell('Maintain\nExp', flex: 3, header: true),
                  ],
                ),
              ),
              // Data rows.
              for (var i = 0; i < _kExpTable.length; i++)
                Container(
                  color: i.isEven
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.025),
                  padding:
                      const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                  child: Row(
                    children: [
                      _Cell('Lv.${_kExpTable[i].level}', flex: 2, accent: true),
                      _Cell(_fmt(_kExpTable[i].totalRecharge), flex: 3),
                      _Cell(_fmt(_kExpTable[i].upgradeExp), flex: 3),
                      _Cell(_fmt(_kExpTable[i].maintainExp), flex: 3),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.text, {
    required this.flex,
    this.header = false,
    this.accent = false,
  });
  final String text;
  final int flex;
  final bool header;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = header
        ? _kGold
        : accent
            ? Colors.white
            : _kText;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        // FittedBox keeps the largest numbers (e.g. 50,000,000) from
        // overflowing on narrow screens by scaling them down to fit.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: header ? 11 : 12.5,
              height: 1.25,
              fontWeight: header || accent
                  ? FontWeight.w800
                  : FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

