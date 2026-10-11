// Signing out must not end the tracking of a live emergency.
//
// `signOut()` stopped tracking first, deliberately: "Signing out is the
// clearest statement a person can make that they are done being observed, and
// it was the one action that did not stop it."
//
// Right about a person signing out of their own phone. Wrong in the one case
// the duress design exists for: a duress PIN tells the person their alarm is
// cancelled and KEEPS TRACKING RUNNING because they may still be in danger —
// and the lock screen's sign-out needs no code. So whoever held the phone could
// end a live duress trail without knowing any PIN, and HQ saw a track go quiet,
// indistinguishable from a flat battery.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> signOut() async {
  try {
    await AuthService(SecureStorageService()).signOut();
  } catch (_) {
    // No Supabase client under `flutter test`; the seams below are what this
    // file asserts on.
  }
}

void main() {
  var stopped = 0;
  var stamped = <String>[];

  setUp(() {
    stopped = 0;
    stamped = <String>[];
    AuthService.stopTrackingOverride = () async => stopped++;
    AuthService.stampSignOutOverride = (id) async => stamped.add(id);
    AuthService.forgetSmsKeyOverride = () async {};
    AuthService.forgetSimBaselineOverride = () async {};
    AuthService.stopMeshOverride = () async {};
    addTearDown(() {
      AuthService.stopTrackingOverride = null;
      AuthService.stampSignOutOverride = null;
      AuthService.forgetSmsKeyOverride = null;
      AuthService.forgetSimBaselineOverride = null;
      AuthService.stopMeshOverride = null;
      AuthService.activeSosOverride = null;
    });
  });

  group('with no emergency open', () {
    test('a patrol track stops, because the officer is off duty', () async {
      AuthService.activeSosOverride = () async => null;
      await signOut();
      expect(stopped, 1);
      expect(stamped, isEmpty);
    });
  });

  group('with an emergency still open', () {
    test('tracking is NOT stopped', () async {
      AuthService.activeSosOverride = () async => 'alert-1';
      await signOut();
      expect(stopped, 0,
          reason: 'the lock screen sign-out needs no code, so this is the one '
              'path a captor can reach');
    });

    test('and HQ is told the app is gone, against that incident', () async {
      AuthService.activeSosOverride = () async => 'alert-1';
      await signOut();
      expect(stamped, ['alert-1'],
          reason: 'a track going quiet reads as a dead battery; this is what '
              'makes it a fact an operator can act on');
    });

    test('a failed stamp does not abandon the sign-out', () async {
      AuthService.activeSosOverride = () async => 'alert-1';
      AuthService.stampSignOutOverride = (_) async => throw StateError('offline');
      var retired = false;
      AuthService.forgetSmsKeyOverride = () async => retired = true;
      await signOut();
      expect(retired, isTrue,
          reason: 'a phone being switched off must not have its sign-out '
              'blocked on a network write');
      expect(stopped, 0, reason: 'and the track still survives');
    });
  });

  group('when the tracking mode cannot be read', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('the track stops, because nothing is telling it to be on an SOS',
        () async {
      // `activeSosAlertId()` swallows its own read failure and answers null.
      // Not a compromise: the background isolate learns its mode from the same
      // store, so an unreadable store means there is no SOS track to preserve
      // — and the privacy rule above ("done being observed") then applies.
      AuthService.activeSosOverride = null;
      await signOut();
      expect(stopped, 1);
      expect(stamped, isEmpty, reason: 'and there is no incident to stamp');
    });
  });

  group('what the tracking service reports', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing, when nothing is tracked', () async {
      expect(await BackgroundTrackingService().activeSosAlertId(), isNull);
    });

    test('nothing, for a responder patrol', () async {
      SharedPreferences.setMockInitialValues({
        'trackingMode': 'responder',
        'activeTrackingUserId': 'u1',
      });
      expect(await BackgroundTrackingService().activeSosAlertId(), isNull);
    });

    test('the alert, for a live SOS track', () async {
      SharedPreferences.setMockInitialValues({
        'trackingMode': 'sos',
        'activeTrackingAlertId': 'alert-9',
        'trackingExpiresAt':
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
      expect(await BackgroundTrackingService().activeSosAlertId(), 'alert-9');
    });

    test('nothing once the twelve-hour ceiling has passed', () async {
      // An expired track is not a live emergency, and the ceiling exists
      // precisely because a duress entry left tracking with no end.
      SharedPreferences.setMockInitialValues({
        'trackingMode': 'sos',
        'activeTrackingAlertId': 'alert-9',
        'trackingExpiresAt':
            DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      });
      expect(await BackgroundTrackingService().activeSosAlertId(), isNull);
    });

    test('nothing when the mode says SOS but no incident is named', () async {
      SharedPreferences.setMockInitialValues({
        'trackingMode': 'sos',
        'activeTrackingAlertId': '',
      });
      expect(await BackgroundTrackingService().activeSosAlertId(), isNull);
    });
  });
}
