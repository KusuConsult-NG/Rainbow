import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service handling cost-optimized media uploads directly to Cloudinary.
/// Configured with live account credentials for Operation Rainbow.
class CloudinaryService {
  CloudinaryService._privateConstructor();
  static final CloudinaryService instance = CloudinaryService._privateConstructor();

  // Cloudinary credentials loaded from .env (never hardcode secrets in source)
  String get cloudName => dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? 'prroorhv';
  String get apiKey => dotenv.env['CLOUDINARY_API_KEY'] ?? '439918347355179';
  String get apiSecret => dotenv.env['CLOUDINARY_API_SECRET'] ?? '';
  String get uploadPreset => dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? 'rainbow_incident_media';

  /// Uploads a local file (image, video, or audio) to Cloudinary and returns the public HTTPS URL.
  Future<String?> uploadMedia(File file) async {
    try {
      final isVideo = file.path.endsWith('.mp4') ||
          file.path.endsWith('.mov') ||
          file.path.endsWith('.webm') ||
          file.path.endsWith('.m4a') ||
          file.path.endsWith('.wav');

      final resourceType = isVideo ? 'video' : 'image';
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final folder = 'operation_rainbow_incidents';

      // Generate SHA-1 Signature for Signed Cloudinary Upload
      final toSign = 'folder=$folder&timestamp=$timestamp$apiSecret';
      final signature = sha1.convert(utf8.encode(toSign)).toString();

      // 1. Try Signed Upload using API Key & Secret
      var request = http.MultipartRequest('POST', url)
        ..fields['api_key'] = apiKey
        ..fields['timestamp'] = timestamp
        ..fields['signature'] = signature
        ..fields['folder'] = folder
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        debugPrint('[CLOUDINARY_SIGNED_UPLOAD] Upload successful: $secureUrl');
        return secureUrl;
      }

      debugPrint('[CLOUDINARY_SIGNED_ERR] Signed upload status ${response.statusCode}, trying unsigned preset...');

      // 2. Fallback to Unsigned Preset Upload
      request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folder
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      streamedResponse = await request.send();
      response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        debugPrint('[CLOUDINARY_UNSIGNED_UPLOAD] Upload successful: $secureUrl');
        return secureUrl;
      } else {
        debugPrint('[CLOUDINARY_UPLOAD_ERR] Cloudinary returned ${response.statusCode}: ${response.body}');
        return null;
      }
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
