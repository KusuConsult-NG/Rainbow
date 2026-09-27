import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/cloudinary_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/core/geo/jurisdiction_resolver.dart';
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
    /// `isCritical` was a parameter that did nothing.
    ///
    /// It was declared, callers set it, and the body never read it — so
    /// `startEmergency()`, which passes `isCritical: true` and no `priority`,
    /// filed every PANIC SOS at the default: MEDIUM. The most urgent thing a
    /// citizen can do arrived on the HQ board graded medium, below a report of
    /// a blocked drain, and outside the CRITICAL filter entirely.
    ///
    /// Caught by pressing the button and reading the row that came out
    /// (`severity: MEDIUM`), not by reading the code — the parameter is right
    /// there in the call and looks like it works.
    final effectivePriority = isCritical ? AlertPriority.critical : priority;

    // Coordinates stay NULL when there is no real fix.
    //
    // This previously defaulted to (9.9167, 8.8917) — the centre of Jos — so an
    // SOS raised where the GPS could not get a lock reached the command
    // dashboard as a confident pin, indistinguishable from a real position, and
    // responders were dispatched to a location produced by a `??` operator.
    // A missing location must read as missing. See E2E_AUDIT_REPORT.md C-5.
    var finalLat = latitude;
    var finalLng = longitude;

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

    // ── Which jurisdiction owns this incident ───────────────────────────
    //
    // The command chain starts at the tier responsible for the GROUND the
    // incident happened on, so an alert has to carry that ground. Nothing
    // attached it: a citizen report carried no geography at all unless the
    // reporter opened the manual override, and the panic SOS carried the
    // reporter's REGISTERED lga/ward — where they live, not where they are.
    // Every tier filter then fell through its `IS NULL` fail-open and showed
    // every alert to everybody, so the routing existed but never ran.
    //
    // Order of preference, most trustworthy first:
    //   1. what the caller passed  — a manual override by the reporter
    //   2. the coordinates          — measured, and the point of all this
    //   3. nothing                  — unresolved is a real answer
    //
    // The reporter's profile is deliberately NOT a fallback here. Filing an
    // incident against the address someone registered at is how a report from
    // Mangu is routed to a unit in Jos, and it would be indistinguishable
    // afterwards from a measured position. C-5 was this mistake with
    // coordinates; this is the same mistake with jurisdiction.
    var finalLga = geoLga;
    var finalWard = geoWard;
    final finalPu = geoPu;

    if (finalLga == null || finalWard == null) {
      try {
        await JurisdictionResolver.instance.ensureLoaded();
        final j = JurisdictionResolver.instance.resolve(finalLat, finalLng);
        if (j.isResolved) {
          finalLga ??= j.lga;
          finalWard ??= j.ward;
          debugPrint('[ALERT_SERVICE] jurisdiction from GPS: $j');
        } else {
          debugPrint(
            '[ALERT_SERVICE] coordinates did not resolve to a Plateau LGA — '
            'submitting without jurisdiction rather than guessing one.',
          );
        }
      } catch (e) {
        debugPrint('[ALERT_SERVICE] jurisdiction lookup failed: $e');
      }
    }

    // There is no polling unit from coordinates, and there cannot be: no open
    // dataset gives polling units a position. A PU arrives only when the
    // reporter picks one.

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
          priority: effectivePriority.name.toUpperCase(),
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
        'reported_by': reportedBy,
        // `'reportedBy': reportedBy` used to sit here too — a camelCase twin of
        // the line above, and not a column. PostgREST rejects an insert naming
        // an unknown column IN FULL, so EVERY alert this app submitted was
        // refused: every SOS, every incident report.
        //
        // It was invisible because the failure path is a fallback, not an
        // error: the catch below enqueues the alert into offline SQLite, and
        // the UI says the report was sent. It looked like an app that worked
        // offline. It was an app that was always offline.
        //
        // The drift gate missed it too — its Dart key pattern was
        // `[a-z_][a-z0-9_]*` with no IGNORECASE, so a camelCase key did not
        // match and was skipped in silence. Fixed in check_schema_drift.py.
        'latitude': finalLat,
        'longitude': finalLng,
        'status': 'PENDING',
        'severity': effectivePriority.name.toUpperCase(),
        'geo_lga': finalLga,
        'geo_ward': finalWard,
        'geo_siec_ward': geoSiecWard,
        'geo_pu': finalPu,
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
          priority: effectivePriority.name.toUpperCase(),
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
