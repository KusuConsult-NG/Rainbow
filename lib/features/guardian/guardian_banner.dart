import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/guardian/guardian_provider.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

/// The in-app notice that Guardian is on. Renders nothing when it is off.
///
/// The phone's own microphone indicator shows too; this one says whose it is
/// and opens the screen that turns it off.
class GuardianBanner extends ConsumerWidget {
  const GuardianBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(guardianProvider);
    if (!g.active) return const SizedBox.shrink();
    final lang = ref.watch(languageProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Material(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('guardian_banner'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(AppRoutes.guardian),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.hearing, color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    Translations.get('guardian_home_banner', lang),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onBackground,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
