// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'TACTICAL SYSTEM SETTINGS',
        subtitle: 'PREFERENCES & SECURITY',
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListTile(
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.person_outline, color: AppColors.primary),
            title: Text(
              auth.profile?['full_name'] ?? 'Citizen User',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.onBackground),
            ),
            subtitle: Text(
              auth.user?.email ?? 'Phone User: 08000000000',
              style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.security_outlined, color: AppColors.warning),
            title: Text(
              'App Removal Authorization',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.onBackground),
            ),
            onTap: () => context.push(AppRoutes.uninstallRequest),
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: AppColors.danger.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
            title: Text(
              'Sign Out Tactical Session',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.danger),
            ),
            onTap: () async {
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
      ),
    );
  }
}
