import 'package:flutter/material.dart';

/// A bottom sheet that lets users pick an emoji reaction.
/// Styled as a dark glass panel matching the Srood Live premium theme.
class ReactionPickerSheet extends StatelessWidget {
  const ReactionPickerSheet({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  static const _emojis = [
    '❤️', // ❤️
    '😂', // 😂
    '😍', // 😍
    '😮', // 😮
    '🔥', // 🔥
    '👏', // 👏
    '👍', // 👍
    '🎉', // 🎉
    '😎', // 😎
    '😢', // 😢
    '😡', // 😡
    '🤍', // 🤍
    '💜', // 💜
    '💯', // 💯
    '✨',       // ✨
    '💀', // 💀
    '🤣', // 🤣
    '😘', // 😘
    '🌟', // 🌟
    '💕', // 💕
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A0B33),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF8B26D9), width: 1.0),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grabber
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 40),
              Text(
                'React',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'إغلاق',
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF9E91B8),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: _emojis.length,
            itemBuilder: (context, i) {
              final emoji = _emojis[i];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  onPick(emoji);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }

  /// Shows the picker as a bottom sheet and returns the chosen emoji or null.
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onPick,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReactionPickerSheet(onPick: onPick),
    );
  }
}
