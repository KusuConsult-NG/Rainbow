import 'dart:async';
// ignore_for_file: unreachable_from_main

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Documentation for this public member.

class BackgroundTrackingService {
  /// Documentation for this public member.
  factory BackgroundTrackingService() => _instance;
  BackgroundTrackingService._internal();
  static final BackgroundTrackingService _instance =
      BackgroundTrackingService._internal();

  bool _isInitialized = false;

  /// Configures the service isolate. Does not start the service.
  Future<void> initializeService() async {
    if (_isInitialized) return;

    try {
      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'rainbow_tracking',
          initialNotificationTitle: 'OPERATION RAINBOW',
          initialNotificationContent: 'System Ready',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('[CRITICAL_BG_ERR] Service Initialization Failed: $e');
      rethrow;
    }
  }

  /// Starts persistent tracking for a responder.
  Future<void> startResponderTracking(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trackingMode', 'responder');
      await prefs.setString('activeTrackingUserId', userId);

      final service = FlutterBackgroundService();
      if (!await service.isRunning()) await service.startService();

      service.invoke('updateMode', {
        'mode': 'responder',
        'userId': userId,
      });
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[CRITICAL_BG_ERR] Responder Tracking Start Failed: $e');
    }
  }

  /// Starts transient tracking for a citizen SOS event.
  Future<void> startSosTracking(String alertId, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trackingMode', 'sos');
      await prefs.setString('activeTrackingAlertId', alertId);
      await prefs.setString('activeTrackingUserId', userId);

      final service = FlutterBackgroundService();
      if (!await service.isRunning()) await service.startService();

      service.invoke('updateMode', {
        'mode': 'sos',
        'alertId': alertId,
        'userId': userId,
      });
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[CRITICAL_BG_ERR] SOS Tracking Start Failed: $e');
    }
  }

  /// Documentation for this public member.

  Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('trackingMode');
    await prefs.remove('activeTrackingAlertId');
    await prefs.remove('activeTrackingUserId');
    await prefs.remove('responderStatus');

    FlutterBackgroundService().invoke('stopService');
  }

  /// Documentation for this public member.

  Future<void> updateStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('responderStatus', status);

    FlutterBackgroundService().invoke('updateStatus', {'status': status});
  }
}

/// Documentation for this public member.

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

/// Documentation for this public member.

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  final battery = Battery();
  final connectivity = Connectivity();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  var modeStr = prefs.getString('trackingMode');
  var currentUserId = prefs.getString('activeTrackingUserId');
  var currentAlertId = prefs.getString('activeTrackingAlertId');
  String? currentStatus = prefs.getString('responderStatus') ??
      (modeStr == 'sos' ? 'EMERGENCY' : 'PATROLLING');

  Position? lastPosition;

  if (service is AndroidServiceInstance) {
    service
        .on('setAsForeground')
        .listen((_) => service.setAsForegroundService());
    service
        .on('setAsBackground')
        .listen((_) => service.setAsBackgroundService());
  }

  service.on('stopService').listen((_) => service.stopSelf());

