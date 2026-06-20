import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/room_music.dart';
import '../services/room_music_service.dart';
import '../services/room_music_upload_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';

// -----------------------------------------------------------------------------
// MusicPanel - Room Music bottom sheet.
//
// HOST view:   Now Playing card -> Add Music buttons -> Saved Tracks list
// MEMBER view: Now Playing (read-only) -> Volume + mute only
// -----------------------------------------------------------------------------

class MusicPanel extends StatefulWidget {
  const MusicPanel({
    required this.musicService,
    required this.isArabic,
    required this.canManage,
    this.roomId,
    this.uploadService,
    this.onTrackSelected,
    super.key,
  });

  final RoomMusicService musicService;
  final bool isArabic;
  final bool canManage;

  /// Required when [canManage] is true so tracks can be fetched/uploaded.
  final String? roomId;

  /// Handles storage uploads and track persistence.
  final RoomMusicUploadService? uploadService;

  /// Called when the host selects a track to play.
  /// If null, falls back to musicService.addToPlaylist + playSong.
  final void Function(RoomSong song)? onTrackSelected;

  @override
  State<MusicPanel> createState() => _MusicPanelState();
}

class _MusicPanelState extends State<MusicPanel> {
  static const _purple = Color(0xFF8B26D9);
  static const _purpleLight = Color(0xFFC875FF);
  static const _red = Color(0xFFE63946);
  static const _gold = Color(0xFFF0C15A);

  RoomMusicService get _svc => widget.musicService;
  bool get _isArabic => context.isArabic;
  String _t(String ar, String en) => _isArabic ? ar : en;

