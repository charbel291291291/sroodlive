import 'package:flutter/material.dart';

import '../../../core/vip/vip_prestige.dart';
import '../../vip/widgets/vip_mic_wave_ring.dart';

/// Admin/dev preview screen showing VIP 0–9 visual hierarchy.
/// Displays chat frames, mic wave rings, entry banners, and badges side by side.
class VipVisualPreviewScreen extends StatelessWidget {
  const VipVisualPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0E14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1117),
          title: const Text('VIP Visual Preview',
              style: TextStyle(color: Color(0xFFF0C15A), fontWeight: FontWeight.w800)),
          iconTheme: const IconThemeData(color: Color(0xFFF0C15A)),
          bottom: const TabBar(
            labelColor: Color(0xFFF0C15A),
            unselectedLabelColor: Color(0xFF6B7280),
            indicatorColor: Color(0xFFF0C15A),
            tabs: [
              Tab(text: 'Chat Frames'),
              Tab(text: 'Mic Waves'),
              Tab(text: 'Entry Banners'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ChatFramesPreview(),
            _MicWavesPreview(),
            _EntryBannersPreview(),
          ],
        ),
      ),
    );
  }
}

// ── Chat Frames ───────────────────────────────────────────────────────────────

class _ChatFramesPreview extends StatelessWidget {
  const _ChatFramesPreview();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 10,
      itemBuilder: (ctx, i) => _ChatFrameTile(level: i),
    );
  }
}

class _ChatFrameTile extends StatefulWidget {
  const _ChatFrameTile({required this.level});
  final int level;

  @override
  State<_ChatFrameTile> createState() => _ChatFrameTileState();
}

class _ChatFrameTileState extends State<_ChatFrameTile>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.level >= 7) {
      _ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.level == 9 ? 1600 : 2200),
      )..repeat(reverse: true);
      _pulse = Tween<double>(begin: 0.60, end: 1.0)
          .animate(CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut));
    } else {
      _pulse = const AlwaysStoppedAnimation(1.0);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final prestige = VipVisualResolver.resolve(level);
    final nameColor = level > 0 ? prestige.nameColor : const Color(0xFF9BE8FF);
    final cr = prestige.cardCornerRadius;
    final isGradient = prestige.bubbleGradient[0] != prestige.bubbleGradient[1];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (ctx, _) {
          final deco = isGradient
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: prestige.bubbleGradient,
                  ),
                  borderRadius: BorderRadius.circular(cr),
                  border: Border.all(
                      color: prestige.borderColor, width: prestige.borderWidth),
                  boxShadow: prestige.buildGlowShadows(pulseFactor: _pulse.value),
                )
              : BoxDecoration(
                  color: prestige.surfaceTint,
                  borderRadius: BorderRadius.circular(cr),
                  border: Border.all(
                      color: prestige.borderColor, width: prestige.borderWidth),
                  boxShadow: prestige.buildGlowShadows(pulseFactor: _pulse.value),
                );

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: deco,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar ring placeholder
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: prestige.avatarRingColor.withValues(alpha: 0.20),
                    border: prestige.avatarRingWidth > 0
                        ? Border.all(
                            color: prestige.avatarRingColor,
                            width: prestige.avatarRingWidth,
                          )
                        : null,
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white54, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            level == 0 ? 'Normal User' : 'VIP $level User',
                            style: TextStyle(
                              color: nameColor,
                              fontSize: 11,
                              fontWeight: prestige.nameFontWeight,
                            ),
                          ),
                          if (level > 0) ...[
                            const SizedBox(width: 4),
                            _PreviewBadge(prestige: prestige),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        level == 0
                            ? 'This is a normal user message with no VIP styling.'
                            : 'This is a VIP $level message — luxury, prestige, and style.',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.prestige});
  final VipPrestige prestige;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: prestige.badgeGradient),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        prestige.badgeLabel,
        style: TextStyle(
          color: prestige.badgeTextColor,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Mic Waves ─────────────────────────────────────────────────────────────────

class _MicWavesPreview extends StatelessWidget {
  const _MicWavesPreview();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: 10,
      itemBuilder: (ctx, i) => _MicWavePreviewCell(level: i),
    );
  }
}

