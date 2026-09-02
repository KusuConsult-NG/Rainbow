// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/features/agent/admin_broadcast_screen.dart';
import 'package:rainbow_app/features/agent/agent_dashboard_screen.dart';
import 'package:rainbow_app/features/agent/mission_intel_screen.dart';
import 'package:rainbow_app/features/agent/mission_resolution_screen.dart';
import 'package:rainbow_app/features/agent/secure_chat_screen.dart';
import 'package:rainbow_app/features/auth/login_screen.dart';
import 'package:rainbow_app/features/citizen/dispatcher_chat_screen.dart';
import 'package:rainbow_app/features/citizen/safe_zone_screen.dart';
import 'package:rainbow_app/features/emergency/emergency_active_screen.dart';
import 'package:rainbow_app/features/history/incident_history_screen.dart';
import 'package:rainbow_app/features/home/home_screen.dart';
import 'package:rainbow_app/features/onboarding/onboarding_contacts_screen.dart';
import 'package:rainbow_app/features/onboarding/onboarding_permissions_screen.dart';
import 'package:rainbow_app/features/onboarding/onboarding_profile_screen.dart';
import 'package:rainbow_app/features/settings/emergency_pin_screen.dart';
import 'package:rainbow_app/features/report/report_category_screen.dart';
import 'package:rainbow_app/features/report/report_details_screen.dart';
import 'package:rainbow_app/features/report/report_initial_screen.dart';
import 'package:rainbow_app/features/report/report_subtype_screen.dart';
import 'package:rainbow_app/features/report/report_success_screen.dart';
import 'package:rainbow_app/features/settings/settings_screen.dart';
import 'package:rainbow_app/features/settings/uninstall_request_screen.dart';
import 'package:rainbow_app/features/splash/splash_screen.dart';
import 'package:rainbow_app/features/tracking/live_tracking_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/shared/widgets/global_navigation_shell.dart';

// Transition Helpers

/// Pure redirect decision for the whole app.
///
/// Deliberately takes primitives rather than `AuthState`/`GoRouterState` so it can
/// be unit-tested with no Flutter binding, no Supabase session and no device — see
/// `test/router_redirect_test.dart`. This function encodes every navigation rule in
/// the app; it was previously private and untestable, and two shipped bugs lived
/// here (see the comments on the `role unresolved` branch).
///
/// Returns the path to redirect to, or `null` to stay put.
String? computeRedirect({
  required bool isLoading,
  required bool isAuthenticated,
  required UserRole role,
  required bool hasOnboarded,
  required bool isDeactivated,
  required String? resolutionError,
  required bool splashFinished,
  required String location,
}) {
  // 0. Always wait for auth to finish resolving before redirecting
  if (isLoading) return null;

  // 1. Splash Logic (Wait for visual completion)
  if (!splashFinished) return AppRoutes.splash;

  final loggingIn = location == AppRoutes.login;
  final onSplash = location == AppRoutes.splash;

  // 2. Auth Logic
  if (isAuthenticated && isDeactivated) {
    return location == AppRoutes.uninstallRequest
        ? null
        : AppRoutes.uninstallRequest;
  }

  if (!isAuthenticated) {
    return loggingIn ? null : AppRoutes.login;
  }

  // 3. Post-Login Role & Onboarding Resolution
  if (loggingIn || onSplash) {
    if (role == UserRole.responder) {
      return AppRoutes.agentDashboard;
    } else if (role == UserRole.citizen) {
      return hasOnboarded ? AppRoutes.home : AppRoutes.onboardingPermissions;
    } else {
      // Authenticated, but the role has not resolved yet.
      //
      // This used to `return AppRoutes.login`, which logged real users out
      // mid-session: the 5s safety timeout in AuthNotifier clears `isLoading`
      // while `role` is still unknown, so any profile fetch slower than 5s
      // (routine on a rural network) bounced an authenticated commander to the
      // login screen before snapping them to the dashboard.
      //
      // Distinguish transient from terminal:
      //   - still resolving   -> hold on splash; the router re-runs on settle.
      //   - resolution failed -> send to login so the user can retry / re-auth.
      if (resolutionError != null) {
        return loggingIn ? null : AppRoutes.login;
      }
      return onSplash ? null : AppRoutes.splash;
    }
  }

  // 4. Role-Based Navigation Guard
  if (role == UserRole.citizen && location == AppRoutes.agentDashboard) {
    return AppRoutes.home;
  }

  if (role == UserRole.responder && location == AppRoutes.home) {
    return AppRoutes.agentDashboard;
  }

  // An unresolved role must not linger on a role-gated screen. The two guards
  // above only fire for a KNOWN role, so before this an authenticated user whose
  // role had not resolved could sit on /agent-dashboard or /home with no check
  // applied at all. Park them on splash until the role lands.
  //
  // Deliberately limited to the role-gated routes: parking on splash from every
  // location would throw away in-progress work (a half-filled incident report)
  // for a state that is normally transient.
  if (role == UserRole.unknown &&
      (location == AppRoutes.home || location == AppRoutes.agentDashboard)) {
    return AppRoutes.splash;
  }

  return null;
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    );

