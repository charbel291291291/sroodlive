import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

class RechargeHelpScreen extends StatefulWidget {
  const RechargeHelpScreen({required this.isArabic, super.key});

  final bool isArabic;

  @override
  State<RechargeHelpScreen> createState() => _RechargeHelpScreenState();
}

class _RechargeHelpScreenState extends State<RechargeHelpScreen> {
  List<_AgentInfo> _agents = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('recharge_agents')
          .select('name, code, phone, whatsapp')
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _agents = (data as List<dynamic>)
            .map((row) => _AgentInfo.fromJson(row as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.isArabic;
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
              _buildHeader(isArabic),
              Expanded(
                child: RefreshIndicator(
                  color: const Color(0xFFF4C95D),
                  backgroundColor: const Color(0xFF1B102A),
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    child: Directionality(
                      textDirection: isArabic
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RateCard(isArabic: isArabic),
                          const SizedBox(height: 16),
                          _PaymentMethodsCard(isArabic: isArabic),
                          const SizedBox(height: 16),
                          _StepsCard(isArabic: isArabic),
                          const SizedBox(height: 16),
                          _AgentsSection(
                            agents: _agents,
                            loading: _loading,
                            error: _error,
                            isArabic: isArabic,
                            onRetry: _load,
                          ),
                          const SizedBox(height: 16),
                          _NoteCard(isArabic: isArabic),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: isArabic
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'دعم الشحن' : 'Recharge Help',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  isArabic ? 'دليل الشحن والوكلاء' : 'Guide & agents',
                  style: const TextStyle(
                    color: Color(0xFFBCAED6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
// Rate card
// ---------------------------------------------------------------------------

class _RateCard extends StatelessWidget {
  const _RateCard({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A1689), Color(0xFF231036), Color(0xFFC8952D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFF4C95D).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B26D9).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Icon(
              Icons.monetization_on_rounded,
              color: Color(0xFFF4C95D),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'سعر الصرف' : 'Exchange Rate',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isArabic ? '1 \$ = 20,000 عملة' : '1 USD = 20,000 coins',
                  style: const TextStyle(
                    color: Color(0xFFF4C95D),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
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
// Payment methods card
// ---------------------------------------------------------------------------

class _PaymentMethodsCard extends StatelessWidget {
  const _PaymentMethodsCard({required this.isArabic});
  final bool isArabic;

  static const _methods = [
    (Icons.account_balance_rounded, 'OMT', 'OMT'),
    (Icons.phone_android_rounded, 'Wish Money', 'Wish Money'),
    (Icons.currency_bitcoin_rounded, 'USDT (Crypto)', 'USDT'),
    (Icons.support_agent_rounded, 'Agent', 'وكيل'),
    (Icons.payments_rounded, 'Cash', 'نقد'),
  ];

  @override
  Widget build(BuildContext context) {
    return _HelpCard(
      title: isArabic ? 'طرق الدفع المقبولة' : 'Accepted Payment Methods',
      icon: Icons.credit_card_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _methods.map((m) {
          final label = isArabic ? m.$3 : m.$2;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1B102A),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFF4C95D).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(m.$1, color: const Color(0xFFF4C95D), size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFE3D9F4),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Steps card
// ---------------------------------------------------------------------------

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final steps = isArabic
        ? [
            'اختر طريقة الدفع المناسبة لك',
            'اضغط "شحن" من صفحة المحفظة',
            'أدخل المبلغ والمرجع أو كود الوكيل',
            'أرسل الطلب وانتظر موافقة الإدارة',
            'سيُضاف الرصيد تلقائياً بعد التأكيد',
          ]
        : [
            'Choose your preferred payment method',
            'Tap "Recharge" from the Wallet screen',
            'Enter the amount and reference or agent code',
            'Submit the request and await admin approval',
            'Balance is added automatically after confirmation',
          ];

    return _HelpCard(
      title: isArabic ? 'خطوات الشحن' : 'How to Recharge',
      icon: Icons.list_alt_rounded,
      child: Column(
        children: List.generate(steps.length, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 12 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4C95D).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFF4C95D).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Color(0xFFF4C95D),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agents section
// ---------------------------------------------------------------------------

class _AgentsSection extends StatelessWidget {
  const _AgentsSection({
    required this.agents,
    required this.loading,
    required this.error,
    required this.isArabic,
    required this.onRetry,
  });

  final List<_AgentInfo> agents;
  final bool loading;
  final String? error;
  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _HelpCard(
      title: isArabic ? 'وكلاء الشحن' : 'Recharge Agents',
      icon: Icons.support_agent_rounded,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF4C95D),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (error != null) {
      return Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF5C7A),
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text(
              isArabic ? 'إعادة المحاولة' : 'Retry',
              style: const TextStyle(color: Color(0xFFF4C95D)),
            ),
          ),
        ],
      );
    }

    if (agents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Icon(
              Icons.support_agent_rounded,
              color: Color(0xFF4A3470),
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'لا يوجد وكلاء متاحون حالياً'
                  : 'No agents available right now',
              style: const TextStyle(
                color: Color(0xFF7A6890),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: agents
          .map((a) => _AgentTile(agent: a, isArabic: isArabic))
          .toList(),
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({required this.agent, required this.isArabic});
  final _AgentInfo agent;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B102A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A3470)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + code row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF4B168C).withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Color(0xFFF4C95D),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (agent.code.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            isArabic ? 'الكود: ' : 'Code: ',
                            style: const TextStyle(
                              color: Color(0xFF7A6890),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            agent.code,
                            style: const TextStyle(
                              color: Color(0xFFF4C95D),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: agent.code),
                              );
                              SroodToast.show(context, isArabic ? 'تم نسخ الكود' : 'Code copied', type: SroodToastType.success);
                            },
                            child: const Icon(
                              Icons.copy_rounded,
                              color: Color(0xFF7A6890),
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Contact buttons
          if (agent.phone.isNotEmpty || agent.whatsapp.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (agent.phone.isNotEmpty)
                  _ContactChip(
                    icon: Icons.phone_rounded,
                    label: agent.phone,
                    isArabic: isArabic,
                  ),
                if (agent.whatsapp.isNotEmpty)
                  _ContactChip(
                    icon: Icons.chat_rounded,
                    label: agent.whatsapp,
                    color: const Color(0xFF25D366),
                    isArabic: isArabic,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip({
    required this.icon,
    required this.label,
    required this.isArabic,
    this.color = const Color(0xFFF4C95D),
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: label));
        SroodToast.show(context, isArabic ? 'تم النسخ' : 'Copied', type: SroodToastType.success);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.copy_rounded,
              color: color.withValues(alpha: 0.6),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note card
// ---------------------------------------------------------------------------

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.isArabic});
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E0A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF2ECC71).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF2ECC71),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isArabic
                  ? 'يُعالَج كل طلب شحن يدوياً من قِبل الإدارة. يُرجى الاحتفاظ بإيصال الدفع حتى تأكيد الطلب.'
                  : 'Each recharge request is processed manually by the admin team. Please keep your payment receipt until your request is confirmed.',
              style: const TextStyle(
                color: Color(0xFF86EFAC),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared help card wrapper
// ---------------------------------------------------------------------------

class _HelpCard extends StatelessWidget {
  const _HelpCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF160B24).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF6E3AA8).withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A28D9).withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFF4C95D), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _AgentInfo {
  const _AgentInfo({
    required this.name,
    required this.code,
    required this.phone,
    required this.whatsapp,
  });

  factory _AgentInfo.fromJson(Map<String, dynamic> json) => _AgentInfo(
    name: json['name']?.toString() ?? '',
    code: json['code']?.toString() ?? '',
    phone: json['phone']?.toString() ?? '',
    whatsapp: json['whatsapp']?.toString() ?? '',
  );

  final String name;
  final String code;
  final String phone;
  final String whatsapp;
}
