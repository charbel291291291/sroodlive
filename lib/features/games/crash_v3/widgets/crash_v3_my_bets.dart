import 'package:flutter/material.dart';

class CrashV3MyBets extends StatelessWidget {
  const CrashV3MyBets({required this.items, super.key});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      builder: (_, controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        itemBuilder: (_, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'My Crash History',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            );
          }
          final item = items[index - 1];
          return ListTile(
            title: Text(
              'Round #${item['public_round_id']} • Slot ${item['slot_number']}',
            ),
            subtitle: Text('${item['bet_amount']} coins • ${item['status']}'),
            trailing: Text('${item['payout_amount']}'),
          );
        },
      ),
    ),
  );
}