CustomTransitionPage<void> _slide(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (_, animation, __, child) {
        final tween = Tween(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );

/// Documentation for this public member.

class RouterNotifier extends ChangeNotifier {
  /// Documentation for this public member.
  RouterNotifier(this._ref) {
    _ref
      ..listen(authProvider, (prev, next) => notifyListeners())
      ..listen(splashFinishedProvider, (prev, next) => notifyListeners());
  }

  final Ref _ref;
}

/// Documentation for this public member.

final routerNotifierProvider = Provider<RouterNotifier>(RouterNotifier.new);

/// Documentation for this public member.

class AppRoutes {
  AppRoutes._();

  /// Documentation for this public member.
  static const String splash = '/splash';

  /// Documentation for this public member.
  static const String login = '/login';

  /// Documentation for this public member.
  static const String agentDashboard = '/agent-dashboard';

  /// Documentation for this public member.
  static const String home = '/home';

  /// Documentation for this public member.
  static const String onboardingProfile = '/onboarding-profile';

  /// Documentation for this public member.
  static const String onboardingPermissions = '/onboarding-permissions';

  /// Documentation for this public member.
  static const String onboardingContacts = '/onboarding-contacts';

  /// Documentation for this public member.
  static const String reportInitial = '/report-initial';

  /// Documentation for this public member.
  static const String reportCategory = '/report-category';

  /// Documentation for this public member.
  static const String reportSubtype = '/report-subtype';

  /// Documentation for this public member.
  static const String reportDetails = '/report-details';

  /// Documentation for this public member.
  static const String emergencyActive = '/emergency-active';

  /// Documentation for this public member.
  static const String incidentHistory = '/incident-history';

  static const String adminBroadcast = '/admin-broadcast';

  /// Documentation for this public member.
  static const String settings = '/settings';

  /// Documentation for this public member.
  static const String uninstallRequest = '/uninstall-request';

  /// Documentation for this public member.
  static const String liveTracking = '/live-tracking';

  /// Documentation for this public member.
  static const String missionIntel = '/mission-intel';

  /// Set or change the per-user safe and duress PINs.
  static const String emergencyPins = '/emergency-pins';

  /// Documentation for this public member.
  static const String missionResolution = '/mission-resolution';

  /// Documentation for this public member.
  static const String secureChat = '/secure-chat';

  /// Documentation for this public member.
  static const String safeZone = '/safe-zone';

  /// Documentation for this public member.
  static const String dispatcherChat = '/dispatcher-chat';

  /// Documentation for this public member.
  static const String reportSuccess = '/report-success';
}

/// Documentation for this public member.

final appRouter = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final splashFinished = ref.read(splashFinishedProvider);

      debugPrint(
        '🧭 [ROUTER] Redirect check: path=${state.matchedLocation}, auth=${auth.user?.id}, splashFinished=$splashFinished, role=${auth.role}',
      );

      final result = computeRedirect(
        isLoading: auth.isLoading,
        isAuthenticated: auth.user != null,
        role: auth.role,
        hasOnboarded: auth.hasOnboarded,
        isDeactivated: auth.profile?['status'] == 'deactivated',
        resolutionError: auth.resolutionError,
        splashFinished: splashFinished,
        location: state.matchedLocation,
      );
      debugPrint('🧭 [ROUTER] Redirect result: $result');
      return result;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      // ── Onboarding flow (top-level so redirect can reach them before /home loads) ──
      GoRoute(
        path: AppRoutes.onboardingProfile,
        pageBuilder: (c, s) => _slide(s, const OnboardingProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingPermissions,
        pageBuilder: (c, s) => _slide(s, const OnboardingPermissionsScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingContacts,
        pageBuilder: (c, s) => _slide(s, const OnboardingContactsScreen()),
      ),
      GoRoute(
        path: AppRoutes.emergencyActive,
        pageBuilder: (c, s) => _fade(s, const EmergencyActiveScreen()),
      ),
      // ── Persistent Navigation Shell ──
      ShellRoute(
        builder: (context, state, child) => GlobalNavigationShell(
          state: state,
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.agentDashboard,
            pageBuilder: (c, s) => _fade(s, const AgentDashboardScreen()),
          ),
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (c, s) => _fade(s, const HomeScreen()),
          ),
          GoRoute(
            path: AppRoutes.liveTracking,
            pageBuilder: (c, s) => _slide(s, const LiveTrackingScreen()),
          ),
          GoRoute(
            path: AppRoutes.emergencyPins,
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _slide(
                s,
                EmergencyPinScreen(
                  fromOnboarding: extra?['onboarding'] == true,
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.missionIntel,
            pageBuilder: (c, s) {
              final data = s.extra as Map<String, dynamic>?;
              if (data == null) return _fade(s, const AgentDashboardScreen());
              return _slide(s, MissionIntelScreen(alertData: data));
            },
          ),
          GoRoute(
            path: AppRoutes.missionResolution,
            pageBuilder: (c, s) {
              final data = s.extra as Map<String, dynamic>?;
              if (data == null) return _fade(s, const AgentDashboardScreen());
              return _slide(s, MissionResolutionScreen(alertData: data));
            },
          ),
          GoRoute(
            path: AppRoutes.secureChat,
            pageBuilder: (c, s) {
              final data = s.extra as Map<String, dynamic>?;
              if (data == null) return _fade(s, const AgentDashboardScreen());
              return _slide(s, SecureChatScreen(alertData: data));
            },
          ),
          GoRoute(
            path: AppRoutes.safeZone,
            pageBuilder: (c, s) => _slide(s, const SafeZoneScreen()),
          ),
          GoRoute(
            path: AppRoutes.dispatcherChat,
            pageBuilder: (c, s) {
              final alertId = s.extra as String?;
              if (alertId == null) return _fade(s, const HomeScreen());
              return _slide(s, DispatcherChatScreen(alertId: alertId));
            },
          ),
          GoRoute(
            path: AppRoutes.reportInitial,
            pageBuilder: (c, s) => _slide(s, const ReportInitialScreen()),
          ),
          GoRoute(
            path: AppRoutes.reportCategory,
            pageBuilder: (c, s) => _slide(s, const ReportCategoryScreen()),
          ),
          GoRoute(
            path: AppRoutes.reportSubtype,
            pageBuilder: (c, s) {
              final info = s.extra as AlertCategoryInfo?;
              if (info == null) return _fade(s, const ReportCategoryScreen());
              return _slide(s, ReportSubtypeScreen(categoryInfo: info));
            },
          ),
          GoRoute(
            path: AppRoutes.reportDetails,
            pageBuilder: (c, s) {
              final data = s.extra as Map<String, dynamic>?;
              if (data == null) return _fade(s, const ReportCategoryScreen());
              return _slide(
                s,
                ReportDetailsScreen(
                  categoryInfo: data['categoryInfo'] as AlertCategoryInfo,
                  subType: data['subType'] as String? ?? '',
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.incidentHistory,
            pageBuilder: (c, s) => _slide(s, const IncidentHistoryScreen()),
          ),
          GoRoute(
            path: AppRoutes.adminBroadcast,
            pageBuilder: (c, s) => _slide(s, const AdminBroadcastScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (c, s) => _slide(s, const SettingsScreen()),
          ),
          GoRoute(
            path: AppRoutes.uninstallRequest,
            pageBuilder: (c, s) => _slide(s, const UninstallRequestScreen()),
          ),
          GoRoute(
            path: AppRoutes.reportSuccess,
            pageBuilder: (c, s) {
              final data = s.extra as Map<String, dynamic>? ?? {};
              return _slide(
                s,
                ReportSuccessScreen(
                  alertId: data['alertId'] as String? ?? '',
                  isOffline: data['isOffline'] as bool? ?? false,
                  reportType: data['type'] as String? ?? 'INCIDENT',
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
});
