/// Skeleton / shimmer loading placeholders for Srood Live.
///
/// Use [SkeletonBox] for a single shimmer rectangle.
/// Use [SkeletonLoader] for preset layouts (card, list tile, grid).
library;

import 'package:flutter/material.dart';

// ── Base shimmer box ──────────────────────────────────────────────────────────

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width:  widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E2435),
              Color.lerp(
                const Color(0xFF1E2435),
                const Color(0xFF2A3248),
                _anim.value,
              )!,
              const Color(0xFF1E2435),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

// ── Preset layouts ────────────────────────────────────────────────────────────

/// Standard card skeleton — mimics an [_AdminSectionCard] or profile card.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2435)),
      ),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 12),
          SizedBox(height: 6),
          SkeletonBox(height: 12),
          SizedBox(height: 6),
          SkeletonBox(width: 180, height: 12),
        ],
      ),
    );
  }
}

/// List-tile skeleton — mimics a row with avatar + two lines of text.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          const SkeletonBox(width: 42, height: 42, borderRadius: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(height: 13),
                SizedBox(height: 6),
                SkeletonBox(width: 140, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen skeleton loader — shows [count] list tiles.
class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({
    super.key,
    this.count = 6,
    this.type = SkeletonType.listTile,
  });

  final int count;
  final SkeletonType type;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: count,
      itemBuilder: (_, _) => switch (type) {
        SkeletonType.listTile => const SkeletonListTile(),
        SkeletonType.card     => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SkeletonCard(),
          ),
        SkeletonType.box      => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SkeletonBox(height: 48),
          ),
      },
    );
  }
}

enum SkeletonType { listTile, card, box }
