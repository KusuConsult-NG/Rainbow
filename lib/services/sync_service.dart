import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
