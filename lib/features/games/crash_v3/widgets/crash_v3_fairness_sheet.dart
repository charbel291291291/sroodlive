import 'package:flutter/material.dart';

class CrashV3FairnessSheet extends StatelessWidget {
  const CrashV3FairnessSheet({required this.data, super.key});
  final Map<String, dynamic>? data;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Provably Fair',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'HMAC-SHA256(server seed, client seed : nonce). The first 52 bits map uniformly to [0,1). The published house edge is applied, capped, then floored to two decimals.',
            ),
            const SizedBox(height: 14),
            for (final entry
                in (data ?? {'status': 'Select a completed round'}).entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText('${entry.key}: ${entry.value}'),
              ),
          ],
        ),
      ),
    ),
  );
}
