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
    return doc.data()?['role'] as String? ?? 'CITIZEN';
  } catch (_) {
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
      if (item.id == 1 && role != 'RESPONDENT') return false; 
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1)
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive ? AppColors.primary : Colors.white24,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              style: GoogleFonts.outfit(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w900 : FontWeight.w800,
                color: isActive ? AppColors.primary : Colors.white24,
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
  final int id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  const _NavItem({required this.id, required this.icon, required this.activeIcon, required this.label, required this.route});
}
