import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/room_music.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoomMusicUploadService
//
// Handles everything that touches Supabase Storage and the room_music_tracks
// table.  Not a ChangeNotifier — callers await the returned futures.
// ─────────────────────────────────────────────────────────────────────────────

class RoomMusicUploadService {
  const RoomMusicUploadService();

  SupabaseClient get _db => SupabaseService.requiredClient;

  // ── Fetch saved tracks for a room ─────────────────────────────────────────

  Future<List<RoomSong>> fetchTracks(String roomId) async {
    try {
      final rows = await _db
          .from('room_music_tracks')
          .select()
          .eq('room_id', roomId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      return (rows as List<dynamic>)
          .map((r) => RoomSong.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[MusicUpload] fetchTracks error: $e');
      return [];
    }
  }

  // ── Upload an audio file from the device ──────────────────────────────────

  /// Picks a file (if [file] is null), uploads it to the room_music bucket,
  /// saves a track row via RPC, and returns the new [RoomSong].
  /// Returns null on any failure.
  Future<RoomSong?> uploadAudioFile(
    String roomId, {
    PlatformFile? file,
    void Function(double progress)? onProgress,
  }) async {
    PlatformFile? picked = file;
    if (picked == null) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      picked = result.files.first;
    }

    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;

    final bytes = _getBytes(picked);
    if (bytes == null) return null;

    // Sanitize file name and build storage path
    final safeName = picked.name
        .replaceAll(RegExp(r'[^\w.\-]'), '_')
        .toLowerCase();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$uid/$roomId/${ts}_$safeName';

    try {
      onProgress?.call(0.1);

      await _db.storage
          .from('room_music')
          .uploadBinary(storagePath, bytes,
              fileOptions: FileOptions(
                contentType: _mimeType(picked.name),
                upsert: false,
              ));

      onProgress?.call(0.8);

      final publicUrl = _db.storage
          .from('room_music')
          .getPublicUrl(storagePath);

      // Strip the file extension to use as the default title
      final title = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');

      final result = await _db.rpc(
        'add_room_music_track',
        params: {
          'p_room_id': roomId,
          'p_title': title,
          'p_track_url': publicUrl,
          'p_storage_path': storagePath,
          'p_source': 'upload',
        },
      );

      onProgress?.call(1.0);

      if (result == null) return null;
      return RoomSong.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('[MusicUpload] uploadAudioFile error: $e');
      return null;
    }
  }

  // ── Add a track from a URL (paste link) ───────────────────────────────────

  Future<RoomSong?> addTrackFromUrl(
    String roomId, {
    required String url,
    required String title,
    String? artist,
  }) async {
    try {
      final result = await _db.rpc(
        'add_room_music_track',
        params: {
          'p_room_id': roomId,
          'p_title': title.trim().isEmpty ? 'Track' : title.trim(),
          'p_track_url': url.trim(),
          if (artist != null && artist.trim().isNotEmpty)
            'p_artist': artist.trim(),
          'p_source': 'url',
        },
      );
      if (result == null) return null;
      return RoomSong.fromJson(result as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('[MusicUpload] addTrackFromUrl error: $e');
      return null;
    }
  }

  // ── Delete a track ────────────────────────────────────────────────────────

  Future<void> deleteTrack(String trackId) async {
    try {
      await _db.rpc('delete_room_music_track', params: {'p_track_id': trackId});
    } catch (e) {
      if (kDebugMode) debugPrint('[MusicUpload] deleteTrack error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Uint8List? _getBytes(PlatformFile file) {
    if (file.bytes != null) return file.bytes;
    final path = file.path;
    if (path == null) return null;
    try {
      return File(path).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  String _mimeType(String name) {
    final ext = name.split('.').last.toLowerCase();
    const map = {
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'ogg': 'audio/ogg',
    };
    return map[ext] ?? 'audio/mpeg';
  }
}
