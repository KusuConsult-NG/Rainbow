// Tapping an emergency push notification.
//
// This was dead code: `navigatorKey` was never assigned by anything, so the
// deep link was a silent no-op. It was found by a lint
// (use_setters_to_change_properties pointing at a setter with no callers) and
// left documented rather than guessed at, because "wiring it needs a device".
//
// It did need a device to confirm the notification ARRIVES. It did not need one
// to test what happens when it does — which is the part that was broken, three
// separate ways:
//
//   1. the navigator key was always null;
//   2. it called Navigator.pushNamed on an app that routes with go_router via
//      MaterialApp.router, which registers no named routes at all;
//   3. it passed only `{'alertId': id}`, but the mission-intel route reads the
//      FULL alert row from `extra` — type, severity, description, coordinates,
//      media.
//
// Any one of those alone would have made the tap useless. So the fix is tested
// end to end short of the OneSignal callback itself: payload → decision → row
// lookup → navigation.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/push_notification_service.dart';

import 'support/offline_supabase.dart';

void main() {
  group('notificationTarget — which payloads are deep links', () {
    test('a DISPATCH payload with an alert id opens that alert', () {
      expect(
        notificationTarget({'type': 'DISPATCH', 'alertId': 'alert-1'}),
        const NotificationTarget(alertId: 'alert-1'),
      );
    });

    test('an ALERT payload does too', () {
      expect(
        notificationTarget({'type': 'ALERT', 'alertId': 'alert-2'}),
        const NotificationTarget(alertId: 'alert-2'),
      );
    });

    // Anything else must be ignored rather than navigating somewhere
    // arbitrary. A responder taken to the wrong incident is worse than one
    // taken nowhere.
    test('other notification types are not deep links', () {
      for (final type in ['BROADCAST', 'INFO', '', 'dispatch']) {
        expect(
          notificationTarget({'type': type, 'alertId': 'alert-1'}),
          isNull,
          reason: '$type must not deep-link',
        );
      }
    });

    test('a payload with no alert id is not a deep link', () {
      expect(notificationTarget({'type': 'DISPATCH'}), isNull);
      expect(notificationTarget({'type': 'DISPATCH', 'alertId': ''}), isNull);
      expect(notificationTarget({'type': 'DISPATCH', 'alertId': 42}), isNull);
    });

    test('an absent payload is not a deep link', () {
      expect(notificationTarget(null), isNull);
      expect(notificationTarget(<String, dynamic>{}), isNull);
    });
  });

  group('handleNotificationTap', () {
    const alertRow = {
      'id': 'alert-1',
      'type': 'CIVIL_UNREST',
      'severity': 'CRITICAL',
      'description': 'Crowd building at the market',
      'latitude': 9.9167,
      'longitude': 8.8917,
    };

    test('opens the FULL alert row, not just the id it was sent', () async {
      final db = installOfflineSupabase(
        handler: jsonRows([alertRow]),
      );
      expect(db, isNotNull);

      Map<String, dynamic>? opened;
      var fellBack = false;
      final service = PushNotificationService(
        openAlert: (a) => opened = a,
        openFallback: () => fellBack = true,
      );

      await service.handleNotificationTap(
        {'type': 'DISPATCH', 'alertId': 'alert-1'},
      );

      expect(fellBack, isFalse);
      expect(opened, isNotNull);
      // The whole point of resolving the id: the screen needs these.
      expect(opened!['severity'], 'CRITICAL');
      expect(opened!['description'], 'Crowd building at the market');
      expect(opened!['latitude'], 9.9167);
    });

    test('does nothing at all for a payload that is not a deep link', () async {
      installOfflineSupabase(handler: jsonRows([alertRow]));

      var opened = false;
      var fellBack = false;
      final service = PushNotificationService(
        openAlert: (_) => opened = true,
        openFallback: () => fellBack = true,
      );

      await service.handleNotificationTap({'type': 'BROADCAST'});

      expect(opened, isFalse);
      expect(fellBack, isFalse);
    });

    // The responder tapped a dispatch notification. Landing them on their
    // dashboard — where the incident should appear in their feed — is a far
    // better answer than the silent nothing this used to do.
    test('falls back to the dashboard when the alert cannot be read', () async {
      installOfflineSupabase(handler: jsonError(403, 'permission denied'));

      var opened = false;
      var fellBack = false;
      final service = PushNotificationService(
        openAlert: (_) => opened = true,
        openFallback: () => fellBack = true,
      );

      await service.handleNotificationTap(
        {'type': 'DISPATCH', 'alertId': 'alert-1'},
      );

      expect(opened, isFalse);
      expect(fellBack, isTrue);
    });

    test('falls back when the alert no longer exists', () async {
      installOfflineSupabase(handler: jsonRows([]));

      var opened = false;
      var fellBack = false;
      final service = PushNotificationService(
        openAlert: (_) => opened = true,
        openFallback: () => fellBack = true,
      );

      await service.handleNotificationTap(
        {'type': 'DISPATCH', 'alertId': 'gone'},
      );

      expect(opened, isFalse);
      expect(fellBack, isTrue);
    });

    // A service built without the callbacks (the default constructor) must not
    // throw — the app still runs if the deep link is not wired.
    test('a service with no navigation callbacks is harmless', () async {
      installOfflineSupabase(handler: jsonRows([alertRow]));
      final service = PushNotificationService();

      await expectLater(
        service.handleNotificationTap(
          {'type': 'DISPATCH', 'alertId': 'alert-1'},
        ),
        completes,
      );
    });
  });
}
