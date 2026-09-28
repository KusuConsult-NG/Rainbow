import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

/// Documentation for this public member.

class TacticalDrawer extends ConsumerWidget {
  /// Documentation for this public member.
  const TacticalDrawer({super.key});

  /// Close the drawer, THEN go.
  ///
  /// Every item here navigated without closing it. Two of the four destinations
  /// — SECURITY HUB and MISSION ARCHIVE — live inside the app's navigation
  /// shell, so pushing them keeps the shell's Scaffold mounted and its open
  /// drawer sits on top of the screen that just loaded. The screen IS there,
  /// greyed out behind the drawer; to the officer, the tap simply did nothing,
  /// and they would have to swipe the drawer away to discover otherwise.
  ///
  /// The other two hid it by accident: EXTRACTION LIST's route is outside the
  /// shell, so it replaces the whole tree including the drawer, and TERMINATE
  /// SESSION uses `context.go`, which does the same. So the two that looked
  /// broken and the two that looked fine differed only in where their
  /// destination happened to sit in the route table.
  static void _leave(BuildContext context, VoidCallback go) {
    // Close first. `maybePop` rather than `pop` so this cannot take a route
    // with it if the drawer is somehow already closed.
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    go();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: AppColors.background,
      width: MediaQuery.of(context).size.width * 0.8,
      child: Column(
        children: [
          const DrawerHeaderWidget(),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                DrawerTile(
                  icon: Icons.shield_rounded,
                  label: 'SECURITY HUB',
                  onTap: () => _leave(context, () => context.push(AppRoutes.settings)),
                ),
                DrawerTile(
                  icon: Icons.history_edu_rounded,
                  label: 'MISSION ARCHIVE',
                  onTap: () => _leave(context, () => context.push(AppRoutes.incidentHistory)),
                ),
                DrawerTile(
                  icon: Icons.contact_emergency_rounded,
                  label: 'EXTRACTION LIST',
                  onTap: () => _leave(context, () => context.push(AppRoutes.onboardingContacts)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: AppColors.outline, height: 1),
                ),
                DrawerTile(
                  icon: Icons.power_settings_new_rounded,
                  label: 'TERMINATE SESSION',
                  color: AppColors.emergency,
                  onTap: () async {
                    // Closed first here too, so a slow sign-out does not leave
                    // the drawer sitting over a half-torn-down session.
                    final nav = Navigator.of(context);
                    final scaffold = Scaffold.maybeOf(context);
                    if (scaffold?.isDrawerOpen ?? false) nav.pop();
                    await ref.read(authProvider.notifier).signOut();
                    if (context.mounted) context.go(AppRoutes.login);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'v1.4.2 · ENCRYPTED CONNECTION',
              style: GoogleFonts.outfit(
                color: AppColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Documentation for this public member.

class DrawerHeaderWidget extends ConsumerWidget {
  const DrawerHeaderWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(bottom: BorderSide(color: AppColors.primaryDark)),
      ),
      child: Builder(
        builder: (context) {
          final authState = ref.watch(authProvider);
          final user = authState.user;
          final profile = authState.profile;
          final name = profile?['full_name'] as String? ?? user?.email ?? 'OPERATIVE';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'O',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name.toUpperCase(),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'ID: 08000000000',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Documentation for this public member.

class DrawerTile extends StatelessWidget {
  /// Documentation for this public member.
  const DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    super.key,
  });

  /// Documentation for this public member.
  final IconData icon;

  /// Documentation for this public member.
  final String label;

  /// Documentation for this public member.
  final VoidCallback onTap;

  /// Documentation for this public member.
  final Color? color;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (color ?? AppColors.onBackground).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color ?? AppColors.textSecondary, size: 20),
        ),
        title: Text(
          label,
          style: GoogleFonts.outfit(
            color: color ?? AppColors.onBackground,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        onTap: onTap,
      );
}
