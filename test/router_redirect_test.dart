// Regression tests for the app-wide navigation rules.
//
// `computeRedirect` is a pure function of primitives, so these run with no
// Flutter binding, no Supabase session, no device and no network. Every case
// below marked "REGRESSION" reproduces a bug that shipped.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

String? redirect({
  bool isLoading = false,
  bool isAuthenticated = true,
  UserRole role = UserRole.responder,
  bool hasOnboarded = true,
  bool isDeactivated = false,
  String? resolutionError,
  bool splashFinished = true,
  String location = AppRoutes.splash,
  bool isLocked = false,
}) {
  return computeRedirect(
    isLoading: isLoading,
    isAuthenticated: isAuthenticated,
    role: role,
    hasOnboarded: hasOnboarded,
    isDeactivated: isDeactivated,
    resolutionError: resolutionError,
    splashFinished: splashFinished,
    location: location,
    isLocked: isLocked,
  );
}

void main() {
  _reentryLockTests();
  group('gating', () {
    test('never redirects while auth is still loading', () {
      expect(redirect(isLoading: true), isNull);
    });

    test('holds on splash until the splash animation completes', () {
      expect(
        redirect(splashFinished: false, location: AppRoutes.home),
        AppRoutes.splash,
      );
    });
  });

  group('unauthenticated', () {
    test('is sent to login from anywhere', () {
      expect(
        redirect(isAuthenticated: false, location: AppRoutes.home),
        AppRoutes.login,
      );
    });

    test('is left alone once already on login', () {
      expect(
        redirect(isAuthenticated: false, location: AppRoutes.login),
        isNull,
      );
    });
  });

  group('role resolution', () {
    test('responder lands on the agent dashboard', () {
      expect(redirect(), AppRoutes.agentDashboard);
    });

    test('onboarded citizen lands on home', () {
      expect(
        redirect(role: UserRole.citizen),
        AppRoutes.home,
      );
    });

    test('new citizen goes to onboarding', () {
      expect(
        redirect(role: UserRole.citizen, hasOnboarded: false),
        AppRoutes.onboardingPermissions,
      );
    });

    // REGRESSION: the 5s safety timeout in AuthNotifier clears `isLoading`
    // while the profile fetch is still in flight. The old code returned
    // AppRoutes.login here, so any profile fetch slower than 5 seconds bounced
    // an authenticated commander through the login screen mid-incident.
    test(
        'REGRESSION: authenticated user whose role is still resolving waits on '
        'splash instead of being bounced to login', () {
      final result = redirect(
        role: UserRole.unknown,
      );
      expect(result, isNot(AppRoutes.login));
      expect(result, isNull, reason: 'already on splash — stay put');
    });

    // The role guards below only fire for a KNOWN role, so an unresolved role
    // used to sit on a role-gated screen with no check applied at all.
    test('unresolved role is parked on splash from a role-gated screen', () {
      expect(
        redirect(role: UserRole.unknown, location: AppRoutes.home),
        AppRoutes.splash,
      );
      expect(
        redirect(role: UserRole.unknown, location: AppRoutes.agentDashboard),
        AppRoutes.splash,
      );
    });

    // ...but parking from everywhere would discard in-progress work, e.g. a
    // half-filled incident report, for a state that is normally transient.
    test('unresolved role does NOT disturb a non-role-gated screen', () {
      expect(
        redirect(role: UserRole.unknown, location: AppRoutes.reportDetails),
        isNull,
      );
    });

    // REGRESSION: resolveRole() used to swallow any exception and default the
    // user to UserRole.citizen. A commander with a flaky connection or an RLS
    // denial was silently demoted to the citizen UI — and because hasOnboarded
    // stays false, pushed into the first-run onboarding wizard.
    test(
        'REGRESSION: terminal role-resolution failure goes to login, never into '
        'the citizen onboarding flow', () {
      final result = redirect(
        role: UserRole.unknown,
        resolutionError: 'PostgrestException: permission denied',
      );
      expect(result, AppRoutes.login);
      expect(result, isNot(AppRoutes.onboardingPermissions));
      expect(result, isNot(AppRoutes.home));
    });
  });

  group('role-based guards', () {
    test('citizen cannot sit on the agent dashboard', () {
      expect(
        redirect(role: UserRole.citizen, location: AppRoutes.agentDashboard),
        AppRoutes.home,
      );
    });

    test('responder is moved off the citizen home', () {
      expect(
        redirect(location: AppRoutes.home),
        AppRoutes.agentDashboard,
      );
    });

    test('deactivated account is confined to the uninstall request screen', () {
      expect(
        redirect(isDeactivated: true, location: AppRoutes.home),
        AppRoutes.uninstallRequest,
      );
      expect(
        redirect(isDeactivated: true, location: AppRoutes.uninstallRequest),
        isNull,
      );
    });
  });
}

void _reentryLockTests() {
  group('the re-entry lock', () {
    test('sends every ordinary screen to the lock', () {
      // Expressed in the router, not as a widget around some screens, because
      // a gate that a route can be reached around is not a gate — and this app
      // has thirty-odd routes, including deep links into a report in progress.
      for (final screen in <String>[
        AppRoutes.home,
        AppRoutes.agentDashboard,
        AppRoutes.settings,
        AppRoutes.incidentHistory,
        AppRoutes.reportDetails,
        AppRoutes.safeZone,
      ]) {
        expect(
          redirect(role: UserRole.citizen, location: screen, isLocked: true),
          AppRoutes.lock,
          reason: screen,
        );
      }
    });

    test('never stands in front of a running emergency', () {
      // The rule the whole design exists to protect. Someone in the middle of
      // an SOS must not be sent to read an SMS before they can see their own
      // alarm.
      expect(
        redirect(
          role: UserRole.citizen,
          location: AppRoutes.emergencyActive,
          isLocked: true,
        ),
        isNull,
      );
    });

    test('lets a locked person sign out', () {
      expect(
        redirect(
          role: UserRole.citizen,
          location: AppRoutes.login,
          isLocked: true,
        ),
        isNull,
      );
    });

    test('stays put when already on the lock screen', () {
      expect(
        redirect(
          role: UserRole.citizen,
          location: AppRoutes.lock,
          isLocked: true,
        ),
        isNull,
      );
    });

    test('does not lock somebody who is not signed in', () {
      // There is no number to send a code to. The login screen is the door.
      expect(
        redirect(
          isAuthenticated: false,
          location: AppRoutes.home,
          isLocked: true,
        ),
        AppRoutes.login,
      );
    });

    test('releases to the right home when the lock lifts', () {
      // Leaving somebody stranded on a lock screen with nothing to unlock
      // would be the same bug as the lock itself, with the sign reversed.
      expect(
        redirect(role: UserRole.citizen, location: AppRoutes.lock),
        AppRoutes.home,
      );
      expect(
        redirect(role: UserRole.responder, location: AppRoutes.lock),
        AppRoutes.agentDashboard,
      );
      expect(
        redirect(
          isAuthenticated: false,
          location: AppRoutes.lock,
        ),
        AppRoutes.login,
      );
    });

    test('a deactivated account is still handled while locked', () {
      // Order matters: the lock is checked first, so a deactivated user sees
      // the lock rather than the uninstall-request screen. That is correct —
      // we do not know yet that it is them.
      expect(
        redirect(
          role: UserRole.citizen,
          isDeactivated: true,
          location: AppRoutes.home,
          isLocked: true,
        ),
        AppRoutes.lock,
      );
    });
  });
}
