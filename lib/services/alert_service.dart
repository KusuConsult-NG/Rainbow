import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final alertServiceProvider = Provider<AlertService>((ref) {
  return AlertService();
});


/// Handles synchronization of Alert and Incident Report data
/// between the local client and the Firestore `alerts` collection.
class AlertService {
  AlertService();

  /// PRD: Escrows to POLLING_UNIT, Priorities strictly enforced. Detects offline to execute SMS Fallback.
  Future<String> submitAlert({
    required String type,
    required String description,
    double? latitude,
    double? longitude,
    required String reportedBy,
    bool isCritical = false,
    String priority = 'HIGH',
    List<String>? attachments,
    String? geoLga,
    String? geoWard,
    String? geoPu,
  }) async {
    double finalLat = latitude ?? 9.9167; // Fallback Jos loc
    double finalLng = longitude ?? 8.8917;

    try {
      final permStatus = await Permission.locationWhenInUse.status;
      if (permStatus.isGranted) {
        // Attempt fresh high-accuracy position with strict timeout to preserve "Instant" feel
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 3), onTimeout: () async {
          debugPrint('[SYS_WARN] Fresh location timeout. Using last known.');
          return await Geolocator.getLastKnownPosition() ?? Position(
            latitude: finalLat, longitude: finalLng, 
            timestamp: DateTime.now(), accuracy: 0, altitude: 0, 
            heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
          );
        });
        
        finalLat = pos.latitude;
        finalLng = pos.longitude;
      } else {
         debugPrint('[SYS_WARN] AlertService: Location permissions not granted instantly. Falling back.');
      }
    } catch (e) {
      debugPrint('[SYS_ERR] AlertService: Critical error resolving location: $e');
    }

    // 1. Check Connectivity for Offline Gateway protocol
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOffline = connectivityResult.contains(ConnectivityResult.none);

    final alertData = {
      'type': type,
      'description': description,
      'lat': finalLat,
      'lng': finalLng,
      'reportedBy': reportedBy,
      'isCritical': priority == 'CRITICAL' || isCritical,
      'status': 'ACTIVE',
      'priority': priority,
      'assigned_to': 'POLLING_UNIT', // Central to the PRD Escrow pipeline
      'geo_lga': geoLga,
      'geo_ward': geoWard,
      'geo_pu': geoPu,
      'attachments': attachments ?? [],
    };

    if (isOffline) {
      debugPrint('[SYS_WARN] Device Offline. Executing SMS Gateway Fallback.');
      
      // Map labels to 2-character codes for SMS brevity
      final typeCodes = {
        'Kidnap': 'KD', 'Fire': 'FR', 'Drug abuse': 'DA', 'Police brutality': 'PB',
        'Flood': 'FL', 'Cyber crime': 'CC', 'Child abuse': 'CA', 
        'Domestic violence': 'DV', 'Cattle rustling': 'CR', 'Community attack': 'CM'
      };
      final typeCode = typeCodes[type] ?? 'OT'; // OT = Other
      
      final gatewayNumber = dotenv.env['SMS_GATEWAY_NUMBER'] ?? '0800RAINBOW';
      final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = 'ALERT|$reportedBy|$typeCode|LAT:$finalLat|LNG:$finalLng|TIME:$epoch';
      final smsUri = Uri(scheme: 'sms', path: gatewayNumber, queryParameters: {'body': payload});
      
      try {
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
        }
      } catch (e) {
        debugPrint('[SYS_ERR] AlertService: SMS Gateway Intent failed: $e');
      }

      // Add to robust offline retry queue
      final prefs = await SharedPreferences.getInstance();
      List<String> offlineQueue = prefs.getStringList('offline_alerts_queue') ?? [];
      offlineQueue.add(jsonEncode(alertData));
      await prefs.setStringList('offline_alerts_queue', offlineQueue);
      
      return 'OFFLINE_QUEUED_${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('createAlert');
      final result = await callable.call(alertData);
      // Fix #3: safe cast — function may return without alertId on partial failure
      return (result.data['alertId'] as String?) ?? 'LOCAL_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('[SYS_ERR] AlertService: HTTP Callable failed: $e');
      
      // Fallback local queue even if we thought we were online but request failed securely
      final prefs = await SharedPreferences.getInstance();
      List<String> offlineQueue = prefs.getStringList('offline_alerts_queue') ?? [];
      offlineQueue.add(jsonEncode(alertData));
      await prefs.setStringList('offline_alerts_queue', offlineQueue);

      return 'OFFLINE_QUEUED_ERR_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Flushes the offline queue gracefully when network is restored.
  Future<void> flushOfflineQueue() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return;

    final prefs = await SharedPreferences.getInstance();
    List<String> offlineQueue = prefs.getStringList('offline_alerts_queue') ?? [];
    
    if (offlineQueue.isEmpty) return;

    List<String> remainingQueue = [];
    final callable = FirebaseFunctions.instance.httpsCallable('createAlert');

    for (String alertStr in offlineQueue) {
      try {
        final alertMap = jsonDecode(alertStr);
        await callable.call(alertMap);
        debugPrint('[SYS_INFO] Successfully flushed queued offline alert.');
      } catch (e) {
        debugPrint('[SYS_ERR] AlertService: Failed to flush queued alert: $e');
        remainingQueue.add(alertStr); // keep in queue if it fails again
      }
    }

    await prefs.setStringList('offline_alerts_queue', remainingQueue);
  }
}
