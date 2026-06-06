import 'package:flutter/material.dart';

import '../widgets/profile_hub_widgets.dart';

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({
    required this.title,
    required this.body,
    required this.isArabic,
    super.key,
  });

  final String title;
  final String body;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return ProfileHubScaffold(
      title: title,
      isArabic: isArabic,
      children: [
        ProfileInfoCard(
          icon: Icons.policy_rounded,
          title: title,
          body: body,
          isArabic: isArabic,
        ),
      ],
    );
  }
}

String policyBody(String key, bool isArabic) {
  if (isArabic) {
    return switch (key) {
      'coin' =>
        'عملات SrOOd Live هي عملة رقمية داخل التطبيق فقط. السعر الأساسي هو 1 USD = 10,000 عملة. لا تملك العملات قيمة نقدية خارج المنصة، وقد تتضمن الباقات عروضاً إضافية.',
      'vip' =>
        'خطط VIP تمنح مزايا مرئية واجتماعية لمدة محددة. يمكن للمنصة تعديل المزايا والأسعار والقواعد عند الحاجة.',
      'gift' =>
        'الهدايا عناصر ترفيهية داخل الغرف. إرسال الهدية يخصم العملات من المرسل ويعتبر نهائياً بعد التأكيد.',
      'agency' =>
        'الوكالات تساعد في إدارة ودعم المضيفين. الأرباح والمكافآت تخضع لمراجعة الإدارة وقواعد المنصة.',
      'income' =>
        'الدخل وطلبات السحب تحتاج مراجعة الإدارة. لا يتم السحب بدون رصيد متاح وكافٍ.',
      'privacy' =>
        'نحترم خصوصيتك ونستخدم بياناتك لتشغيل الحساب، الغرف، الدعم، والمحفظة وفق إعدادات الخصوصية.',
      'terms' =>
        'باستخدام SrOOd Live توافق على قواعد المجتمع، سياسات العملات والهدايا وVIP، وتعليمات الإدارة.',
      _ =>
        'احترم المستخدمين الآخرين. لا مضايقات، لا تهديدات، لا احتيال، لا انتحال، ولا مشاركة معلومات خاصة بدون موافقة.',
    };
  }

  return switch (key) {
    'coin' =>
      'SrOOd Live coins are a digital in-app currency used only inside the platform. The base recharge rate is 1 USD = 10,000 SrOOd Coins. Coins have no cash value outside SrOOd Live, and packages may include bonus offers.',
    'vip' =>
      'VIP plans provide premium visual and social benefits for a fixed duration. SrOOd Live may update VIP benefits, prices, or rules when needed.',
    'gift' =>
      'Gifts are entertainment items inside live rooms. Sending a gift deducts coins from the sender and is final after confirmation.',
    'agency' =>
      'Agencies help recruit, manage, and support hosts. Earnings and rewards are reviewed by admins and follow platform policy.',
    'income' =>
      'Income and payout requests require admin review. No payout is processed without enough available balance.',
    'privacy' =>
      'We respect your privacy and use account, room, support, and wallet data to operate SrOOd Live according to your settings.',
    'terms' =>
      'By using SrOOd Live, you agree to community rules, coin, gift, VIP, agency, and admin policies.',
    _ =>
      'Respect others in live rooms. No harassment, hate speech, threats, scams, impersonation, illegal activity, or sharing private information without consent.',
  };
}
