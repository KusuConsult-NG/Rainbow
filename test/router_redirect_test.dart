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
  );
}

void main() {
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
      expect(redirect(role: UserRole.responder), AppRoutes.agentDashboard);
    });

    test('onboarded citizen lands on home', () {
      expect(
        redirect(role: UserRole.citizen, hasOnboarded: true),
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
        resolutionError: null,
        location: AppRoutes.splash,
      );
      expect(result, isNot(AppRoutes.login));
      expect(result, isNull, reason: 'already on splash — stay put');
    });

    test('unresolved role from another route is parked on splash', () {
      expect(
        redirect(role: UserRole.unknown, location: AppRoutes.home),
        AppRoutes.splash,
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
        location: AppRoutes.splash,
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
        redirect(role: UserRole.responder, location: AppRoutes.home),
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
