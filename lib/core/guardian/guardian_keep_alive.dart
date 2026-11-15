/// Keeps a Guardian session listening with the app in the background.
///
/// ANDROID. An app may use the microphone in the background only while it
/// runs a foreground service of the "microphone" type, started while the app
/// is on screen, which a Guardian session always is. The service shows a
/// permanent notification, "Guardian is listening", with a Stop button: a
/// person can always see that the microphone is in use and end it without
/// opening the app. The listening itself stays in the app; the service only
/// keeps the app alive and visible.
///
/// IPHONE. iOS keeps an app running in the background while it records, when
/// the app declares the "audio" background mode (Info.plist). Nothing more
/// is needed here; iOS shows its own microphone indicator.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

abstract class GuardianKeepAlive {
  /// Starts keeping the app alive. False when it could not, in which case the
  /// session falls back to pausing in the background.
  Future<bool> start({
    required String title,
    required String text,
    required String stopLabel,
  });

  Future<void> stop();

  /// [callback] runs when the person presses Stop on the notification.
  void whenStopPressed(void Function()? callback);
}

class PlatformGuardianKeepAlive implements GuardianKeepAlive {
  void Function()? _onStop;
  bool _listening = false;

  static const int _serviceId = 4711;
  static const String _stopId = 'guardian_stop';

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void whenStopPressed(void Function()? callback) => _onStop = callback;

  void _onData(Object data) {
    if (data == _stopId) _onStop?.call();
  }

  @override
  Future<bool> start({
    required String title,
    required String text,
    required String stopLabel,
  }) async {
    if (!_android) return true;
    try {
      if ((await FlutterForegroundTask.checkNotificationPermission()) !=
          NotificationPermission.granted) {
        // Asked once; refused, the service still runs, but Android hides its
        // notification, so the session says so on its own screen.
        await FlutterForegroundTask.requestNotificationPermission();
      }
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'guardian_listening',
          channelName: 'AI Emergency Guardian',
          channelDescription: 'Shown while Guardian is listening for distress.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
        ),
      );
      if (!_listening) {
        FlutterForegroundTask.addTaskDataCallback(_onData);
        _listening = true;
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: title,
        notificationText: text,
        notificationButtons: [NotificationButton(id: _stopId, text: stopLabel)],
        callback: guardianKeepAliveCallback,
      );
      return result is ServiceRequestSuccess;
    } on Object catch (e) {
      debugPrint('[GUARDIAN] keep-alive did not start: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_android) return;
    try {
      if (_listening) {
        FlutterForegroundTask.removeTaskDataCallback(_onData);
        _listening = false;
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } on Object catch (e) {
      debugPrint('[GUARDIAN] keep-alive did not stop: $e');
    }
  }
}

/// Entry point of the service's own isolate. It does no work of its own: it
/// passes a press of Stop back to the app.
@pragma('vm:entry-point')
void guardianKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_GuardianTaskHandler());
}

class _GuardianTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == PlatformGuardianKeepAlive._stopId) {
      FlutterForegroundTask.sendDataToMain(PlatformGuardianKeepAlive._stopId);
    }
  }
}
