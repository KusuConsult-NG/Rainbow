import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/guardian/guardian_provider.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

/// The in-app notice that Guardian is on — and, until somebody has read the
/// Guardian notice once, the only thing in the app that says it exists.
///
/// The phone's own microphone indicator shows too; this one says whose it is
/// and opens the screen that turns it off.
///
/// WHY IT ALSO SHOWS WHEN GUARDIAN IS OFF. It used to render nothing unless a
/// session was already running, so it was a way OUT of Guardian and never a
/// way in. Guardian is reached from exactly two places in this app: this
/// banner, and a tile most of the way down Settings. With the banner hidden
/// until the feature was on, the tile was the only route, and a person looking
/// for a voice SOS on the home screen found AI REPORT — a different feature —
/// and nothing else. The feature was reported as not working. Nothing was
/// broken: 124 tests cover the session and the rules. Nobody could find it.
///
/// The way in disappears once [guardianConsentProvider] is accepted, because
/// by then the person has read what Guardian does and decided. An emergency
/// home screen is not a place to keep advertising.
class GuardianBanner extends ConsumerWidget {
  const GuardianBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(guardianProvider);
    if (!g.active) {
      if (ref.watch(guardianConsentProvider)) return const SizedBox.shrink();
      return const _GuardianWayIn();
    }
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


/// The one-time signpost: Guardian exists, here is where it lives.
///
/// Deliberately quiet — muted, one line, no colour that competes with the SOS
/// button underneath it. It is a signpost, not an alarm.
class _GuardianWayIn extends ConsumerWidget {
  const _GuardianWayIn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Material(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('guardian_way_in'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(AppRoutes.guardian),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.hearing, color: AppColors.textDim, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    Translations.get('guardian_home_way_in', lang),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 13,
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
