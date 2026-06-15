import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/room_music.dart';
import '../services/room_music_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MusicPanel — full room music controller bottom sheet.
// ─────────────────────────────────────────────────────────────────────────────

class MusicPanel extends StatefulWidget {
  const MusicPanel({
    required this.musicService,
    required this.isArabic,
    required this.canManage,
    super.key,
  });

  final RoomMusicService musicService;
  final bool isArabic;
  final bool canManage;

  @override
  State<MusicPanel> createState() => _MusicPanelState();
}

class _MusicPanelState extends State<MusicPanel>
    with SingleTickerProviderStateMixin {
  static const _kPurple = Color(0xFF8B26D9);
  static const _kRed = Color(0xFFE63946);

  late final TabController _tabs;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  RoomMusicService get _svc => widget.musicService;
  bool get _isArabic => widget.isArabic;
  String _t(String ar, String en) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<RoomSong> get _filteredCatalog {
    if (_query.isEmpty) return kRoomMusicCatalog;
    return kRoomMusicCatalog
        .where((s) =>
            s.title.toLowerCase().contains(_query) ||
            s.artist.toLowerCase().contains(_query))
        .toList();
  }

  List<RoomSong> get _filteredPlaylist {
    if (_query.isEmpty) return _svc.playlist;
    return _svc.playlist
        .where((s) =>
            s.title.toLowerCase().contains(_query) ||
            s.artist.toLowerCase().contains(_query))
        .toList();
  }

  List<RoomSong> get _filteredFavorites {
    if (_query.isEmpty) return _svc.favorites;
    return _svc.favorites
        .where((s) =>
            s.title.toLowerCase().contains(_query) ||
            s.artist.toLowerCase().contains(_query))
        .toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _requirePermission(VoidCallback fn) {
    if (widget.canManage) {
      fn();
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(
            _t('ليس لديك صلاحية التحكم بالموسيقى',
                'You do not have permission to control music'),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF2A0F1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _kRed.withValues(alpha: 0.5)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final textDir = _isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDir,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1040), Color(0xFF160C2F), Color(0xFF0C0619)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListenableBuilder(
          listenable: _svc,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            _kPurple.withValues(alpha: 0.35),
                            _kPurple.withValues(alpha: 0.15),
                          ],
                        ),
                        border: Border.all(
                            color: _kPurple.withValues(alpha: 0.5)),
                      ),
                      child: const Icon(Icons.music_note_rounded,
                          color: Color(0xFFC875FF), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _t('موسيقى الغرفة', 'Room Music'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              // Now Playing card
              if (_svc.currentSong != null) ...[
                _NowPlayingCard(
                  svc: _svc,
                  canManage: widget.canManage,
                  isArabic: _isArabic,
                  onRequirePermission: _requirePermission,
                ),
                const SizedBox(height: 4),
              ],

              // Error banner
              if (_svc.error != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kRed.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_rounded,
                          color: Color(0xFFE63946), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _t('تعذّر تشغيل الأغنية', 'Failed to play the track'),
                          style: const TextStyle(
                              color: Color(0xFFE63946), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _t('ابحث عن أغنية...', 'Search music...'),
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: Colors.white.withValues(alpha: 0.4), size: 20),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    suffixIcon: _query.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                            child: Icon(Icons.close_rounded,
                                color: Colors.white.withValues(alpha: 0.5),
                                size: 18),
                          )
                        : null,
                  ),
                ),
              ),

              // Tab bar
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabs,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: _kPurple.withValues(alpha: 0.35),
                    border: Border.all(color: _kPurple.withValues(alpha: 0.5)),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.45),
                  labelStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: _t('المكتبة', 'Library')),
                    Tab(text: _t('قائمة التشغيل', 'Playlist')),
                    Tab(text: _t('المفضلة', 'Favorites')),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Tab views
              Flexible(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _SongList(
                      songs: _filteredCatalog,
                      svc: _svc,
                      isArabic: _isArabic,
                      canManage: widget.canManage,
                      emptyAr: 'لا توجد موسيقى متاحة حالياً',
                      emptyEn: 'No music available yet',
                      showAddToPlaylist: true,
                      onPlay: (song) => _requirePermission(() {
                        HapticFeedback.selectionClick();
                        final idx = kRoomMusicCatalog.indexOf(song);
                        if (idx >= 0) {
                          // If the current playlist IS the catalog (default), play in-place
                          if (_svc.playlist.length == kRoomMusicCatalog.length) {
                            _svc.playSong(idx);
                          } else {
                            _svc.addToPlaylist(song);
                            _svc.playSong(
                                _svc.playlist.indexWhere((s) => s.id == song.id));
                          }
                        }
                      }),
                      onAddToPlaylist: (song) =>
                          _requirePermission(() => _svc.addToPlaylist(song)),
                      onFavorite: (song) => _svc.toggleFavorite(song),
                      onRemove: null,
                    ),
                    _SongList(
                      songs: _filteredPlaylist,
                      svc: _svc,
                      isArabic: _isArabic,
                      canManage: widget.canManage,
                      emptyAr: 'قائمة التشغيل فارغة',
                      emptyEn: 'Playlist is empty',
                      showAddToPlaylist: false,
                      onPlay: (song) => _requirePermission(() {
                        HapticFeedback.selectionClick();
                        _svc.playSong(
                            _svc.playlist.indexWhere((s) => s.id == song.id));
                      }),
                      onAddToPlaylist: null,
                      onFavorite: (song) => _svc.toggleFavorite(song),
                      onRemove: widget.canManage
                          ? (song) => _svc.removeFromPlaylist(song.id)
                          : null,
                    ),
                    _SongList(
                      songs: _filteredFavorites,
                      svc: _svc,
                      isArabic: _isArabic,
                      canManage: widget.canManage,
                      emptyAr: 'لا توجد مفضلات بعد',
                      emptyEn: 'No favorites yet',
                      showAddToPlaylist: true,
                      onPlay: (song) => _requirePermission(() {
                        HapticFeedback.selectionClick();
                        _svc.addToPlaylist(song);
                        _svc.playSong(
                            _svc.playlist.indexWhere((s) => s.id == song.id));
                      }),
                      onAddToPlaylist: (song) =>
                          _requirePermission(() => _svc.addToPlaylist(song)),
                      onFavorite: (song) => _svc.toggleFavorite(song),
                      onRemove: null,
                    ),
                  ],
                ),
              ),

              SizedBox(height: bottomPad + 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Now Playing card — progress, controls, volume, loop/shuffle
// ─────────────────────────────────────────────────────────────────────────────

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.svc,
    required this.canManage,
    required this.isArabic,
    required this.onRequirePermission,
  });

  final RoomMusicService svc;
  final bool canManage;
  final bool isArabic;
  final void Function(VoidCallback) onRequirePermission;

  static const _kPurple = Color(0xFF8B26D9);
  static const _kGold = Color(0xFFF0C15A);

  String _t(String ar, String en) => isArabic ? ar : en;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final song = svc.currentSong!;
    final total = svc.duration ?? Duration.zero;
    final pos = svc.position;
    final progress = total.inMilliseconds > 0
        ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(color: _kPurple.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kPurple.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.20),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Song info
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _kPurple.withValues(alpha: 0.25),
                  border: Border.all(color: _kPurple.withValues(alpha: 0.4)),
                ),
                child: svc.isLoading
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kPurple.withValues(alpha: 0.8),
                          ),
                        ),
                      )
                    : const Icon(Icons.music_note_rounded,
                        color: Color(0xFFC875FF), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Favorite toggle
              GestureDetector(
                onTap: () => svc.toggleFavorite(song),
                child: Icon(
                  svc.isFavorite(song.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: svc.isFavorite(song.id)
                      ? const Color(0xFFE63946)
                      : Colors.white.withValues(alpha: 0.4),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: _kPurple,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: const Color(0xFFC875FF),
              overlayColor: _kPurple.withValues(alpha: 0.25),
            ),
            child: Slider(
              value: progress.toDouble(),
              onChanged: canManage
                  ? (v) => svc.seek(
                      Duration(
                          milliseconds:
                              (v * total.inMilliseconds).round()))
                  : null,
            ),
          ),

          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(pos),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                Text(
                  total.inSeconds > 0 ? _fmt(total) : song.formattedDuration,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlBtn(
                icon: Icons.skip_previous_rounded,
                size: 28,
                onTap: () => onRequirePermission(() {
                  HapticFeedback.selectionClick();
                  svc.previous();
                }),
              ),
              const SizedBox(width: 12),
              // Play / Pause
              GestureDetector(
                onTap: () => onRequirePermission(() {
                  HapticFeedback.mediumImpact();
                  svc.playPause();
                }),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _kPurple,
                        _kPurple.withValues(alpha: 0.7),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kPurple.withValues(alpha: 0.4),
                        blurRadius: 14,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: svc.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          svc.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              _ControlBtn(
                icon: Icons.skip_next_rounded,
                size: 28,
                onTap: () => onRequirePermission(() {
                  HapticFeedback.selectionClick();
                  svc.next();
                }),
              ),
              const SizedBox(width: 16),
              _ControlBtn(
                icon: Icons.stop_rounded,
                size: 22,
                color: const Color(0xFFE63946),
                onTap: () => onRequirePermission(() {
                  HapticFeedback.mediumImpact();
                  svc.stop();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Volume slider
          Row(
            children: [
              Icon(
                svc.volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_down_rounded,
                color: Colors.white.withValues(alpha: 0.45),
                size: 18,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: _kGold,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                    thumbColor: _kGold,
                    overlayColor: _kGold.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: svc.volume,
                    onChanged: (v) => svc.setVolume(v),
                  ),
                ),
              ),
              Icon(
                Icons.volume_up_rounded,
                color: Colors.white.withValues(alpha: 0.45),
                size: 18,
              ),
            ],
          ),

          // Loop + Shuffle toggles
          Row(
            children: [
              _ToggleChip(
                icon: Icons.repeat_one_rounded,
                label: _t('تكرار', 'Loop'),
                active: svc.loop,
                onTap: () => onRequirePermission(svc.toggleLoop),
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                icon: Icons.shuffle_rounded,
                label: _t('عشوائي', 'Shuffle'),
                active: svc.shuffle,
                onTap: () => onRequirePermission(svc.toggleShuffle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({
    required this.icon,
    required this.onTap,
    this.size = 24,
    this.color,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withValues(alpha: 0.75);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.07),
        ),
        child: Icon(icon, color: c, size: size),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  static const _kPurple = Color(0xFF8B26D9);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: active
              ? _kPurple.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.07),
          border: Border.all(
            color: active
                ? _kPurple.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active
                    ? const Color(0xFFC875FF)
                    : Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active
                    ? const Color(0xFFC875FF)
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Song list — shared by all three tabs
// ─────────────────────────────────────────────────────────────────────────────

class _SongList extends StatelessWidget {
  const _SongList({
    required this.songs,
    required this.svc,
    required this.isArabic,
    required this.canManage,
    required this.emptyAr,
    required this.emptyEn,
    required this.showAddToPlaylist,
    required this.onPlay,
    required this.onFavorite,
    this.onAddToPlaylist,
    this.onRemove,
  });

  final List<RoomSong> songs;
  final RoomMusicService svc;
  final bool isArabic;
  final bool canManage;
  final String emptyAr;
  final String emptyEn;
  final bool showAddToPlaylist;
  final void Function(RoomSong) onPlay;
  final void Function(RoomSong) onFavorite;
  final void Function(RoomSong)? onAddToPlaylist;
  final void Function(RoomSong)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_off_rounded,
                  color: Colors.white.withValues(alpha: 0.25), size: 48),
              const SizedBox(height: 12),
              Text(
                isArabic ? emptyAr : emptyEn,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: songs.length,
      itemBuilder: (_, i) => _SongRow(
        song: songs[i],
        svc: svc,
        isPlaying: svc.currentSong?.id == songs[i].id && svc.isPlaying,
        isCurrent: svc.currentSong?.id == songs[i].id,
        isArabic: isArabic,
        showAddToPlaylist: showAddToPlaylist,
        onPlay: () => onPlay(songs[i]),
        onFavorite: () => onFavorite(songs[i]),
        onAddToPlaylist:
            onAddToPlaylist != null ? () => onAddToPlaylist!(songs[i]) : null,
        onRemove: onRemove != null ? () => onRemove!(songs[i]) : null,
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.svc,
    required this.isPlaying,
    required this.isCurrent,
    required this.isArabic,
    required this.showAddToPlaylist,
    required this.onPlay,
    required this.onFavorite,
    this.onAddToPlaylist,
    this.onRemove,
  });

  final RoomSong song;
  final RoomMusicService svc;
  final bool isPlaying;
  final bool isCurrent;
  final bool isArabic;
  final bool showAddToPlaylist;
  final VoidCallback onPlay;
  final VoidCallback onFavorite;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onRemove;

  static const _kPurple = Color(0xFF8B26D9);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCurrent
            ? _kPurple.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: isCurrent
              ? _kPurple.withValues(alpha: 0.40)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                // Play / Waveform icon
                GestureDetector(
                  onTap: onPlay,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCurrent
                          ? _kPurple.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.07),
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: isCurrent
                          ? const Color(0xFFC875FF)
                          : Colors.white.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Song info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? const Color(0xFFC875FF)
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${song.artist} · ${song.formattedDuration}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Favorite
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onFavorite();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          svc.isFavorite(song.id)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: svc.isFavorite(song.id)
                              ? const Color(0xFFE63946)
                              : Colors.white.withValues(alpha: 0.35),
                          size: 18,
                        ),
                      ),
                    ),
                    // Add to playlist
                    if (showAddToPlaylist && onAddToPlaylist != null)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onAddToPlaylist!();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.playlist_add_rounded,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 20,
                          ),
                        ),
                      ),
                    // Remove from playlist
                    if (onRemove != null)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          onRemove!();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.remove_circle_outline_rounded,
                            color: const Color(0xFFE63946).withValues(alpha: 0.7),
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
