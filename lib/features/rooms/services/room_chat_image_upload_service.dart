import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

class RoomChatImageResult {
  const RoomChatImageResult({required this.url, required this.path});
  final String url;
  final String path;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class RoomChatImageUploadService {
  const RoomChatImageUploadService();

  static const String _bucket = 'room_chat_images';
  static const int _maxBytes = 5 * 1024 * 1024; // 5 MB
  static const List<String> _allowedExtensions = [
    'jpg', 'jpeg', 'png', 'webp',
  ];

  /// Opens the gallery picker and, if the user selected an image, validates
  /// and uploads it to Supabase Storage.
  ///
  /// Returns [null] if the user cancelled.
  /// Throws a [StateError] or [ArgumentError] on validation failure.
  /// Throws on upload failure.
  Future<RoomChatImageResult?> pickAndUpload({required String userId}) async {
    debugPrint('[RoomImage] pickAndUpload called userId=$userId');
    final picker = ImagePicker();
    debugPrint('[RoomImage] picker start');
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null) {
      debugPrint('[RoomImage] picker cancelled');
      return null;
    }
    debugPrint('[RoomImage] picked path=${picked.path} name=${picked.name}');

    // Extension check
    final ext = picked.name.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      throw ArgumentError(
        'Unsupported format. Please pick a JPG, PNG, or WebP image.',
      );
    }

    // Size check
    final file = File(picked.path);
    final size = await file.length();
    if (size > _maxBytes) {
      throw ArgumentError('Image is too large. Maximum size is 5 MB.');
    }

    // Generate a unique path: userId/timestamp_randomSuffix.ext
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$userId/${ts}_${picked.name.hashCode.abs()}.$ext';

    final client = SupabaseService.requiredClient;
    debugPrint('[RoomImage] upload start bucket=$_bucket path=$storagePath ext=$ext size=${await file.length()}');
    await client.storage.from(_bucket).upload(
      storagePath,
      file,
      fileOptions: FileOptions(
        contentType: _mimeType(ext),
        upsert: false,
      ),
    );

    debugPrint('[RoomImage] upload success path=$storagePath');
    final publicUrl =
        client.storage.from(_bucket).getPublicUrl(storagePath);
    debugPrint('[RoomImage] public url=$publicUrl');

    return RoomChatImageResult(url: publicUrl, path: storagePath);
  }

  static String _mimeType(String ext) => switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png'           => 'image/png',
        'webp'          => 'image/webp',
        _               => 'image/jpeg',
      };
}
