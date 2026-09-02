import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  // The deep link is wired HERE rather than inside the service so the service
  // knows nothing about routes: it decides WHICH alert to open, the provider
  // decides WHERE that goes. That is also what makes the tap handler testable
  // without a router.
  return PushNotificationService(
    openAlert: (alert) => unawaited(
      ref.read(appRouter).push(AppRoutes.missionIntel, extra: alert),
    ),
    openFallback: () => ref.read(appRouter).go(AppRoutes.agentDashboard),
  );
});

/// A tapped notification that should open something.
@immutable
class NotificationTarget {
  /// Documentation for this public member.
  const NotificationTarget({required this.alertId});

  /// The alert the responder should be taken to.
  final String alertId;

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget && other.alertId == alertId;

  @override
  int get hashCode => alertId.hashCode;
}

/// Decides whether a notification payload is a deep link this app handles.
///
/// Pure: no I/O and no navigation, so the rule can be tested without a device.
/// Only DISPATCH and ALERT carry an incident to open; anything else — a
/// broadcast, a malformed payload, a future notification type — must be ignored
/// rather than navigating somewhere arbitrary.
NotificationTarget? notificationTarget(Map<String, dynamic>? data) {
  if (data == null) return null;
  final alertId = data['alertId'];
  final type = data['type'];
  if (alertId is! String || alertId.isEmpty) return null;
  if (type != 'DISPATCH' && type != 'ALERT') return null;
  return NotificationTarget(alertId: alertId);
}

class PushNotificationService {
  /// Documentation for this public member.
  PushNotificationService({this.openAlert, this.openFallback});

  /// Opens the mission intel screen for a full alert row.
  final void Function(Map<String, dynamic> alert)? openAlert;

  /// Where to land when the alert itself cannot be loaded.
  final void Function()? openFallback;

  static const String _oneSignalAppId = '885be8b2-5f31-4627-a618-685f54dd266a';

  Future<void> initialize() async {
    try {
      if (kDebugMode) {
        unawaited(OneSignal.Debug.setLogLevel(OSLogLevel.verbose));
      }

      // Initialize OneSignal SDK
      unawaited(OneSignal.initialize(_oneSignalAppId));

      // Prompt for push notification permissions
      await OneSignal.Notifications.requestPermission(true);

      // Link current Supabase User ID with OneSignal External ID
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        await OneSignal.login(userId);
        debugPrint('[ONESIGNAL] User logged in to OneSignal with ID: $userId');
      }

      // Get initial OneSignal Push Subscription ID (Player ID)
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId != null && playerId.isNotEmpty) {
        debugPrint('[ONESIGNAL] Subscription ID (Player ID) acquired: $playerId');
        await _saveTokenToProfile(playerId);
      }

      // Listen to subscription state changes
      OneSignal.User.pushSubscription.addObserver((state) async {
        final newPlayerId = state.current.id;
        debugPrint('[ONESIGNAL] Subscription state changed. New ID: $newPlayerId');
        if (newPlayerId != null && newPlayerId.isNotEmpty) {
          await _saveTokenToProfile(newPlayerId);
        }
      });

      // Listen for foreground notification clicks or receipts
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        debugPrint('[ONESIGNAL_FG] Notification received: ${event.notification.title} - ${event.notification.body}');
        event.notification.display();
      });

      OneSignal.Notifications.addClickListener((event) {
        debugPrint('[ONESIGNAL_CLICK] Notification clicked: ${event.notification.title}');
        unawaited(handleNotificationTap(event.notification.additionalData));
      });
    } catch (e) {
      debugPrint('[ONESIGNAL_ERR] OneSignal push notification init failed: $e');
    }
  }

  /// Opens the incident a tapped notification refers to.
  ///
  /// THIS WAS BROKEN THREE SEPARATE WAYS, all of which had to be fixed together:
  ///
  ///   1. It navigated through a `static GlobalKey<NavigatorState> navigatorKey`
  ///      that NOTHING ever assigned, so the key was always null and the tap
  ///      was a silent no-op.
  ///   2. Even with the key set it called `pushNamed('/mission-intel')`. This
  ///      app routes with go_router via `MaterialApp.router`, which registers
  ///      no named routes on the Navigator — so that call could not have
  ///      resolved regardless.
  ///   3. It passed `{'alertId': id}` as the argument, but the mission-intel
  ///      route expects the FULL alert row in `extra` and reads type, severity,
  ///      description, coordinates and media from it. A payload carrying only
  ///      an id renders an incident with no detail.
  ///
  /// So the id is resolved into the real row before navigating. If that read
  /// fails the responder is sent to their dashboard rather than nowhere: they
  /// tapped a dispatch notification, and the incident should be in their feed.
  @visibleForTesting
  Future<void> handleNotificationTap(Map<String, dynamic>? data) async {
    final target = notificationTarget(data);
    if (target == null) return;

    final alert = await loadAlertRow(target.alertId);
    if (alert == null) {
      openFallback?.call();
      return;
    }
    openAlert?.call(alert);
  }

  /// Reads the alert row a notification refers to. Null when it cannot be read.
  @visibleForTesting
  Future<Map<String, dynamic>?> loadAlertRow(String alertId) async {
    try {
      final row = await SupabaseConfig.client
          .from('alerts')
          .select()
          .eq('id', alertId)
          .maybeSingle();
      return row;
    } catch (e) {
      debugPrint('[ONESIGNAL_ERR] Could not load alert $alertId for deep link: $e');
      return null;
    }
  }

  Future<void> _saveTokenToProfile(String playerId) async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        await SupabaseConfig.client.from('profiles').update({
          'onesignal_player_id': playerId,
          'push_enabled': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
        debugPrint('[ONESIGNAL] Player ID synced to profile for user $userId');
      }
    } catch (e) {
      debugPrint('[ONESIGNAL_ERR] Failed to save OneSignal player ID to Supabase: $e');
    }
  }
}
