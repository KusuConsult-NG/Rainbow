import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/widgets/bottom_nav_bar.dart';
import 'package:rainbow_app/shared/widgets/tactical_drawer.dart';

/// Documentation for this public member.

class GlobalNavigationShell extends StatelessWidget {
  /// Documentation for this public member.
  const GlobalNavigationShell({
    required this.child,
    required this.state,
    super.key,
  });

  /// Documentation for this public member.

  final Widget child;

  /// Documentation for this public member.
  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    var currentIndex = -1;
    if (state.matchedLocation == AppRoutes.agentDashboard ||
        state.matchedLocation == AppRoutes.home) {
      currentIndex = 0;
    } else if (state.matchedLocation.startsWith(AppRoutes.liveTracking)) {
      currentIndex = 1;
    } else if (state.matchedLocation.startsWith('/report')) {
      currentIndex = 2;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TacticalDrawer(),
      body: child,
      bottomNavigationBar: RainbowBottomNav(currentIndex: currentIndex),
    );
  }
}
