// The app has to open with no network. It did not.
//
// A signed-in handset restores its session from local storage, which needs no
// network. `AuthNotifier.resolveRole()` then set `isLoading = true` and issued
// a PostgREST fetch of `profiles` with NO timeout, and `computeRedirect` holds
// the router on the splash for as long as `isLoading` is true. The only guard
// was a single `Future.delayed(5s)` armed in the constructor — already fired by
// the time `resolveRole` re-entered loading, and a one-shot timer cannot cover
// a second entry.
//
// So with no network the app sat on the splash for as long as the operating
// system takes to abandon a TCP connection to an unreachable host, and then,
// because the failure set `resolutionError`, went to the LOGIN SCREEN — which
// offline cannot succeed. Every offline mechanism this product has (the alert
// queue, the Bluetooth mesh, the encrypted SMS fallback, USSD) sat behind a
// screen the user could not reach.
//
// See E2E_AUDIT_REPORT.md T-100.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/auth/last_known_role.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('the record this handset keeps of who it opened as', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips a responder rung', () async {
      final saved = LastKnownRole(
        userId: 'uid-1',
        role: UserRole.responder,
        tier: ResponderTier.lga,
        jurisdiction: 'MANGU',
        hasOnboarded: true,
        savedAt: DateTime.utc(2026, 10, 21, 9, 30),
      );
      await saveLastKnownRole(saved);

      final read = await readLastKnownRole('uid-1');
      expect(read, isNotNull);
      expect(read!.role, UserRole.responder);
      expect(read.tier, ResponderTier.lga);
      expect(read.jurisdiction, 'MANGU');
      expect(read.hasOnboarded, isTrue);
      expect(read.savedAt, DateTime.utc(2026, 10, 21, 9, 30));
    });

    // A phone in a command post is shared. Opening as the previous holder
    // would put somebody else's board, and their jurisdiction, in front of
    // whoever picked it up.
    test('is never handed to a different account', () async {
      await saveLastKnownRole(LastKnownRole(
        userId: 'uid-1',
        role: UserRole.responder,
        tier: ResponderTier.hq,
        hasOnboarded: true,
        savedAt: DateTime.utc(2026, 10, 21),
      ));
      expect(await readLastKnownRole('uid-2'), isNull);
    });

    test('is forgotten on sign-out', () async {
      await saveLastKnownRole(LastKnownRole(
        userId: 'uid-1',
        role: UserRole.responder,
        tier: ResponderTier.hq,
        hasOnboarded: true,
        savedAt: DateTime.utc(2026, 10, 21),
      ));
      await clearLastKnownRole();
      expect(await readLastKnownRole('uid-1'), isNull);
    });

    test('reads as absent when nothing was ever stored', () async {
      expect(await readLastKnownRole('uid-1'), isNull);
    });

    // Unreadable storage must not be the reason the app fails to open — that
    // would reintroduce the defect this file is about, one layer in.
    for (final json in <Map<String, dynamic>>[
      <String, dynamic>{'role': 'responder'},
      <String, dynamic>{'userId': 'uid-1'},
      <String, dynamic>{
        'userId': 'uid-1',
        'role': 'archbishop',
        'savedAt': '2026-10-21T00:00:00Z',
      },
      <String, dynamic>{
        'userId': 'uid-1',
        'role': 'responder',
        'savedAt': 'not a date',
      },
    ]) {
      test('refuses a malformed record rather than throwing: $json', () {
        expect(LastKnownRole.fromJson(json), isNull);
      });
    }

    // A rung this build has never heard of falls back to `unknown` rather than
    // rejecting the whole record: the ROLE is what chooses the screen.
    test('tolerates an unknown tier', () {
      final read = LastKnownRole.fromJson(<String, dynamic>{
        'userId': 'uid-1',
        'role': 'responder',
        'tier': 'brigade',
        'hasOnboarded': true,
        'savedAt': '2026-10-21T00:00:00Z',
      });
      expect(read, isNotNull);
      expect(read!.role, UserRole.responder);
      expect(read.tier, ResponderTier.unknown);
    });
  });

  group('where an offline start lands', () {
    // THE REGRESSION. A role recovered from this handset's own record is a
    // RESOLVED role: the router must open the app, not bounce the user to a
    // login screen that needs the network they do not have.
    test('a remembered responder reaches their board, not login', () {
      expect(
        computeRedirect(
          isLoading: false,
          isAuthenticated: true,
          role: UserRole.responder,
          hasOnboarded: true,
          isDeactivated: false,
          // Set, because the fetch really did fail — and no longer terminal.
          resolutionError: 'TimeoutException after 0:00:06.000000',
          splashFinished: true,
          location: AppRoutes.splash,
        ),
        AppRoutes.agentDashboard,
      );
    });

    test('a remembered citizen reaches home, not login', () {
      expect(
        computeRedirect(
          isLoading: false,
          isAuthenticated: true,
          role: UserRole.citizen,
          hasOnboarded: true,
          isDeactivated: false,
          resolutionError: 'ClientException: Failed host lookup',
          splashFinished: true,
          location: AppRoutes.splash,
        ),
        AppRoutes.home,
      );
    });

    // And the case where there IS nothing to open as is unchanged: we have
    // never known who this is, so login is the honest destination.
    test('an account never resolved on this handset still goes to login', () {
      expect(
        computeRedirect(
          isLoading: false,
          isAuthenticated: true,
          role: UserRole.unknown,
          hasOnboarded: false,
          isDeactivated: false,
          resolutionError: 'ClientException: Failed host lookup',
          splashFinished: true,
          location: AppRoutes.splash,
        ),
        AppRoutes.login,
      );
    });
  });

  group('the bound on resolution', () {
    // The number matters less than its existence, but a bound long enough to
    // be indistinguishable from the old behaviour is not a bound. Ten seconds
    // on a splash screen is already a long time to hold somebody who is
    // trying to raise an alarm.
    test('is short enough to be a bound', () {
      expect(AuthNotifier.resolveTimeout.inSeconds, lessThanOrEqualTo(10));
      expect(AuthNotifier.resolveTimeout.inSeconds, greaterThan(0));
    });
  });
}
