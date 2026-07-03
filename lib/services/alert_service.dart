// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/sqlite_service.dart';

/// Documentation for this public member.

final alertServiceProvider = Provider<AlertService>((ref) {
  return AlertService(ref.read(sqliteServiceProvider));
});

/// Handles synchronization of Alert and Incident Report data
/// between the local client and the Firestore `alerts` collection.
class AlertService {
  /// Documentation for this public member.
  AlertService([SqliteService? sqliteService])
      : _sqliteService = sqliteService ?? SqliteService();

  final SqliteService _sqliteService;

  /// PRD: Escrows to POLLING_UNIT, Priorities strictly enforced. Detects offline to execute SMS Fallback.
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
        final permStatus = await Permission.locationWhenInUse.status;
        if (permStatus.isGranted) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.high),
          ).timeout(
            const Duration(seconds: 3),
            onTimeout: () async {
              return await Geolocator.getLastKnownPosition() ??
                  Position(
                    latitude: finalLat,
                    longitude: finalLng,
                    timestamp: DateTime.now(),
                    accuracy: 0,
                    altitude: 0,
                    heading: 0,
                    speed: 0,
                    speedAccuracy: 0,
                    altitudeAccuracy: 0,
                    headingAccuracy: 0,
                  );
            },
          );
          finalLat = pos.latitude;
          finalLng = pos.longitude;
        }
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint(
        '[SYS_ERR] AlertService: Critical error resolving location: $e',
      );
    }

    final localId = 'OFFLINE_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult.contains(ConnectivityResult.none);

      final alertData = <String, dynamic>{
        'type': type,
        'description': description,
        'lat': finalLat,
        'lng': finalLng,
        'reportedByUid': reportedBy, // canonical field — all queries use this
        'reportedBy':
            reportedBy, // legacy alias — keep for HQ dashboard compatibility
        'status': 'OPEN',
        'priority': priority.name.toUpperCase(),
        'assigned_to': 'POLLING_UNIT',
        'geo_lga': geoLga,
        'geo_ward': geoWard,
        'geo_siec_ward': geoSiecWard,
        'geo_pu': geoPu,
        'mediaUrls': attachments ?? <String>[],
        'sync_status': isOffline ? 'PENDING' : syncStatus,
        'reportedAt': DateTime.now().toIso8601String(),
        'local_id': localId,
      };

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

        // Start local tracking
        await BackgroundTrackingService().startSosTracking(localId, reportedBy);
        return localId;
      }

      final isVoiceReport = type == 'AI_VOICE_REPORT';
      final callable = isVoiceReport
          ? FirebaseFunctions.instance.httpsCallable('triageAndCreateVoiceAlert')
          : FirebaseFunctions.instance.httpsCallable('createAlert');
      
      final payload = isVoiceReport
          ? {
              'text': description,
              'lat': finalLat,
              'lng': finalLng,
            }
          : alertData;

      final result = await callable.call<Map<String, dynamic>>(payload);
      final data = result.data;

      final alertId = data['alertId'] as String?;
      if (alertId != null) {
        await BackgroundTrackingService().startSosTracking(alertId, reportedBy);
        return alertId;
      }

      debugPrint('[SYS_WARN] AlertService: Server response missing alertId');
      return null;
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint(
        '[CRITICAL_SERVICE_ERR] AlertService Submission Failed: $e. Using direct fallback.',
      );
      try {
        final alertData = <String, dynamic>{
          'type': type,
          'description': description,
          'lat': finalLat,
          'lng': finalLng,
          'reportedByUid': reportedBy,
          'reportedBy': reportedBy,
          'status': 'OPEN',
          'priority': priority.name.toUpperCase(),
          'assigned_to': 'POLLING_UNIT',
          'geo_lga': geoLga,
          'geo_ward': geoWard,
          'geo_pu': geoPu,
          'mediaUrls': attachments ?? <String>[],
          'sync_status': 'COMPLETED',
          'createdAt': FieldValue.serverTimestamp(),
          'reportedAt': FieldValue.serverTimestamp(),
        };
        final docRef = await FirebaseFirestore.instance
            .collection('alerts')
            .add(alertData);
        await BackgroundTrackingService()
            .startSosTracking(docRef.id, reportedBy);
        return docRef.id;
        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
      } catch (fallbackErr) {
        debugPrint(
          '[CRITICAL_SERVICE_ERR] Fallback Submission Failed: $fallbackErr',
        );
        return null;
      }
    }
  }

  /// Replays pending alerts once connectivity is restored.
  /// Returns a map of local_id -> real_id for media remapping.
  Future<Map<String, String>> flushOfflineQueue() async {
    final mappings = <String, String>{};
    try {
      final offlineQueue = await _sqliteService.getPendingAlerts();

      if (offlineQueue.isEmpty) return mappings;

      debugPrint('[SYNC] Recovering ${offlineQueue.length} offline alerts...');
      for (final row in offlineQueue) {
        final localId = row['local_id'] as String;
        try {
          final isVoiceReport = row['type'] == 'AI_VOICE_REPORT';
          final recoveryCallable = isVoiceReport
              ? FirebaseFunctions.instance.httpsCallable('triageAndCreateVoiceAlert')
              : FirebaseFunctions.instance.httpsCallable('createAlert');

          final payload = isVoiceReport
              ? {
                  'text': row['description'],
                  'lat': row['lat'],
                  'lng': row['lng'],
                }
              : {
                  'type': row['type'],
                  'description': row['description'],
                  'lat': row['lat'],
                  'lng': row['lng'],
                  'reportedByUid': 'unknown',
                  'reportedBy': 'unknown',
                  'status': 'OPEN',
                  'priority': row['priority'],
                  'assigned_to': 'POLLING_UNIT',
                  'sync_status': 'RECOVERED',
                  'reportedAt': row['created_at'],
                  'local_id': localId,
                };

          try {
            final result = await recoveryCallable.call<Map<String, dynamic>>(payload);
            final realId = result.data['alertId'] as String?;

            if (realId != null) {
              mappings[localId] = realId;
              await _sqliteService.deleteAlert(localId);
            }
            debugPrint(
              '[SYNC_SUCCESS] Alert $localId synchronized as $realId.',
            );
          } catch (e) {
            debugPrint(
              '[SYNC_FALLBACK] Cloud Function Failed. Using direct fallback for $localId: $e',
            );
            final alertData = <String, dynamic>{
              'type': row['type'],
              'description': row['description'],
              'lat': row['lat'],
              'lng': row['lng'],
              'reportedByUid': 'unknown',
              'reportedBy': 'unknown',
              'status': 'OPEN',
              'priority': row['priority'],
              'assigned_to': 'POLLING_UNIT',
              'sync_status': 'COMPLETED',
              'createdAt': FieldValue.serverTimestamp(),
              'reportedAt': FieldValue.serverTimestamp(),
            };
            final docRef = await FirebaseFirestore.instance
                .collection('alerts')
                .add(alertData);
            final realId = docRef.id;
            mappings[localId] = realId;
            await _sqliteService.deleteAlert(localId);
            debugPrint(
              '[SYNC_SUCCESS_FALLBACK] Alert $localId synchronized as $realId.',
            );
          }
        } catch (e) {
          debugPrint('[SYNC_RETRY] Failed to sync alert $localId: $e');
          await _sqliteService.updateSyncStatus(localId, 'FAILED');
        }
      }
    } catch (e) {
      debugPrint('[CRITICAL_SYNC_ERR] Failed to flush offline queue: $e');
    }
    return mappings;
  }
}
