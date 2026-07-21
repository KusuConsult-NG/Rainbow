import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/services/alert_service.dart';

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
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        syncPendingData();
      }
    });
  }

  Future<void> syncPendingData() async {
    if (_syncingNotifier.value) return;
    _syncingNotifier.value = true;
    try {
      final alertService = _ref.read(alertServiceProvider);
      await alertService.flushOfflineQueue();
      debugPrint('[SYNC] Device online - offline buffer synced with Supabase.');
    } finally {
      _syncingNotifier.value = false;
    }
  }

  Future<void> queueMediaUpload({
    required String alertId,
    String? filePath,
    String? mediaType,
    List<dynamic>? files,
    String? userId,
  }) async {
    debugPrint('[SYNC] Media upload queued for alert $alertId');
    if (files == null || files.isEmpty) return;
    
    for (var file in files) {
      if (file is String) {
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final filename = file.split('/').last;
          final path = '$alertId/${timestamp}_$filename';
          final bytes = await File(file).readAsBytes();
          await SupabaseConfig.client.storage.from('incident-media').uploadBinary(path, bytes);
          final url = SupabaseConfig.client.storage.from('incident-media').getPublicUrl(path);
          
          final alertData = await SupabaseConfig.client.from('alerts').select('media_urls').eq('id', alertId).single();
          List<dynamic> currentUrls = (alertData['media_urls'] as List<dynamic>?) ?? [];
          currentUrls.add(url);
          await SupabaseConfig.client.from('alerts').update({'media_urls': currentUrls}).eq('id', alertId);
        } catch (e) {
          debugPrint('[SYNC_ERR] Media upload failed: $e');
        }
      }
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
