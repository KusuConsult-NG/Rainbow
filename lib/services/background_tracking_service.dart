import 'dart:async';
import 'dart:io';
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
          initialNotificationTitle: 'PLATEAU EYE',
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
      var permission = await Geolocator.checkPermission();
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

  /// The longest an SOS track may run without anyone renewing it.
  ///
  /// There has to be a limit, and the duress path is why. A duress PIN
  /// deliberately leaves tracking running while telling the person their
  /// emergency has ended — that is the point of a duress code, and it is
  /// defensible while they may still be in danger. What is NOT defensible is
  /// that it had no end: nothing stopped it, so one duress entry meant that
  /// phone transmitting its position every five seconds for the life of the
  /// install, to a person who believed they had cancelled.
  ///
  /// Twelve hours is long enough to cover any plausible response to an
  /// emergency and short enough that "while they may be in danger" stays true.
  /// It is a ceiling, not a target: the ordinary paths still stop tracking the
  /// moment the incident closes.
  static const Duration sosTrackingMaxAge = Duration(hours: 12);

  /// Starts transient tracking for a citizen SOS event.
  Future<void> startSosTracking(String alertId, String userId) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trackingMode', 'sos');
      await prefs.setString('activeTrackingAlertId', alertId);
      await prefs.setString('activeTrackingUserId', userId);
      await prefs.setInt(
        'trackingExpiresAt',
        DateTime.now().add(sosTrackingMaxAge).millisecondsSinceEpoch,
      );

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

  /// The SOS this handset is currently tracking for, or null.
  ///
  /// Null when the track is a responder's patrol, when nothing is being
  /// tracked, or when the twelve-hour `sosTrackingMaxAge` ceiling has passed —
  /// an expired track is not a live emergency.
  ///
  /// `signOut()` asks this to decide what it may stop. A patrol track ends when
  /// an officer goes off duty; an SOS track must not, because the lock screen's
  /// sign-out needs no code and a duress alarm deliberately leaves tracking
  /// running.
  /// Null on a read failure too, and that is not a compromise: the isolate
  /// learns its own mode from THIS SAME store. If SharedPreferences cannot be
  /// read, there is no SOS track to preserve, because nothing is telling the
  /// background service to be on one.
  Future<String?> activeSosAlertId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('trackingMode') != 'sos') return null;
      final expiresAt = prefs.getInt('trackingExpiresAt');
      if (expiresAt != null &&
          DateTime.now().millisecondsSinceEpoch >= expiresAt) {
        return null;
      }
      final alertId = prefs.getString('activeTrackingAlertId');
      return (alertId == null || alertId.isEmpty) ? null : alertId;
    } catch (e) {
      debugPrint('[TRACKING] could not read the tracking mode: $e');
      return null;
    }
  }

  Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('trackingMode');
    await prefs.remove('activeTrackingAlertId');
    await prefs.remove('activeTrackingUserId');
    await prefs.remove('responderStatus');
    await prefs.remove('trackingExpiresAt');

    FlutterBackgroundService().invoke('stopService');
  }

  Future<void> updateStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('responderStatus', status);

    FlutterBackgroundService().invoke('updateStatus', {'status': status});
  }
}

