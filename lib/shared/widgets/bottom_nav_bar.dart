import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';

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
            children: [
              for (final item in items) ...[
                _buildNavItem(context, item),
                // The citizen's SOS sits between HOME and NEW REPORT, so it is
                // in the bar on every screen that has one — reports, safe
                // zones, history, settings — and not only on Home.
                if (!isStaff && item.id == 0) const SosNavButton(),
              ],
            ],
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

/// The SOS control in the bottom bar.
///
/// Three taps inside [sosTapWindow] raise a Silent SOS and leave the user on
/// the screen they were on: no alarm, no banner, no emergency screen. One or
/// two taps send nothing. Once an emergency is running the control carries a
/// small steady dot and a single tap opens the emergency screen — the way back
/// to HOLD TO CANCEL and the Safe/Duress PIN pad, which a silent SOS otherwise
/// had no route to.
class SosNavButton extends ConsumerWidget {
  const SosNavButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active =
        ref.watch(emergencyProvider.select((s) => s.isEmergencyActive));

    void onTap() {
      switch (registerSosTap(ref.read)) {
        case SosTapOutcome.counting:
          break;
        case SosTapOutcome.sent:
          // The lightest tick the platform has: enough for the hand that sent
          // it, nothing anybody else in the room would notice.
          unawaited(HapticFeedback.selectionClick());
        case SosTapOutcome.alreadyActive:
          context.go(AppRoutes.emergencyActive);
      }
    }

    return Semantics(
      button: true,
      label: active
          ? 'SOS is active. Open it to cancel with your PIN.'
          : 'Emergency. Tap three times quickly to send a silent SOS.',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        key: const ValueKey('nav_sos'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.emergency.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.emergency.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(
                    Icons.emergency_rounded,
                    color: AppColors.emergency,
                    size: 22,
                  ),
                  if (active)
                    Positioned(
                      key: const ValueKey('nav_sos_active'),
                      right: -4,
                      top: -2,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.emergency,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Just SOS. It used to read "SOS ×3", which put a keystroke
              // recipe in the one place on the screen that has to be read in
              // a second, and read as a product name rather than a control.
              // How to use it belongs on the button that teaches it (the big
              // SOS on the home screen says TAP 3 TIMES) and in the semantics
              // label above, which is what a screen reader announces.
              Text(
                'SOS',
                style: GoogleFonts.outfit(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: AppColors.emergency,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
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
