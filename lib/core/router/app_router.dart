import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/agent/agent_dashboard_screen.dart';
import '../../features/onboarding/onboarding_permissions_screen.dart';
import '../../features/onboarding/onboarding_profile_screen.dart';
import '../../features/onboarding/onboarding_contacts_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/emergency/emergency_active_screen.dart';
import '../../features/tracking/live_tracking_screen.dart';
import '../../features/report/report_category_screen.dart';
import '../../features/report/report_subtype_screen.dart';
import '../../features/report/report_details_screen.dart';
import '../../features/report/report_initial_screen.dart';
import '../../features/history/incident_history_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../core/constants/alert_categories.dart';

class AppRoutes {
  AppRoutes._();
  static const String splash = '/splash';
  static const String login = '/login';
  static const String agentDashboard = '/agent-dashboard';
  static const String onboardingPermissions = '/onboarding/permissions';
  static const String onboardingProfile = '/onboarding/permissions/profile';
  static const String onboardingContacts = '/onboarding/permissions/profile/contacts';
  static const String home = '/home';
  static const String emergencyActive = '/home/emergency-active';
  static const String liveTracking = '/home/tracking';
  static const String reportCategory = '/home/report/category';
  static const String reportList = '/home/report/category/list';
  static const String reportSubtype = '/home/report/category/list/subcategory';
  static const String reportDetails = '/home/report/category/list/subcategory/details';
  static const String incidentHistory = '/home/history';
  static const String settings = '/home/settings';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: false,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      pageBuilder: (c, s) => _fade(s, const SplashScreen()),
    ),
    // ── Unified Login
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: (c, s) => _fade(s, const LoginScreen()),
    ),
    // Agent dashboard is a root (PopScope guarded inside the screen)
    GoRoute(
      path: AppRoutes.agentDashboard,
      pageBuilder: (c, s) {
        final roleId = s.extra as String? ?? 'AGENT';
        return _slide(s, AgentDashboardScreen(roleId: roleId));
      },
    ),
    // Onboarding screens
    GoRoute(
      path: AppRoutes.onboardingPermissions,
      pageBuilder: (c, s) => _slide(s, const OnboardingPermissionsScreen()),
      routes: [
        GoRoute(
          path: 'profile',
          pageBuilder: (c, s) => _slide(s, const OnboardingProfileScreen()),
          routes: [
            GoRoute(
              path: 'contacts',
              pageBuilder: (c, s) => _slide(s, const OnboardingContactsScreen()),
            ),
          ],
        ),
      ],
    ),
    // Home is a root (PopScope guarded inside the screen)
    GoRoute(
      path: AppRoutes.home,
      pageBuilder: (c, s) => _fade(s, const HomeScreen()),
      routes: [
        // Emergency is pushed on top of home
        GoRoute(
          path: 'emergency-active',
          pageBuilder: (c, s) => _fade(s, const EmergencyActiveScreen()),
        ),
        GoRoute(
          path: 'tracking',
          pageBuilder: (c, s) => _slide(s, const LiveTrackingScreen()),
        ),
        // Report flow — each pushed on top so pop() chain works
        GoRoute(
          path: 'report/category',
          pageBuilder: (c, s) => _slide(s, const ReportInitialScreen()),
          routes: [
            GoRoute(
              path: 'list',
              pageBuilder: (c, s) => _slide(s, const ReportCategoryScreen()),
              routes: [
                GoRoute(
                  path: 'subcategory',
                  pageBuilder: (c, s) {
                    // Fix #1 & #10: safe cast + empty list guard
                    final extra = s.extra is AlertCategoryInfo ? s.extra as AlertCategoryInfo : null;
                    final fallback = alertCategories.isNotEmpty ? alertCategories.first : null;
                    if (extra == null && fallback == null) {
                      return _slide(s, const SizedBox()); // defensive empty screen
                    }
                    return _slide(s, ReportSubtypeScreen(categoryInfo: extra ?? fallback!));
                  },
                  routes: [
                    GoRoute(
                      path: 'details',
                      pageBuilder: (c, s) {
                        // Fix #1: safe map cast
                        final extra = s.extra is Map<String, dynamic> ? s.extra as Map<String, dynamic> : null;
                        final fallback = alertCategories.isNotEmpty ? alertCategories.first : null;
                        return _slide(
                          s,
                          ReportDetailsScreen(
                            categoryInfo: (extra?['category'] is AlertCategoryInfo
                                ? extra!['category'] as AlertCategoryInfo
                                : fallback) ?? alertCategories.first,
                            subType: extra?['subType'] as String? ?? '',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: 'history',
          pageBuilder: (c, s) => _slide(s, const IncidentHistoryScreen()),
        ),
        GoRoute(
          path: 'settings',
          pageBuilder: (c, s) => _slide(s, const SettingsScreen()),
        ),
      ],
    ),
  ],
);

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
        final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
