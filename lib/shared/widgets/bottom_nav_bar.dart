import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

final userRoleProvider = FutureProvider<String>((ref) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'CITIZEN';
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!doc.exists) return 'CITIZEN';
    // Fix #7: safe cast — rules denial or missing field returns 'CITIZEN'
    return doc.data()?['role'] as String? ?? 'CITIZEN';
  } catch (_) {
    // Firestore rules denied OR network error — degrade gracefully
    return 'CITIZEN';
  }
});

class RainbowBottomNav extends ConsumerWidget {
  final int currentIndex;

  const RainbowBottomNav({super.key, required this.currentIndex});

  static final _allItems = [
    const _NavItem(id: 0, icon: Icons.shield_outlined, activeIcon: Icons.shield_rounded, label: 'SAFETY', route: AppRoutes.home),
    const _NavItem(id: 1, icon: Icons.radar_outlined, activeIcon: Icons.radar_rounded, label: 'TRACKING', route: AppRoutes.liveTracking),
    const _NavItem(id: 2, icon: Icons.report_outlined, activeIcon: Icons.report_rounded, label: 'REPORTS', route: AppRoutes.reportCategory),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(userRoleProvider);
    final role = roleAsync.value ?? 'CITIZEN';

    final items = _allItems.where((item) {
      if (item.id == 1 && role != 'RESPONDENT') return false; // Hide Tracking for non-respondents
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.map((item) => _buildNavItem(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, _NavItem item) {
    final isActive = item.id == currentIndex;
    return GestureDetector(
      onTap: () { if (!isActive) context.go(item.route); },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: isActive
            ? BoxDecoration(
                color: AppColors.primary.withAlpha(13),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive ? AppColors.primary : AppColors.outline,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isActive ? AppColors.primary : AppColors.outline,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final int id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  const _NavItem({required this.id, required this.icon, required this.activeIcon, required this.label, required this.route});
}
