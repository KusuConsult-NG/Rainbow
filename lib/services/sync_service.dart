import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/services/alert_media.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/cloudinary_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref)..initialize();
});

class SyncService {
  SyncService(this._ref);
  final Ref _ref;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final _syncingNotifier = ValueNotifier<bool>(false);

  ValueListenable<bool> get isSyncing => _syncingNotifier;

  void initialize() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi)) {
        unawaited(syncPendingData());
      }
    });
  }

  Future<void> syncPendingData() async {
    if (_syncingNotifier.value) return;
    _syncingNotifier.value = true;
    try {
      final alertService = _ref.read(alertServiceProvider);
      await alertService.flushOfflineQueue();
      debugPrint('[SYNC] Device online — offline buffer synced with Supabase.');
    } finally {
      _syncingNotifier.value = false;
    }
  }

  /// Upload one or more media files and attach their public URLs to an alert.
  ///
  /// Accepts [files] as either [List<File>] or [List<String>] (paths) — both
  /// are now handled correctly. Previously only String paths were processed,
  /// causing silent data loss when File objects were passed (BUG #15).
  ///
  /// Upload strategy:
  ///   1. Try Cloudinary (signed → unsigned preset fallback).
  ///   2. If Cloudinary fails, fall back to Supabase Storage.
  ///   3. Append all successful URLs to alerts.media_urls atomically.
  Future<List<String>> queueMediaUpload({
    required String alertId,
    List<dynamic>? files, // accepts List<File> OR List<String>
    String? filePath,     // single-file convenience
    String? mediaType,
    String? userId,
  }) async {
    final uploadedUrls = <String>[];

    // Normalise input into a flat List<File>
    final fileList = <File>[];
    if (files != null) {
      for (final item in files) {
        if (item is File) {
          fileList.add(item);
        } else if (item is String && item.isNotEmpty) {
          fileList.add(File(item));
        }
      }
    }
    if (filePath != null && filePath.isNotEmpty) {
      fileList.add(File(filePath));
    }

    if (fileList.isEmpty) {
      debugPrint('[SYNC] queueMediaUpload called with no valid files for alert $alertId');
      return uploadedUrls;
    }

    debugPrint('[SYNC] Uploading ${fileList.length} file(s) for alert $alertId');

    for (var i = 0; i < fileList.length; i++) {
      final file = fileList[i];
      if (!file.existsSync()) {
        debugPrint('[SYNC] File not found, skipping: ${file.path}');
        continue;
      }

      String? url;

      // ── Strategy 1: Cloudinary ──────────────────────────────────────────
      try {
        url = await CloudinaryService.instance.uploadMedia(file);
        if (url != null) {
          debugPrint('[SYNC] Cloudinary upload OK (${i + 1}/${fileList.length}): $url');
        }
      } catch (e) {
        debugPrint('[SYNC] Cloudinary upload error for ${file.path}: $e');
      }

      // ── Strategy 2: Supabase Storage fallback ───────────────────────────
      if (url == null) {
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final filename = file.path.split('/').last;
          final storagePath = '$alertId/${timestamp}_$filename';
          final bytes = await file.readAsBytes();

          await SupabaseConfig.client.storage
              .from('incident-media')
              .uploadBinary(storagePath, bytes);

          url = SupabaseConfig.client.storage
              .from('incident-media')
              .getPublicUrl(storagePath);

          debugPrint('[SYNC] Supabase Storage fallback OK (${i + 1}/${fileList.length}): $url');
        } catch (e) {
          debugPrint('[SYNC] Supabase Storage fallback error for ${file.path}: $e');
        }
      }

      if (url != null) uploadedUrls.add(url);
    }

    // ── Atomic URL append to alerts.media_urls ───────────────────────────
    //
    // This block was labelled atomic and was not: it read media_urls, merged
    // into the copy, and wrote the whole array back. Read-modify-write over a
    // network is lost-update by construction, and this loop is the worst place
    // for it — a queue of uploads racing the duress screen's own unawaited
    // attach, both reading the same array, the later write erasing the earlier.
    //
    // append_alert_media() does it in one locked statement. See
    // lib/services/alert_media.dart and migration 20261010000000.
    if (uploadedUrls.isNotEmpty) {
      final res = await AlertMedia.append(alertId, uploadedUrls);
      if (res.isOnTheIncident) {
        debugPrint('[SYNC] Attached ${res.added} of ${uploadedUrls.length} '
            'URL(s) to alert $alertId (total ${res.total})');
      } else {
        // A refusal is not a transport failure and the difference matters when
        // reading these logs: one means this account has no part in the
        // incident, the other means try again.
        debugPrint('[SYNC] Could NOT attach ${uploadedUrls.length} URL(s) to '
            'alert $alertId: ${res.outcome.name}${res.error == null ? '' : ' — ${res.error}'}');
      }
    } else {
      debugPrint('[SYNC] No files successfully uploaded for alert $alertId');
    }

    return uploadedUrls;
  }

  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
  }
}