  List<RoomSong> _savedTracks = [];
  List<RoomSong> _userLibrary = [];
  bool _loadingTracks = false;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    if (widget.canManage && widget.roomId != null) {
      _loadTracks();
    }
  }

  Future<void> _loadTracks() async {
    if (widget.uploadService == null || widget.roomId == null) return;
    setState(() => _loadingTracks = true);
    final results = await Future.wait([
      widget.uploadService!.fetchTracks(widget.roomId!),
      widget.uploadService!.fetchUserTracks(),
    ]);
    if (!mounted) return;
    final roomTracks = results[0];
    final userTracks = results[1];
    // Personal library = user's tracks NOT already in this room
    final roomIds = roomTracks.map((s) => s.id).toSet();
    setState(() {
      _savedTracks = roomTracks;
      _userLibrary = userTracks.where((s) => !roomIds.contains(s.id)).toList();
      _loadingTracks = false;
    });
  }

  void _playTrack(RoomSong song) {
    if (widget.onTrackSelected != null) {
      widget.onTrackSelected!(song);
    } else {
      _svc.addToPlaylist(song);
      _svc.playSong(_svc.playlist.indexWhere((s) => s.id == song.id));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      }
    });
  }

  // -- Import from phone -----------------------------------------------------

  Future<void> _importFromPhone() async {
    if (!widget.canManage) return;
    final upSvc = widget.uploadService;
    final roomId = widget.roomId;
    if (upSvc == null || roomId == null) return;

    setState(() { _uploading = true; _uploadProgress = 0; _uploadError = null; });

    final song = await upSvc.uploadAudioFile(
      roomId,
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );

    if (!mounted) return;
    if (song != null) {
      setState(() { _savedTracks.insert(0, song); _uploading = false; });
      _playTrack(song);
      _showToast(_t('تم رفع المقطع وتشغيله ✓', 'Track uploaded & playing ✓'));
    } else {
      setState(() { _uploading = false; _uploadError = _t('فشل رفع الملف', 'Upload failed'); });
    }
  }

  // -- Paste URL ------------------------------------------------------------

  Future<void> _pasteUrl() async {
    if (!widget.canManage) return;
    final upSvc = widget.uploadService;
    final roomId = widget.roomId;
    if (upSvc == null || roomId == null) return;

    final urlCtrl = TextEditingController();
    final titleCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1040),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            _t('أضف رابط مقطع موسيقي', 'Paste a music link'),
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(
                ctrl: urlCtrl,
                hint: _t('https://example.com/song.mp3', 'https://example.com/song.mp3'),
                label: _t('رابط الملف الصوتي', 'Audio URL'),
              ),
              const SizedBox(height: 12),
              _dialogField(
                ctrl: titleCtrl,
                hint: _t('اسم المقطع', 'Track title'),
                label: _t('الاسم (اختياري)', 'Title (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('إلغاء', 'Cancel'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t('إضافة', 'Add'),
                  style: const TextStyle(color: _purpleLight, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final url = urlCtrl.text.trim();
    if (url.isEmpty || !Uri.tryParse(url)!.hasAbsolutePath) {
      _showToast(_t('الرابط غير صالح', 'Invalid URL'));
      return;
    }

    setState(() { _uploading = true; _uploadError = null; });
    final song = await upSvc.addTrackFromUrl(
      roomId,
      url: url,
      title: titleCtrl.text.trim().isEmpty
          ? _t('مقطع موسيقي', 'Music Track')
          : titleCtrl.text.trim(),
    );

    if (!mounted) return;
    if (song != null) {
      setState(() { _savedTracks.insert(0, song); _uploading = false; });
      _playTrack(song);
      _showToast(_t('تمت إضافة المقطع ✓', 'Track added ✓'));
    } else {
      setState(() { _uploading = false; _uploadError = _t('فشلت الإضافة', 'Failed to add track'); });
    }
  }

  // -- Scan QR --------------------------------------------------------------

  Future<void> _scanQr() async {
    if (!widget.canManage) return;

    String? scannedUrl;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _QrScannerSheet(
        isArabic: _isArabic,
        onScanned: (url) {
          scannedUrl = url;
          Navigator.pop(ctx);
        },
      ),
    );

    if (scannedUrl == null || scannedUrl!.isEmpty) return;
    final upSvc = widget.uploadService;
    final roomId = widget.roomId;
    if (upSvc == null || roomId == null) return;

    setState(() { _uploading = true; _uploadError = null; });
    final song = await upSvc.addTrackFromUrl(
      roomId,
      url: scannedUrl!,
      title: _t('مقطع QR', 'QR Track'),
    );

    if (!mounted) return;
    if (song != null) {
      setState(() { _savedTracks.insert(0, song); _uploading = false; });
      _playTrack(song);
      _showToast(_t('تم مسح رمز QR وإضافة المقطع ✓', 'QR scanned & track added ✓'));
    } else {
      setState(() { _uploading = false; _uploadError = _t('فشل إضافة المقطع', 'Failed to add track'); });
    }
  }

  // -- Delete track ----------------------------------------------------------

  Future<void> _deleteTrack(RoomSong track) async {
    final upSvc = widget.uploadService;
    if (upSvc == null) return;
    await upSvc.deleteTrack(track.id);
    if (mounted) {
      setState(() => _savedTracks.removeWhere((t) => t.id == track.id));
    }
    // If this track was playing, stop it
    if (_svc.currentSong?.id == track.id) {
      unawaited(_svc.stop());
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A0F4A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));
  }

  Widget _dialogField({
    required TextEditingController ctrl,
    required String hint,
    required String label,
  }) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _purple.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _purple.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _purple),
        ),
      ),
    );
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
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
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              _header(),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  shrinkWrap: true,
                  children: [
                    // Now playing
                    if (_svc.currentSong != null) ...[
                      _NowPlayingCard(
                        svc: _svc,
                        canManage: widget.canManage,
                        isArabic: _isArabic,
                      ),
                      const SizedBox(height: 4),
                    ] else ...[
                      _emptyNowPlaying(),
                    ],

                    // Upload progress
                    if (_uploading) _uploadProgressBar(),

                    // Error
                    if (_uploadError != null) _errorBanner(),

                    // HOST: Add Music section
                    if (widget.canManage) ...[
                      _sectionHeader(_t('إضافة موسيقى', 'Add Music')),
                      _addMusicButtons(),
                      const SizedBox(height: 4),
                      _sectionHeader(_t('مقاطع الغرفة', 'Room Tracks')),
                      _savedTracksList(),
                      if (_userLibrary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _sectionHeader(_t('مكتبتي', 'My Library')),
                        _userLibraryList(),
                      ],
                    ] else ...[
                      // MEMBER: volume/mute only
                      _memberControls(),
                    ],

                    SizedBox(height: bottomPad + 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Sub-widgets -----------------------------------------------------------

  Widget _handle() => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      width: 36, height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [
              _purple.withValues(alpha: 0.35),
              _purple.withValues(alpha: 0.15),
            ]),
            border: Border.all(color: _purple.withValues(alpha: 0.5)),
          ),
          child: const Icon(Icons.music_note_rounded, color: _purpleLight, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          _t('موسيقى الغرفة', 'Room Music'),
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _emptyNowPlaying() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: Colors.white.withValues(alpha: 0.04),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Row(
      children: [
        Icon(Icons.music_off_rounded, color: Colors.white.withValues(alpha: 0.25), size: 28),
        const SizedBox(width: 12),
        Text(
          _t('لا توجد موسيقى قيد التشغيل', 'No music playing'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
        ),
      ],
    ),
  );

  Widget _uploadProgressBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('جارٍ رفع الملف...', 'Uploading...'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: _uploadProgress,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation<Color>(_purple),
          borderRadius: BorderRadius.circular(4),
          minHeight: 4,
        ),
      ],
    ),
  );

  Widget _errorBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: _red.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _red.withValues(alpha: 0.4)),
    ),
    child: Row(children: [
      const Icon(Icons.error_rounded, color: _red, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(_uploadError!, style: const TextStyle(color: _red, fontSize: 12)),
      ),
      GestureDetector(
        onTap: () => setState(() => _uploadError = null),
        child: Icon(Icons.close_rounded, color: _red.withValues(alpha: 0.6), size: 16),
      ),
    ]),
  );

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _addMusicButtons() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Expanded(child: _AddButton(
          icon: Icons.smartphone_rounded,
          label: _t('من الهاتف', 'From Phone'),
          onTap: _uploading ? null : _importFromPhone,
        )),
        const SizedBox(width: 8),
        Expanded(child: _AddButton(
          icon: Icons.link_rounded,
          label: _t('لصق رابط', 'Paste Link'),
          onTap: _uploading ? null : _pasteUrl,
        )),
        const SizedBox(width: 8),
        Expanded(child: _AddButton(
          icon: Icons.qr_code_scanner_rounded,
          label: _t('مسح QR', 'Scan QR'),
          onTap: _uploading ? null : _scanQr,
        )),
      ],
    ),
  );

  Widget _savedTracksList() {
    if (_loadingTracks) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(
          strokeWidth: 2, color: _purple,
        )),
      );
    }

    // Combine DB tracks + static catalog for the host
    final allTracks = [
      ..._savedTracks,
      ...kRoomMusicCatalog.where((c) => !_savedTracks.any((t) => t.url == c.url)),
    ];

    if (allTracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_rounded,
                color: Colors.white.withValues(alpha: 0.2), size: 44),
            const SizedBox(height: 10),
            Text(
              _t('لا توجد مقاطع بعد\nاستورد ملفاً أو أضف رابطاً',
                  'No tracks yet\nImport a file or paste a link'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: allTracks.map((track) => _TrackRow(
        track: track,
        isCurrent: _svc.currentSong?.id == track.id,
        isPlaying: _svc.currentSong?.id == track.id && _svc.isPlaying,
        canDelete: _savedTracks.any((t) => t.id == track.id),
        onPlay: () => _playTrack(track),
        onDelete: () => _deleteTrack(track),
      )).toList(),
    );
  }

  Widget _userLibraryList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _userLibrary.map((track) => _TrackRow(
        track: track,
        isCurrent: _svc.currentSong?.id == track.id,
        isPlaying: _svc.currentSong?.id == track.id && _svc.isPlaying,
        canDelete: false,
        onPlay: () {
          _playTrack(track);
          // Also insert into this room's list so it appears in Room Tracks
          if (!_savedTracks.any((t) => t.id == track.id)) {
            setState(() {
              _savedTracks.insert(0, track);
              _userLibrary.removeWhere((t) => t.id == track.id);
            });
          }
        },
        onDelete: () {},
      )).toList(),
    );
  }

  Widget _memberControls() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: Colors.white.withValues(alpha: 0.04),
      border: Border.all(color: _purple.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('التحكم بالصوت', 'Volume Control'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12, fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _svc.setVolume(_svc.volume == 0 ? 1.0 : 0.0);
            },
            child: Icon(
              _svc.volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
              color: _svc.volume == 0 ? _red : Colors.white.withValues(alpha: 0.5),
              size: 22,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: _gold,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: _gold,
                overlayColor: _gold.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: _svc.volume,
                onChanged: (v) => _svc.setVolume(v),
              ),
            ),
          ),
          Icon(Icons.volume_up_rounded, color: Colors.white.withValues(alpha: 0.5), size: 22),
        ]),
        const SizedBox(height: 4),
        Center(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _svc.setVolume(_svc.volume == 0 ? 1.0 : 0.0);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: _svc.volume == 0
                    ? _red.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.07),
                border: Border.all(
                  color: _svc.volume == 0
                      ? _red.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _svc.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 14,
                    color: _svc.volume == 0 ? _red : Colors.white.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _svc.volume == 0
                        ? _t('إلغاء الكتم', 'Unmute')
                        : _t('كتم الموسيقى', 'Mute Music'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _svc.volume == 0 ? _red : Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// -----------------------------------------------------------------------------
// Now Playing card
// -----------------------------------------------------------------------------

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.svc,
    required this.canManage,
    required this.isArabic,
  });

  final RoomMusicService svc;
  final bool canManage;
  final bool isArabic;

  static const _purple = Color(0xFF8B26D9);
  static const _purpleLight = Color(0xFFC875FF);
  static const _gold = Color(0xFFF0C15A);
  static const _red = Color(0xFFE63946);

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
        color: Colors.black.withValues(alpha: 0.25),
        border: Border.all(color: _purple.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_purple.withValues(alpha: 0.18), Colors.black.withValues(alpha: 0.20)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Song info row
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _purple.withValues(alpha: 0.25),
                border: Border.all(color: _purple.withValues(alpha: 0.4)),
              ),
              child: svc.isLoading
                  ? Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _purple.withValues(alpha: 0.8))))
                  : const Icon(Icons.music_note_rounded, color: _purpleLight, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text(song.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
              ],
            )),
            if (!canManage)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _purple.withValues(alpha: 0.15),
                  border: Border.all(color: _purple.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _t('مباشر', 'LIVE'),
                  style: const TextStyle(color: _purpleLight, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
          ]),
          const SizedBox(height: 12),

          // Progress bar (seek-enabled for host, read-only for member)
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: canManage ? 7 : 0),
              overlayShape: RoundSliderOverlayShape(overlayRadius: canManage ? 14 : 0),
              activeTrackColor: _purple,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: _purpleLight,
              overlayColor: _purple.withValues(alpha: 0.25),
            ),
            child: Slider(
              value: progress.toDouble(),
              onChanged: canManage
                  ? (v) => svc.seek(Duration(milliseconds: (v * total.inMilliseconds).round()))
                  : null,
            ),
          ),

          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(pos),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                Text(total.inSeconds > 0 ? _fmt(total) : song.formattedDuration,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Playback controls (host) or static label (member)
          if (canManage) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _CtrlBtn(icon: Icons.skip_previous_rounded, size: 28, onTap: svc.previous),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () { HapticFeedback.mediumImpact(); svc.playPause(); },
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_purple, _purple.withValues(alpha: 0.7)]),
                    boxShadow: [BoxShadow(color: _purple.withValues(alpha: 0.4), blurRadius: 14, spreadRadius: -2)],
                  ),
                  child: svc.isLoading
                      ? const Padding(padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Icon(svc.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(width: 12),
              _CtrlBtn(icon: Icons.skip_next_rounded, size: 28, onTap: svc.next),
              const SizedBox(width: 16),
              _CtrlBtn(
                icon: Icons.stop_rounded, size: 22, color: _red,
                onTap: () { HapticFeedback.mediumImpact(); svc.stop(); },
              ),
            ]),
            const SizedBox(height: 12),
          ],

          // Volume row (all users)
          Row(children: [
            GestureDetector(
              onTap: () => svc.setVolume(svc.volume == 0 ? 1.0 : 0.0),
              child: Icon(
                svc.volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
                color: svc.volume == 0 ? _red : Colors.white.withValues(alpha: 0.4),
                size: 18,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: _gold,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  thumbColor: _gold,
                  overlayColor: _gold.withValues(alpha: 0.2),
                ),
                child: Slider(value: svc.volume, onChanged: (v) => svc.setVolume(v)),
              ),
            ),
            Icon(Icons.volume_up_rounded, color: Colors.white.withValues(alpha: 0.4), size: 18),
          ]),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  const _CtrlBtn({required this.icon, required this.onTap, this.size = 24, this.color});
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
        width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
        child: Icon(icon, color: c, size: size),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Add Music button (grid cell)
