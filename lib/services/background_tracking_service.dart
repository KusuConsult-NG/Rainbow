
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
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
        // autoStart must be FALSE — the OS cannot post foreground notifications
        // before the notification channel is created. The service is started
        // explicitly via startTracking() only when an SOS is triggered.
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: 'rainbow_tracking',
        initialNotificationTitle: 'OPERATION RAINBOW',
        initialNotificationContent: 'Active Emergency Tracking',
        foregroundServiceNotificationId: 888,
      ),
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
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } catch (e) {
    // Already initialized
  }

  // Check if we booted natively or started normally
  final prefs = await SharedPreferences.getInstance();
  String? currentAlertId = prefs.getString('activeTrackingAlertId');
  String? currentUserId = prefs.getString('activeTrackingUserId');

  // Tracking state variables
  int inactiveSeconds = 0;

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

  // PRD §3: Real-Time Tracking — Event-driven stream for battery efficiency
  final locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // 10 meters distance filter
    intervalDuration: const Duration(seconds: 10), // 10s sync interval
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationText: "Tracking Active...",
      notificationTitle: "OPERATION RAINBOW",
      enableWakeLock: true,
    ),
  );

  StreamSubscription<Position>? positionStream;

  void startPositionStream() {
    positionStream?.cancel();
    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) async {
      if (currentAlertId == null) return;

      // Reset inactivity and update last known
      inactiveSeconds = 0;

      final userId = currentUserId ?? 'UNKNOWN';
      try {
        final trackingRef = FirebaseDatabase.instance.ref('tracking/$userId');
        final historyRef = FirebaseDatabase.instance.ref('tracking_history/$userId');
        
        final data = {
          'alert_id': currentAlertId,
          'user_id': userId,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': ServerValue.timestamp,
          'speed': pos.speed,
          'accuracy': pos.accuracy,
        };

        // 1. Update Real-time "Last Known"
        await trackingRef.set(data);
        
        // 2. Append to persistent breadcrumb trail (Tactical History)
        await historyRef.push().set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': ServerValue.timestamp,
          'alert_id': currentAlertId,
        });

        debugPrint('[TRACKING_UPDATE] Telemetry & History synced: $userId');
      } catch (e) {
        debugPrint('[SYS_ERR] BackgroundTracking: DB Sync failed - $e');
      }
    });
  }

  // Initial trigger
  startPositionStream();

  // Watchdog Timer for Inactivity/Timeout
  Timer.periodic(const Duration(seconds: 60), (timer) async {
    inactiveSeconds += 60;
    if (inactiveSeconds >= 1800) { // 30 minutes
      debugPrint('[TRACKING_UPDATE] Tracking timed out due to 30m inactivity.');
      service.stopSelf();
    }
  });

  service.on('stopService').listen((event) {
    positionStream?.cancel();
    service.stopSelf();
  });

}
