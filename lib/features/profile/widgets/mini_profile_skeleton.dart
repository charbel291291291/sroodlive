import 'package:flutter/material.dart';

class MiniProfileSkeleton extends StatelessWidget {
  const MiniProfileSkeleton({super.key});

  static const _surface = Color(0xFF170C25);
  static const _highlight = Color(0xFF2A1740);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading profile',
      liveRegion: true,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  16,
                  12,
                  16,
                  MediaQuery.paddingOf(context).bottom + 32,
                ),
                child: const Column(
                  children: [
                    _HeaderSkeleton(),
                    SizedBox(height: 16),
                    _StatsSkeleton(),
                    SizedBox(height: 16),
                    _ProgressSkeleton(),
                    SizedBox(height: 16),
                    _ActionGridSkeleton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: const Column(
        children: [
          Row(
            children: [
              _SkeletonBox(width: 88, height: 88, radius: 44),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 150, height: 18),
                    SizedBox(height: 10),
                    _SkeletonBox(width: 104, height: 13),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SkeletonBox(width: 62, height: 24, radius: 12),
                        _SkeletonBox(width: 74, height: 24, radius: 12),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              _SkeletonBox(width: 48, height: 48, radius: 16),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: _cardDecoration(),
      child: const Row(
        children: [
          Expanded(child: _SkeletonStat()),
          Expanded(child: _SkeletonStat()),
          Expanded(child: _SkeletonStat()),
        ],
      ),
    );
  }
}

class _SkeletonStat extends StatelessWidget {
  const _SkeletonStat();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _SkeletonBox(width: 42, height: 17),
        SizedBox(height: 8),
        _SkeletonBox(width: 62, height: 12),
      ],
    );
  }
}

class _ProgressSkeleton extends StatelessWidget {
  const _ProgressSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 118, height: 16),
          SizedBox(height: 14),
          _SkeletonBox(width: double.infinity, height: 9, radius: 5),
          SizedBox(height: 12),
          _SkeletonBox(width: 176, height: 12),
        ],
      ),
    );
  }
}

class _ActionGridSkeleton extends StatelessWidget {
  const _ActionGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 360 ? 8.0 : 12.0;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(6, (index) {
            final width = (constraints.maxWidth - gap) / 2;
            return _SkeletonBox(width: width, height: 76, radius: 18);
          }),
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: MiniProfileSkeleton._highlight,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: MiniProfileSkeleton._surface.withValues(alpha: 0.94),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: const Color(0xFF6F3AA8).withValues(alpha: 0.24)),
);