// -----------------------------------------------------------------------------

class _AddButton extends StatelessWidget {
  const _AddButton({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  static const _purple = Color(0xFF8B26D9);
  static const _purpleLight = Color(0xFFC875FF);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap != null ? () { HapticFeedback.selectionClick(); onTap!(); } : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _purple.withValues(alpha: 0.1),
            border: Border.all(color: _purple.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _purpleLight, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _purpleLight, fontSize: 11, fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Track row in Saved Tracks list
// -----------------------------------------------------------------------------

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.canDelete,
    required this.onPlay,
    required this.onDelete,
  });

  final RoomSong track;
  final bool isCurrent;
  final bool isPlaying;
  final bool canDelete;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  static const _purple = Color(0xFF8B26D9);
  static const _purpleLight = Color(0xFFC875FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCurrent ? _purple.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: isCurrent ? _purple.withValues(alpha: 0.40) : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              // Play icon
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent ? _purple.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: isCurrent ? _purpleLight : Colors.white.withValues(alpha: 0.6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              // Info
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? _purpleLight : Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 13,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    '${track.artist.isEmpty ? "—" : track.artist} · ${track.formattedDuration}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                  ),
                ],
              )),
              // Delete (only for DB tracks, not catalog)
              if (canDelete)
                GestureDetector(
                  onTap: () { HapticFeedback.mediumImpact(); onDelete(); },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 18,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// QR scanner bottom sheet
// -----------------------------------------------------------------------------

class _QrScannerSheet extends StatefulWidget {
  const _QrScannerSheet({required this.isArabic, required this.onScanned});
  final bool isArabic;
  final void Function(String url) onScanned;

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  MobileScannerController? _ctrl;
  bool _scanned = false;
  String? _error;

  String _t(String ar, String en) => context.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    try {
      _ctrl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
    } catch (e) {
      _error = e.toString();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.hasAbsolutePath && raw.startsWith('http')) {
        _scanned = true;
        widget.onScanned(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.65;
    return Container(
      height: h,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text(
            _t('امسح رمز QR الخاص بمقطع موسيقي', 'Scan a music QR code'),
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          _t('يجب أن يحتوي الرمز على رابط مقطع صوتي', 'QR must contain an audio file URL'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _t('تعذّر تشغيل الكاميرا', 'Could not open camera'),
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(children: [
                    MobileScanner(controller: _ctrl!, onDetect: _onDetect),
                    Center(
                      child: Container(
                        width: 200, height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF8B26D9), width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ]),
                ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            _t('إلغاء', 'Cancel'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