/// Forget everything that says this device is tracking anybody.
///
/// Shared by the three stop conditions in the isolate so none of them can
/// leave a key behind that makes the next launch resume a track the user
/// believes ended.
Future<void> _clearTrackingPrefs(SharedPreferences prefs) async {
  await prefs.remove('trackingMode');
  await prefs.remove('activeTrackingAlertId');
  await prefs.remove('activeTrackingUserId');
  await prefs.remove('responderStatus');
  await prefs.remove('trackingExpiresAt');
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
    } catch (e) {
      debugPrint('[BG_SUPABASE_FAIL] Cannot connect to Supabase: $e — background service aborting.');
      unawaited(service.stopSelf());
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    var modeStr = prefs.getString('trackingMode');
    var currentUserId = prefs.getString('activeTrackingUserId');
    // The alert this track belongs to. `startSosTracking` has always passed it
    // and the `updateMode` listener below has always thrown it away, so
    // `telemetry.alert_id` — a real column, with a foreign key to alerts — was
    // never written by anything and never read by anything. A live SOS track
    // could not be tied to the SOS it was for.
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

    final LocationSettings dynamicSettings;
    if (Platform.isIOS) {
      dynamicSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distance,
        activityType: ActivityType.fitness,
      );
    } else {
      dynamicSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distance,
        intervalDuration: interval,
      );
    }

    try {
      positionStream = Geolocator.getPositionStream(
        locationSettings: dynamicSettings,
      ).listen(
        (pos) async {
          final userId = currentUserId ?? 'UNKNOWN';
          if (userId == 'UNKNOWN') return;

          // THREE REASONS TO STOP TRANSMITTING SOMEBODY'S POSITION.
          //
          // None of them existed. Tracking started, and the only thing that
          // ever ended it was the person entering their safe PIN on that
          // handset — so a duress entry, a responder closing the incident, or
          // the user signing out all left the phone reporting its location
          // every few seconds, indefinitely, with nothing on screen to say so.

          // 1. The window expired. See `sosTrackingMaxAge`.
          final expiry = prefs.getInt('trackingExpiresAt');
          if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
            debugPrint('[TELEMETRY_STOP] tracking window expired');
            await _clearTrackingPrefs(prefs);
            await positionStream?.cancel();
            unawaited(service.stopSelf());
            return;
          }

          // 2. Nobody is signed in on this device any more. The background
          //    isolate re-initialises Supabase on its own, so a signed-out
          //    session here is genuinely no session — not a race.
          if (SupabaseConfig.client.auth.currentUser == null) {
            debugPrint('[TELEMETRY_STOP] no session — not tracking a signed-out user');
            await _clearTrackingPrefs(prefs);
            await positionStream?.cancel();
            unawaited(service.stopSelf());
            return;
          }

          // 3. The incident this track exists for is closed. A responder
          //    resolving an alert from the console or the feed never told the
          //    reporter's phone anything, so the citizen kept transmitting long
          //    after the emergency was over.
          if (modeStr == 'sos' && currentAlertId != null) {
            try {
              final row = await SupabaseConfig.client
                  .from('alerts')
                  .select('status')
                  .eq('id', currentAlertId!)
                  .maybeSingle();
              final status = row?['status'] as String?;
              if (status == 'RESOLVED' || status == 'CANCELLED') {
                debugPrint('[TELEMETRY_STOP] alert $status — ending the track');
                await _clearTrackingPrefs(prefs);
                await positionStream?.cancel();
                unawaited(service.stopSelf());
                return;
              }
            } catch (e) {
              // Unreachable backend must never silently end an SOS track: the
              // emergency is exactly when the network is worst. Keep going.
              debugPrint('[TELEMETRY_CHECK_WARN] could not read alert status: $e');
            }
          }

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
              if (currentAlertId != null) 'alert_id': currentAlertId,
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

            // AND KEEP THE POINT.
            //
            // The upsert above overwrites: `telemetry` has `user_id` as its
            // primary key, so the database holds the CURRENT position and
            // nothing else. The trail the console draws lived only in that
            // browser tab's memory, so a refresh lost it, a second operator
            // joining mid-incident saw a dot rather than a path, and anybody
            // reviewing afterwards saw no movement at all. For a kidnapping,
            // "which way did they go" is the question, and it was being
            // discarded several times a minute.
            //
            // Only ever against an incident. No alert_id, no row — an officer
            // on ordinary patrol writes nothing here, which is what keeps this
            // from becoming the standing location feed that
            // 20260929000000 was written to remove. The 5m filter above
            // applies to this too, so a stationary handset does not fill the
            // table with the same point.
            //
            // Its own try/catch: a failure to keep the history must never stop
            // the live position being reported, and the live position is what
            // a dispatcher is looking at right now.
            if (currentAlertId != null) {
              try {
                await SupabaseConfig.client.from('incident_tracks').insert({
                  'alert_id': currentAlertId,
                  'user_id': userId,
                  'latitude': pos.latitude,
                  'longitude': pos.longitude,
                  'accuracy': pos.accuracy,
                  'speed': pos.speed,
                  'recorded_at': DateTime.now().toUtc().toIso8601String(),
                });
              } catch (e) {
                debugPrint('[TRACK_FAIL] could not keep the point: $e');
              }
            }

            if (service is AndroidServiceInstance) {
              unawaited(
                service.setForegroundNotificationInfo(
                  title: 'PLATEAU EYE',
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
      // `alertId` has always been in this payload and was never read out of it.
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