// Note: updateMode and updateStatus listeners are registered below
// after startTelemetry/startAdaptiveHeartbeat are defined,
// so they can restart those engines on mode changes.

  // Plateau State Operational Bounds (Approximate)
  const plateauLatMin = 8.38;
  const plateauLatMax = 10.42;
  const plateauLngMin = 8.38;
  const plateauLngMax = 10.75;

  StreamSubscription<Position>? positionStream;

  void startTelemetry() {
    if (positionStream != null) {
      unawaited(positionStream!.cancel());
    }

    // Dynamic settings based on mode
    final interval = modeStr == 'sos'
        ? const Duration(seconds: 5)
        : const Duration(seconds: 15);
    final distance = modeStr == 'sos' ? 0 : 10;

    final dynamicSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distance,
      intervalDuration: interval,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'OPERATION RAINBOW',
        notificationText: modeStr == 'sos'
            ? 'EMERGENCY: LIVE TRANSMISSION'
            : "RESPONDER: ${currentStatus ?? 'ONLINE'}",
        enableWakeLock: true,
      ),
    );

    positionStream =
        Geolocator.getPositionStream(locationSettings: dynamicSettings)
            .listen((pos) async {
      final userId = currentUserId ?? 'UNKNOWN';
      if (userId == 'UNKNOWN') return;

      if (lastPosition != null && modeStr != 'sos') {
        final dist = Geolocator.distanceBetween(
          lastPosition!.latitude,
          lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (dist < 5) return;
      }
      lastPosition = pos;

      try {
        final batteryLevel = await battery.batteryLevel;
        final conn = await connectivity.checkConnectivity();

        final isWithinPlateau = pos.latitude >= plateauLatMin &&
            pos.latitude <= plateauLatMax &&
            pos.longitude >= plateauLngMin &&
            pos.longitude <= plateauLngMax;

        final trackingRef = FirebaseDatabase.instance.ref('tracking/$userId');

        // 1. Current Position (State)
        final payload = {
          'user_id': userId,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': ServerValue.timestamp,
          'mode': modeStr,
          if (modeStr == 'sos') 'alert_id': currentAlertId,
          'status':
              modeStr == 'sos' ? 'EMERGENCY' : (currentStatus ?? 'PATROLLING'),
          'geo_integrity':
              isWithinPlateau ? 'VERIFIED_PLATEAU' : 'OUT_OF_BOUNDS',
          'telemetry': {
            'battery': batteryLevel,
            'network': conn.toString(),
            'accuracy': pos.accuracy,
            'speed': pos.speed,
          },
        };
        await trackingRef.update(payload);

        // 2. Mission Path History (For HQ Mapping)
        if (modeStr == 'sos' || modeStr == 'responder') {
          final historyRef = trackingRef.child('path').push();
          await historyRef.set({
            'lat': pos.latitude,
            'lng': pos.longitude,
            't': ServerValue.timestamp,
          });

          // Optional: Trim history to last 50 points to save RTDB bandwidth
        }

        if (service is AndroidServiceInstance) {
          unawaited(
            service.setForegroundNotificationInfo(
              title: 'OPERATION RAINBOW',
              content: modeStr == 'sos'
                  ? 'SOS: ACTIVE TRANSMISSION'
                  : "UNIT: ${currentStatus ?? 'ONLINE'}",
            ),
          );
        }
        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
      } catch (e) {
        debugPrint('[TELEMETRY_FAIL] $e');
      }
    });
  }

  // PHASE 3: ADAPTIVE HEARTBEAT ENGINE
  Timer? heartbeatTimer;

  void startAdaptiveHeartbeat() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      final userId = currentUserId;
      if (userId == null) return;

      final bLevel = await battery.batteryLevel;

      var targetInterval = 60;
      if (modeStr == 'sos' || currentStatus == 'DURESS') {
        targetInterval = 15;
      } else if (bLevel < 15) {
        targetInterval = 300;
      } else if (currentStatus == 'IDLE') {
        targetInterval = 120;
      }

      if (timer.tick % (targetInterval ~/ 15) == 0) {
        final heartbeatRef =
            FirebaseDatabase.instance.ref('tracking/$userId/heartbeat');
        await heartbeatRef.set(ServerValue.timestamp);
      }
    });
  }

  service.on('updateMode').listen((event) {
    if (event != null) {
      modeStr = event['mode'] as String?;
      currentUserId = event['userId'] as String?;
      currentAlertId = event['alertId'] as String?;
      // Re-initialize telemetry with new settings
      startTelemetry();
      startAdaptiveHeartbeat();
    }
  });

  service.on('updateStatus').listen((event) {
    if (event != null) {
      currentStatus = event['status'] as String?;
      // Refresh heartbeat logic for priority changes
      startAdaptiveHeartbeat();
    }
  });

  startTelemetry();
  startAdaptiveHeartbeat();
}
