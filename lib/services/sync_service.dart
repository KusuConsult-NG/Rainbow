// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/sqlite_service.dart';

/// Documentation for this public member.

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref)..initialize();
});

/// Documentation for this public member.

class SyncService {
  /// Documentation for this public member.
  SyncService(this._ref);
  final Ref _ref;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  final _syncingNotifier = ValueNotifier<bool>(false);

  /// Documentation for this public member.
  ValueListenable<bool> get isSyncing => _syncingNotifier;

  /// Documentation for this public member.

  void initialize() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(_triggerSync());
      }
    });
    // Initial check
    unawaited(_triggerSync());
  }

  /// Documentation for this public member.

  Future<void> queueMediaUpload({
    required String alertId,
    required List<File> files,
    required String userId,
  }) async {
    final sqlite = _ref.read(sqliteServiceProvider);
    final appDir = await getApplicationDocumentsDirectory();

    for (final file in files) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final localFile = await file.copy('${appDir.path}/$fileName');
      await sqlite.enqueueMedia(
        localAlertId: alertId,
        localFilePath: localFile.path,
      );
    }
    unawaited(_triggerSync());
  }

  Future<void> _triggerSync() async {
    if (_syncingNotifier.value) return;

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return;

    _syncingNotifier.value = true;

    try {
      // 1. Flush Offline Alerts (Delegated to AlertService)
      final mappings =
          await _ref.read(alertServiceProvider).flushOfflineQueue();

      // 2. Remap Media IDs for newly synced alerts
      final sqlite = _ref.read(sqliteServiceProvider);
      for (final entry in mappings.entries) {
        await sqlite.remapAlertId(entry.key, entry.value);
      }

      // 3. Flush Media Queue
      await _flushMediaQueue();
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[SYNC_MASTER_ERR] $e');
    } finally {
      _syncingNotifier.value = false;
    }
  }

  Future<void> _flushMediaQueue() async {
    final sqlite = _ref.read(sqliteServiceProvider);
    final mediaList = await sqlite.getAllPendingMedia();
    if (mediaList.isEmpty) return;

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in mediaList) {
      final alertId = row['local_alert_id'] as String;
      if (alertId.startsWith('OFFLINE_')) {
        continue; // Wait until alert is fully synchronized to Firestore
      }
      grouped.putIfAbsent(alertId, () => []).add(row);
    }

    for (final entry in grouped.entries) {
      final alertId = entry.key;
      final rows = entry.value;
      final urls = <String>[];

      for (final row in rows) {
        final mediaId = row['id'] as int;
        final path = row['local_file_path'] as String;
        final file = File(path);

        try {
          if (file.existsSync()) {
            final fileName = path.split('/').last;
            final storageRef = _storage.ref().child('alerts/uploads/$fileName');
            await storageRef.putFile(file);
            final url = await storageRef.getDownloadURL();
            urls.add(url);
            await sqlite.updateMediaStatus(mediaId, 'COMPLETE', remoteStoragePath: url);
            await file.delete();
          } else {
            await sqlite.deleteMedia(mediaId);
          }
        } catch (e) {
          debugPrint('[SYNC_MEDIA_ERR] Failed to upload media ID $mediaId: $e');
          await sqlite.updateMediaStatus(mediaId, 'FAILED');
        }
      }

      if (urls.isNotEmpty) {
        try {
          await _db.collection('alerts').doc(alertId).update({
            'attachments': FieldValue.arrayUnion(urls),
            'sync_status': 'COMPLETED',
          });
          for (final row in rows) {
            await sqlite.deleteMedia(row['id'] as int);
          }
        } catch (e) {
          debugPrint('[SYNC_FIRESTORE_ERR] Failed to update attachments: $e');
        }
      }
    }
  }

  /// Documentation for this public member.

  void dispose() {
    if (_connectivitySubscription != null) {
      unawaited(_connectivitySubscription!.cancel());
    }
  }
}
