import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/sqlite_service.dart';

/// Documentation for this public member.

final alertServiceProvider = Provider<AlertService>((ref) {
  return AlertService(ref.read(sqliteServiceProvider));
});

/// Handles synchronization of Alert and Incident Report data
/// between the local client and the Supabase `alerts` table.
class AlertService {
  /// Documentation for this public member.
  AlertService([SqliteService? sqliteService])
      : _sqliteService = sqliteService ?? SqliteService();

  final SqliteService _sqliteService;

  /// Submits an emergency SOS or incident alert to Supabase.
  Future<String?> submitAlert({
    required String type,
    required String description,
    required String reportedBy,
    double? latitude,
    double? longitude,
    bool isCritical = false,
    AlertPriority priority = AlertPriority.medium,
    List<String>? attachments,
    String? geoLga,
    String? geoWard,
    String? geoSiecWard,
    String? geoPu,
    String syncStatus = 'COMPLETED',
  }) async {
    var finalLat = latitude ?? 9.9167; // Fallback Jos loc
    var finalLng = longitude ?? 8.8917;

    try {
      if (latitude == null || longitude == null) {
        final pos = await LocationService().getCurrentPosition(force: true);
        if (pos != null) {
          finalLat = pos.latitude;
          finalLng = pos.longitude;
        }
      }
    } catch (e) {
      debugPrint('[SYS_ERR] AlertService: Error resolving location: $e');
    }

    final localId = 'OFFLINE_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult.contains(ConnectivityResult.none);

      if (isOffline) {
        await _sqliteService.enqueueAlert(
          localId: localId,
          type: type,
          description: description,
          lat: finalLat,
          lng: finalLng,
          priority: priority.name.toUpperCase(),
          isAnonymous: false,
          createdAt: DateTime.now().toIso8601String(),
        );

        if (attachments != null) {
          for (final path in attachments) {
            await _sqliteService.enqueueMedia(
              localAlertId: localId,
              localFilePath: path,
            );
          }
        }

        await BackgroundTrackingService().startSosTracking(localId, reportedBy);
        return localId;
      }

      final alertPayload = <String, dynamic>{
        'local_id': localId,
        'type': type,
        'description': description,
        'latitude': finalLat,
        'longitude': finalLng,
        'status': 'PENDING',
        'severity': priority.name.toUpperCase(),
        'geo_lga': geoLga,
        'geo_ward': geoWard,
        'geo_pu': geoPu,
      };

      final response = await SupabaseConfig.client
          .from('alerts')
          .insert(alertPayload)
          .select()
          .single();

      final alertId = response['id'] as String?;
      if (alertId != null) {
        await BackgroundTrackingService().startSosTracking(alertId, reportedBy);
        return alertId;
      }

      return null;
    } catch (e) {
      debugPrint('[CRITICAL_SERVICE_ERR] AlertService Submission Failed: $e');
      return null;
    }
  }

  /// Replays pending alerts once connectivity is restored.
  Future<Map<String, String>> flushOfflineQueue() async {
    final mappings = <String, String>{};
    try {
      final offlineQueue = await _sqliteService.getPendingAlerts();
      if (offlineQueue.isEmpty) return mappings;

      debugPrint('[SYNC] Recovering ${offlineQueue.length} offline alerts...');
      for (final row in offlineQueue) {
        final localId = row['local_id'] as String;
        try {
          final payload = <String, dynamic>{
            'local_id': localId,
            'type': row['type'],
            'description': row['description'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
            'severity': row['priority'],
            'status': 'PENDING',
          };

          final response = await SupabaseConfig.client
              .from('alerts')
              .insert(payload)
              .select()
              .single();

          final alertId = response['id'] as String?;
          if (alertId != null) {
            mappings[localId] = alertId;
            await _sqliteService.markAlertSynced(localId);
          }
        } catch (e) {
          debugPrint('[SYNC_ERR] Alert sync failed for $localId: $e');
        }
      }
    } catch (e) {
      debugPrint('[SYNC_ERR] Flush offline queue failed: $e');
    }
    return mappings;
  }
}
