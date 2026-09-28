// When the app locks itself, and — more importantly — when it must not.
//
// A lock screen in front of a panic button is a liability, so every rule below
// is a rule about NOT locking. They are tested as a pure function because a
// mistake in any of them is not a cosmetic bug: it is a person holding a phone
// they cannot use, in the situation the phone was for.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/auth/reentry_lock.dart';

void main() {
  group('coming back to the app', () {
    test('asks for a code after being away', () {
      expect(
        reentryDecision(
          awayFor: const Duration(minutes: 10),
          hasSession: true,
          emergencyActive: false,
        ),
        LockDecision.lock,
      );
    });

    test('does not lock while an SOS is running', () {
      // The worst thing this feature could do. The person is in the middle of
      // the emergency the app exists for; being told to go and read an SMS
      // before they can see their own alarm is not a safety measure.
      expect(
        reentryDecision(
          awayFor: const Duration(hours: 3),
          hasSession: true,
          emergencyActive: true,
        ),
        LockDecision.emergencyInProgress,
      );
    });

    test('does not lock for a moment away', () {
      // Reporting an incident means switching to the camera. Being told to
      // ring someone means switching to the dialler. Both background the app,
      // and neither is leaving it.
      expect(
        reentryDecision(
          awayFor: const Duration(seconds: 20),
          hasSession: true,
          emergencyActive: false,
        ),
        LockDecision.withinGrace,
      );
    });

    test('does not lock when nobody is signed in', () {
      // The login screen is already the door. A lock screen in front of it
      // would ask an unauthenticated person to prove a number we do not have.
      expect(
        reentryDecision(
          awayFor: const Duration(days: 1),
          hasSession: false,
          emergencyActive: false,
        ),
        LockDecision.noSession,
      );
    });

    test('a live emergency outranks everything else', () {
      // Both "no session" and "emergency" could describe an edge case at the
      // same time; the order matters, so it is asserted rather than assumed.
      expect(
        reentryDecision(
          awayFor: const Duration(days: 1),
          hasSession: true,
          emergencyActive: true,
        ),
        LockDecision.emergencyInProgress,
      );
    });

    test('the boundary is the grace window itself', () {
      const grace = Duration(minutes: 2);
      expect(
        shouldLockOnResume(
          awayFor: grace - const Duration(seconds: 1),
          hasSession: true,
          emergencyActive: false,
          grace: grace,
        ),
        isFalse,
      );
      expect(
        shouldLockOnResume(
          awayFor: grace,
          hasSession: true,
          emergencyActive: false,
          grace: grace,
        ),
        isTrue,
      );
    });

    test('the default grace window is long enough to take a photo', () {
      // If this is ever shortened to seconds, every incident report that
      // includes a photograph costs the person an SMS and a wait, in the
      // middle of reporting an emergency.
      expect(reentryGraceWindow.inSeconds, greaterThanOrEqualTo(60));
      // And short enough that a phone left on a desk is not open all afternoon.
      expect(reentryGraceWindow.inMinutes, lessThanOrEqualTo(5));
    });
  });

  group('what can actually be done on the lock screen', () {
    test('with a connection, a code can be sent', () {
      expect(unlockPathFor(online: true), UnlockPath.codeBySms);
    });

    test('with no connection, nothing can verify anyone', () {
      // Not a pessimistic guess: the code needs the network to arrive, and the
      // emergency PIN is checked by a database function, so it needs the
      // network too. A lock screen showing a code box during a blackout — the
      // condition this whole product is built around — is asking for something
      // that cannot come.
      expect(unlockPathFor(online: false), UnlockPath.emergencyOnly);
    });

    test('offline, the screen says so and points at the panic button', () {
      final text = lockScreenExplanation(UnlockPath.emergencyOnly);
      expect(text.toLowerCase(), contains('offline'));
      expect(text.toLowerCase(), contains('emergency button still works'));
    });

    test('online, the screen explains why it is asking', () {
      final text = lockScreenExplanation(UnlockPath.codeBySms);
      expect(text.toLowerCase(), contains('code'));
      expect(text, isNot(contains('offline')));
    });
  });
}
