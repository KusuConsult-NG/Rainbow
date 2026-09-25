import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/cloudinary_service.dart';
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
    // Coordinates stay NULL when there is no real fix.
    //
    // This previously defaulted to (9.9167, 8.8917) — the centre of Jos — so an
    // SOS raised where the GPS could not get a lock reached the command
    // dashboard as a confident pin, indistinguishable from a real position, and
    // responders were dispatched to a location produced by a `??` operator.
    // A missing location must read as missing. See E2E_AUDIT_REPORT.md C-5.
    var finalLat = latitude;
    var finalLng = longitude;

    // A critical report always outranks the caller-supplied priority. The
    // `isCritical` flag was accepted and then discarded, so every panic SOS —
    // emergency_provider.dart passes isCritical: true — was filed with the
    // default MEDIUM severity, and so never matched the dashboard's CRITICAL
    // filter or the notification worker's rule that HQ is copied on anything
    // critical.
    final severity = isCritical ? 'CRITICAL' : priority.name.toUpperCase();

    try {
      if (finalLat == null || finalLng == null) {
        final pos = await LocationService().getCurrentPosition(force: true);
        if (pos != null) {
          finalLat = pos.latitude;
          finalLng = pos.longitude;
        }
      }
    } catch (e) {
      debugPrint('[SYS_ERR] AlertService: Error resolving location: $e');
    }

    if (finalLat == null || finalLng == null) {
      debugPrint(
        '[ALERT_SERVICE] No GPS fix for $type alert — submitting WITHOUT '
        'coordinates. HQ surfaces these in the unlocated-alerts panel; '
        'jurisdiction (geo_lga/geo_ward/geo_pu) is still attached.',
      );
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
          priority: severity,
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

      final mediaUrls = <String>[];
      if (attachments != null && attachments.isNotEmpty) {
        for (final filePath in attachments) {
          try {
            final file = File(filePath);
            if (file.existsSync()) {
              // 1. Cost-optimized Cloudinary Upload (Free 25GB Storage + Transcoding)
              final cloudinaryUrl = await CloudinaryService.instance.uploadMedia(file);
              if (cloudinaryUrl != null) {
                mediaUrls.add(cloudinaryUrl);
                continue;
              }

              // 2. Supabase Storage Fallback
              final bytes = await file.readAsBytes();
              final ext = filePath.split('.').last;
              final fileName = '${DateTime.now().millisecondsSinceEpoch}_${localId.length > 5 ? localId.substring(0, 5) : localId}.$ext';
              final storagePath = 'incident_media/$fileName';
              await SupabaseConfig.client.storage
                  .from('incident-media')
                  .uploadBinary(storagePath, bytes);
              final publicUrl = SupabaseConfig.client.storage
                  .from('incident-media')
                  .getPublicUrl(storagePath);
              mediaUrls.add(publicUrl);
            } else if (filePath.startsWith('http')) {
              mediaUrls.add(filePath);
            }
          } catch (e) {
            debugPrint('[ALERT_SERVICE] Media upload fallback for $filePath: $e');
            if (filePath.startsWith('http')) {
              mediaUrls.add(filePath);
            }
          }
        }
      }

      final alertPayload = <String, dynamic>{
        'local_id': localId,
        'type': type,
        'description': description,
        // Only the snake_case column exists. Sending 'reportedBy' as well made
        // PostgREST reject the whole insert ("column alerts.reportedBy does not
        // exist"), so every online alert threw and silently degraded to the
        // offline queue — the online path never worked.
        'reported_by': reportedBy,
        'latitude': finalLat,
        'longitude': finalLng,
        'status': 'PENDING',
        'severity': severity,
        'geo_lga': geoLga,
        'geo_ward': geoWard,
        'geo_siec_ward': geoSiecWard,
        'geo_pu': geoPu,
        'media_urls': mediaUrls,
      };

      try {
        final response = await SupabaseConfig.client
            .from('alerts')
            .insert(alertPayload)
            .select('id')
            .maybeSingle();

        final alertId = response?['id'] as String? ?? localId;
        await BackgroundTrackingService().startSosTracking(alertId, reportedBy);
        return alertId;
      } catch (e) {
        debugPrint(
          '[ALERT_SERVICE] Direct insert failed ($e) — saving to offline SQLite queue.',
        );
        await _sqliteService.enqueueAlert(
          localId: localId,
          type: type,
          description: description,
          lat: finalLat,
          lng: finalLng,
          priority: severity,
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
    } catch (e) {
      debugPrint('[CRITICAL_SERVICE_ERR] AlertService Submission Failed: $e');
      return localId;
    }
  }

  /// Builds the Supabase `alerts` payload for one row of the local offline queue.
  ///
  /// Extracted as a pure function so the offline SOS replay path can be tested
  /// without a network or a Supabase session — see `test/offline_queue_test.dart`.
  ///
  /// REGRESSION GUARD: this previously read `row['latitude']` and
  /// `row['longitude']`, but the SQLite schema stores those columns as `lat` and
  /// `lng` (see SqliteService._initDb and enqueueAlert). Both lookups therefore
  /// returned null, and **every alert queued while offline reached HQ with no
  /// coordinates** — in exactly the no-signal scenario the offline queue exists
  /// to serve.
  ///
  /// `created_at` is carried across from the queue rather than defaulting to
  /// NOW() at insert time, so an incident raised at 14:00 and synced at 18:00 is
  /// recorded at 14:00.
  static Map<String, dynamic> buildOfflineSyncPayload(
    Map<String, dynamic> row,
  ) {
    return <String, dynamic>{
      'local_id': row['local_id'],
      'type': row['type'],
      'description': row['description'],
      'latitude': row['lat'],
      'longitude': row['lng'],
      'severity': row['priority'],
      'status': 'PENDING',
      if (row['created_at'] != null) 'created_at': row['created_at'],
    };
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
          final payload = buildOfflineSyncPayload(row);

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
          await _sqliteService.updateSyncStatus(localId, 'FAILED');
        }
      }
    } catch (e) {
      debugPrint('[SYNC_ERR] Flush offline queue failed: $e');
    }
    return mappings;
  }
}
