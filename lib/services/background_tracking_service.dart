import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for background responder location tracking and SOS broadcasts.
class BackgroundTrackingService {
  factory BackgroundTrackingService() => _instance;
  BackgroundTrackingService._internal();
  static final BackgroundTrackingService _instance =
      BackgroundTrackingService._internal();

  bool _isInitialized = false;

  /// Configures the service isolate.
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
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trackingMode', 'responder');
      await prefs.setString('activeTrackingUserId', userId);

      final service = FlutterBackgroundService();
      if (!await service.isRunning()) await service.startService();

      service.invoke('updateMode', {
        'mode': 'responder',
        'userId': userId,
      });
    } catch (e) {
      debugPrint('[CRITICAL_BG_ERR] Responder Tracking Start Failed: $e');
    }
  }

  /// Starts transient tracking for a citizen SOS event.
  Future<void> startSosTracking(String alertId, String userId) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

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
    } catch (e) {
      debugPrint('[CRITICAL_BG_ERR] SOS Tracking Start Failed: $e');
    }
  }

  Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('trackingMode');
    await prefs.remove('activeTrackingAlertId');
    await prefs.remove('activeTrackingUserId');
    await prefs.remove('responderStatus');

    FlutterBackgroundService().invoke('stopService');
  }

  Future<void> updateStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('responderStatus', status);

    FlutterBackgroundService().invoke('updateStatus', {'status': status});
  }
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    final battery = Battery();
    final connectivity = Connectivity();

    try {
      await SupabaseConfig.init();
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

  StreamSubscription<Position>? positionStream;

  void startTelemetry() {
    if (positionStream != null) {
      unawaited(positionStream!.cancel());
    }

    final interval = modeStr == 'sos'
        ? const Duration(seconds: 5)
        : const Duration(seconds: 15);
    final distance = modeStr == 'sos' ? 0 : 10;

    final dynamicSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distance,
      intervalDuration: interval,
      forceLocationManager: true,
    );

    try {
      positionStream = Geolocator.getPositionStream(
        locationSettings: dynamicSettings,
      ).listen(
        (pos) async {
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
            final batteryLevel = await battery.batteryLevel.catchError((_) => 100);
            final conn = await connectivity.checkConnectivity().catchError((_) => [ConnectivityResult.none]);

            final telemetryPayload = {
              'user_id': userId,
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'mode': modeStr ?? 'responder',
              'status': modeStr == 'sos'
                  ? 'EMERGENCY'
                  : (currentStatus ?? 'PATROLLING'),
              'battery': batteryLevel,
              'network': conn.toString(),
              'accuracy': pos.accuracy,
              'speed': pos.speed,
              'updated_at': DateTime.now().toIso8601String(),
            };

            await SupabaseConfig.client
                .from('telemetry')
                .upsert(telemetryPayload);

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
          } catch (e) {
            debugPrint('[TELEMETRY_FAIL] $e');
          }
        },
        onError: (Object err) {
          debugPrint('[BG_LOC_ERR] Background stream error: $err');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[BG_LOC_ERR] Failed to start background position stream: $e');
    }
  }

  service.on('updateMode').listen((event) {
    if (event != null) {
      modeStr = event['mode'] as String?;
      currentUserId = event['userId'] as String?;
      currentAlertId = event['alertId'] as String?;
      startTelemetry();
    }
  });

  service.on('updateStatus').listen((event) {
    if (event != null) {
      currentStatus = event['status'] as String?;
    }
  });

  startTelemetry();
  } catch (e) {
    debugPrint('[BG_CRITICAL_ERR] Exception inside background service onStart: $e');
  }
}
