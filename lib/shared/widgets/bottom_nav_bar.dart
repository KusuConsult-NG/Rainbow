import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

import 'package:rainbow_app/providers/auth_provider.dart';

/// Documentation for this public member.

class RainbowBottomNav extends ConsumerWidget {
  /// Documentation for this public member.
  const RainbowBottomNav({required this.currentIndex, super.key});

  /// Documentation for this public member.
  final int currentIndex;

  static final _allItems = [
    const _NavItem(
      id: 0,
      icon: Icons.shield_outlined,
      activeIcon: Icons.shield_rounded,
      label: 'DASHBOARD',
      route: AppRoutes.agentDashboard,
    ),
    const _NavItem(
      id: 1,
      icon: Icons.radar_outlined,
      activeIcon: Icons.radar_rounded,
      label: 'MOVEMENT',
      route: AppRoutes.liveTracking,
    ),
    const _NavItem(
      id: 2,
      icon: Icons.report_outlined,
      activeIcon: Icons.report_rounded,
      label: 'NEW REPORT',
      route: AppRoutes.reportCategory,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isStaff = auth.role != UserRole.citizen;

    final items = _allItems.map((item) {
      if (item.id == 0 && !isStaff) {
        return const _NavItem(
          id: 0,
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: 'HOME',
          route: AppRoutes.home,
        );
      }
      return item;
    }).where((item) {
      if (!isStaff && item.id == 1) return false;
      return true;
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.outline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children:
                items.map((item) => _buildNavItem(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, _NavItem item) {
    final isActive = item.id == currentIndex;
    return GestureDetector(
      onTap: () {
        if (!isActive) context.go(item.route);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive ? AppColors.primary : AppColors.textDim,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              style: GoogleFonts.outfit(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w900 : FontWeight.w800,
                color: isActive ? AppColors.primary : AppColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.id,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
  final int id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
}
