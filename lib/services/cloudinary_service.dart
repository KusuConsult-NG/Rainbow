import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rainbow_app/core/config/app_config.dart';

/// Cost-optimised media uploads to Cloudinary using an UNSIGNED upload preset.
///
/// The previous implementation attempted a signed upload first, using an API key
/// and secret read from `.env`. That path was dead code — `CLOUDINARY_API_SECRET`
/// defaulted to `''`, so the SHA-1 signature was always wrong, every signed
/// upload was rejected, and it silently fell through to the unsigned preset
/// anyway. It was also unsafe by construction: `.env` is bundled as a Flutter
/// asset, so any secret placed there ships inside the APK. Signed uploads must be
/// brokered by a server that holds the secret.
class CloudinaryService {
  CloudinaryService._privateConstructor();
  static final CloudinaryService instance = CloudinaryService._privateConstructor();

  // No hardcoded fallbacks: an unconfigured upload must fail visibly, not
  // silently target someone else's Cloudinary account.
  String? get cloudName => AppConfig.cloudinaryCloudName;
  String? get uploadPreset => AppConfig.cloudinaryUploadPreset;

  /// Uploads a local file (image, video, or audio) and returns the public HTTPS URL.
  ///
  /// Returns `null` on any failure, including missing configuration.
  Future<String?> uploadMedia(File file) async {
    final cloud = cloudName;
    final preset = uploadPreset;
    if (cloud == null || preset == null) {
      debugPrint(
        '[CLOUDINARY_CONFIG_ERR] CLOUDINARY_CLOUD_NAME / CLOUDINARY_UPLOAD_PRESET '
        'not configured — upload skipped.',
      );
      return null;
    }

    try {
      final isVideo = file.path.endsWith('.mp4') ||
          file.path.endsWith('.mov') ||
          file.path.endsWith('.webm') ||
          file.path.endsWith('.m4a') ||
          file.path.endsWith('.wav');

      final resourceType = isVideo ? 'video' : 'image';
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloud/$resourceType/upload',
      );
      const folder = 'operation_rainbow_incidents';

      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = preset
        ..fields['folder'] = folder
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        debugPrint('[CLOUDINARY_UPLOAD] Upload successful: $secureUrl');
        return secureUrl;
      }

      debugPrint(
        '[CLOUDINARY_UPLOAD_ERR] Cloudinary returned '
        '${response.statusCode}: ${response.body}',
      );
      return null;
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[CLOUDINARY_UPLOAD_ERR] Exception uploading to Cloudinary: $e');
      return null;
    }
  }

  /// Batch uploads multiple media files to Cloudinary concurrently.
  Future<List<String>> uploadBatch(List<File> files) async {
    final urls = <String>[];
    for (final file in files) {
      if (await file.exists()) {
        final url = await uploadMedia(file);
        if (url != null) {
          urls.add(url);
        }
      }
    }
    return urls;
  }
}
