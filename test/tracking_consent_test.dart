// When does this app STOP watching somebody?
//
// It had one answer: when the person entered their safe PIN on that handset.
// Every other way an emergency can end left the phone transmitting its
// position every few seconds, indefinitely, with nothing on screen to say so:
//
//   * a DURESS PIN deliberately keeps tracking running — that is the point of
//     a duress code, and it is defensible while the person may be in danger —
//     but nothing ever ended it, so one duress entry meant tracking for the
//     life of the install;
//   * a responder resolving the incident from the console or the feed never
//     told the reporter's phone anything;
//   * SIGNING OUT cleared the session and the secure storage and left the
//     background service running, because its keys are in SharedPreferences
//     and the isolate re-initialises Supabase by itself.
//
// The last one is the plainest: signing out is the clearest statement a person
// can make that they are done being observed, and it was the one action that
// did not stop it.
//
// AND IT HAS ONE EXCEPTION, which is the first bullet above arriving from the
// other side. A duress PIN keeps tracking running because the person may still
// be in danger, and the lock screen's sign-out needs no code — so a sign-out
// could end a live duress trail with no PIN at all. Sign-out now stops a
// RESPONDER's patrol track, as asserted below, and leaves an SOS track running
// until the incident closes or the twelve-hour ceiling expires. That half is in
// test/signout_during_emergency_test.dart; the tests here are the no-emergency
// case, which is still the common one and still works this way.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the SOS tracking window', () {
    test('is bounded', () {
      // The value can be argued about; its existence cannot. An unbounded
      // covert track is the defect, whatever number replaces this one.
      expect(BackgroundTrackingService.sosTrackingMaxAge.inHours, greaterThan(0));
      expect(
        BackgroundTrackingService.sosTrackingMaxAge.inDays,
        lessThanOrEqualTo(1),
        reason: 'a track that outlives a day is no longer "while they may '
            'still be in danger"',
      );
    });

    test('is long enough to cover a real response', () {
      expect(
        BackgroundTrackingService.sosTrackingMaxAge.inHours,
        greaterThanOrEqualTo(6),
        reason: 'cutting a live SOS track short is the opposite failure, and '
            'the more dangerous one',
      );
    });
  });

  group('signing out', () {
    tearDown(() => AuthService.stopTrackingOverride = null);

    test('stops location tracking', () async {
      var stopped = false;
      AuthService.stopTrackingOverride = () async {
        stopped = true;
      };

      // signOut also reaches Supabase and secure storage, neither of which
      // exists here. What this pins is that tracking is stopped FIRST, so a
      // failure further down cannot leave it running.
      try {
        await AuthService(SecureStorageService()).signOut();
      } catch (_) {
        // expected: no Supabase client under `flutter test`
      }

      expect(
        stopped,
        isTrue,
        reason: 'signOut cleared the session and left the phone transmitting',
      );
    });

    test('stops tracking even when stopping throws', () async {
      var attempted = false;
      AuthService.stopTrackingOverride = () async {
        attempted = true;
        throw StateError('no platform channels under test');
      };

      try {
        await AuthService(SecureStorageService()).signOut();
      } catch (_) {
        // The sign-out itself must not be abandoned because the background
        // service could not be reached.
      }

      expect(attempted, isTrue);
    });
  });
}
