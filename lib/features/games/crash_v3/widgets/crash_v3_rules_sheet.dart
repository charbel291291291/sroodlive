import 'package:flutter/material.dart';

class CrashV3RulesSheet extends StatelessWidget {
  const CrashV3RulesSheet({super.key});

  @override
  Widget build(BuildContext context) => const SafeArea(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to play',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 12),
          Text(
            'Place up to two independent coin bets during betting. Cash out '
            'while the rocket is flying, or set an automatic multiplier. The '
            'server timestamp and result are authoritative. If the rocket '
            'crashes first, the accepted bet is lost. Virtual Srood coins only.',
          ),
        ],
      ),
    ),
  );
}
