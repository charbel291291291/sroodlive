import 'package:flutter/material.dart';
import '../models/crash_v3_history_item.dart';

class CrashV3HistoryStrip extends StatelessWidget {
  const CrashV3HistoryStrip({
    required this.items,
    required this.onTap,
    super.key,
  });
  final List<CrashV3HistoryItem> items;
  final ValueChanged<CrashV3HistoryItem> onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 7),
      itemBuilder: (_, i) {
        final item = items[i];
        return ActionChip(
          onPressed: () => onTap(item),
          backgroundColor: const Color(0xFF26143D),
          side: BorderSide.none,
          label: Text(
            '${item.crashMultiplier.toStringAsFixed(2)}×',
            style: TextStyle(
              color: item.crashMultiplier >= 10
                  ? const Color(0xFFFFC857)
                  : const Color(0xFFE879F9),
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    ),
  );
}