class _MicWavePreviewCell extends StatelessWidget {
  const _MicWavePreviewCell({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final prestige = VipVisualResolver.resolve(level);
    const outerSize = 64.0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2435)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Avatar placeholder
                Container(
                  width: outerSize,
                  height: outerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: prestige.primaryColor.withValues(alpha: 0.15),
                    border: Border.all(
                      color: prestige.borderColor,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(Icons.mic_rounded,
                      color: Colors.white70, size: 22),
                ),
                // Mic wave ring
                IgnorePointer(
                  child: VipMicWaveRing(
                    vipLevel: level,
                    isActive: true,
                    isHost: level == 0,
                    outerSize: outerSize,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            level == 0 ? 'No VIP' : 'VIP $level',
            style: TextStyle(
              color: level > 0 ? prestige.nameColor : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            prestige.micWaveRingCount == 1
                ? '1 ring'
                : '${prestige.micWaveRingCount} rings${level >= 7 ? ' + sparkles' : ''}',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ── Entry Banners ─────────────────────────────────────────────────────────────

class _EntryBannersPreview extends StatelessWidget {
  const _EntryBannersPreview();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 10,
      itemBuilder: (ctx, i) {
        final prestige = VipVisualResolver.resolve(i);
        if (prestige.entryTier == VipEntryTier.none) {
          return _NoEntryTile(level: i);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _EntryBannerPreviewTile(level: i),
        );
      },
    );
  }
}

class _NoEntryTile extends StatelessWidget {
  const _NoEntryTile({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2435)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hide_source_rounded,
              color: Color(0xFF6B7280), size: 20),
          const SizedBox(width: 10),
          Text('VIP $level — no entry effect',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
        ],
      ),
    );
  }
}

class _EntryBannerPreviewTile extends StatefulWidget {
  const _EntryBannerPreviewTile({required this.level});
  final int level;

  @override
  State<_EntryBannerPreviewTile> createState() =>
      _EntryBannerPreviewTileState();
}

class _EntryBannerPreviewTileState extends State<_EntryBannerPreviewTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _aura;

  @override
  void initState() {
    super.initState();
    final prestige = VipVisualResolver.resolve(widget.level);
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _aura = Tween<double>(begin: 0.65, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (prestige.isElite) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final prestige = VipVisualResolver.resolve(level);
    final br = BorderRadius.circular(prestige.isElite ? 22 : 18);

    return AnimatedBuilder(
      animation: _aura,
      builder: (ctx, child) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: prestige.isElite ? 12 : 10,
        ),
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: prestige.gradientColors,
          ),
          boxShadow: prestige.buildGlowShadows(pulseFactor: _aura.value),
          border: prestige.isElite
              ? Border.all(
                  color: prestige.borderColor.withValues(alpha: 0.60),
                  width: 1.4)
              : null,
        ),
        child: child,
      ),
      child: Row(
        children: [
          Container(
            width: prestige.isElite ? 42 : 38,
            height: prestige.isElite ? 42 : 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: prestige.primaryColor.withValues(alpha: 0.25),
            ),
            child: Icon(Icons.person_rounded,
                color: prestige.entryTextColor.withValues(alpha: 0.8),
                size: prestige.isElite ? 24 : 20),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: prestige.badgeGradient),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'VIP $level',
              style: TextStyle(
                color: prestige.badgeTextColor,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Preview User entered as VIP $level',
              style: TextStyle(
                color: prestige.entryTextColor,
                fontSize: prestige.isElite ? 13 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (prestige.isLegendary)
            Icon(Icons.local_fire_department_rounded,
                color: prestige.entryTextColor.withValues(alpha: 0.85),
                size: 18),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              prestige.entryTier.name,
              style: TextStyle(
                color: prestige.entryTextColor.withValues(alpha: 0.70),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
