// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// Documentation for this public member.

class ReportCategoryScreen extends ConsumerStatefulWidget {
  /// [situation] narrows the list to one of the four Situation Report cards
  /// ('danger', 'crime', 'suspicious', 'environment'). Null shows all twelve.
  const ReportCategoryScreen({super.key, this.situation});

  final String? situation;

  @override
  ConsumerState<ReportCategoryScreen> createState() =>
      _ReportCategoryScreenState();
}

class _ReportCategoryScreenState extends ConsumerState<ReportCategoryScreen> {
  late String? _situation = widget.situation;

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final shown = categoriesForSituation(_situation);
    final narrowed = shown.length < alertCategories.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: Translations.get('incident_protocol', lang),
        subtitle: Translations.get('select_category_subtitle', lang),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.hub_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    Translations.get('select_category_desc', lang),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      height: 1.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            Translations.get('available_categories', lang),
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.textDim,
              letterSpacing: 2,
            ),
          ),
          if (narrowed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${Translations.get('rpt_showing_some', lang).replaceAll('{n}', '${shown.length}').replaceAll('{total}', '${alertCategories.length}')}',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('show_all_categories'),
                  onPressed: () => setState(() => _situation = null),
                  child: Text(
                    Translations.get('rpt_show_all_categories', lang),
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          ...shown.map(
            (cat) => _CategoryCard(
              info: cat,
              onTap: () => context.push(AppRoutes.reportSubtype, extra: cat),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.info, required this.onTap});
  final AlertCategoryInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = info.color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(info.icon, color: color, size: 28),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.label.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.onBackground,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${info.subTypes.length} OPERATIONAL SUBTYPES',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: info.subTypes
                        .take(2)
                        .map(
                          (s) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child: Text(
                              s.toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textDim,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.outline,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
