
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundTrackingService {
  static final BackgroundTrackingService _instance = BackgroundTrackingService._internal();
  factory BackgroundTrackingService() => _instance;
  BackgroundTrackingService._internal();

  /// Call this when the app starts.
  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true, // MUST be true for boot receivers to fire correctly on Android
        autoStartOnBoot: true, 
        isForegroundMode: true,
        notificationChannelId: 'rainbow_tracking',
        initialNotificationTitle: 'OPERATION RAINBOW',
        initialNotificationContent: 'Active Emergency Tracking',
        foregroundServiceNotificationId: 888,
      ),
      // iOS configuration typically requires heavy p-list configurations 
      // but is provided here as a dummy block based on PRD scopes.
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  Future<void> startTracking(String alertId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeTrackingAlertId', alertId);
    await prefs.setString('activeTrackingUserId', userId);

    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
    // We send data to the isolate
    service.invoke("setTrackingMetadata", {
      "alertId": alertId,
      "userId": userId,
    });
  }

  Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeTrackingAlertId');
    await prefs.remove('activeTrackingUserId');

    final service = FlutterBackgroundService();
    service.invoke("stopService");
  }
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  WidgetsFlutterBinding.ensureInitialized();
  
  // Isolate requires its own Firebase initialization for background threads
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Already initialized
  }

  // Check if we booted natively or started normally
  final prefs = await SharedPreferences.getInstance();
  String? currentAlertId = prefs.getString('activeTrackingAlertId');
  String? currentUserId = prefs.getString('activeTrackingUserId');

  // If autoStart triggered on boot, but we have no active alert, kill the service
  if (currentAlertId == null) {
     service.stopSelf();
     return;
  }

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('setTrackingMetadata').listen((event) {
    if (event != null) {
      currentAlertId = event["alertId"] as String?;
      currentUserId = event["userId"] as String?;
    }
  });

  // State variables for compression and timeout
  double? lastLat;
  double? lastLng;
  int inactiveSeconds = 0;

  // PRD Constraint: Transmit every 10 seconds
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService() && currentAlertId != null) {
        
        try {
          final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
          
          // PRD: Movement trail compression (avoid DB overload)
          if (lastLat != null && lastLng != null) {
            final distance = Geolocator.distanceBetween(lastLat!, lastLng!, pos.latitude, pos.longitude);
            if (distance < 5.0) {
               // User hasn't moved 5 meters. Skip DB write.
               inactiveSeconds += 10;
               
               // PRD: Tracking timeout if inactive (30 minutes)
               if (inactiveSeconds >= 1800) {
                 debugPrint('[TRACKING_UPDATE] Tracking timed out due to inactivity.');
                 service.stopSelf();
               }
               return;
            }
          }

          // Reset inactivity and update last known
          inactiveSeconds = 0;
          lastLat = pos.latitude;
          lastLng = pos.longitude;

          final userId = currentUserId ?? 'UNKNOWN';
          // Use RTDB for high-frequency telemetry instead of Firestore
          await FirebaseDatabase.instance.ref('tracking/$userId').set({
            'alert_id': currentAlertId,
            'user_id': userId,
            'lat': pos.latitude,
            'lng': pos.longitude,
            'timestamp': ServerValue.timestamp,
          });
          debugPrint('[TRACKING_UPDATE] Telemetry synced for alert $currentAlertId locally.');

          service.setForegroundNotificationInfo(
            title: "OPERATION RAINBOW",
            content: "Tracking Active...", // Do not show coords in generic notification for OpSec
          );

        } catch (e) {
          debugPrint('[SYS_ERR] BackgroundTracking: Error retrieving or pushing coords - $e');
        }
      }
    }
  });
}
