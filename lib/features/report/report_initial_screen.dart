// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:rainbow_app/core/router/safe_pop.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

/// Documentation for this public member.

class ReportInitialScreen extends StatelessWidget {
  /// Documentation for this public member.
  const ReportInitialScreen({super.key});

  void _proceed(BuildContext context, String filter) {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(context.push(AppRoutes.reportCategory, extra: filter));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background ambient glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton(
                           tooltip: 'Close',
                    onPressed: () => context.popOrGo(AppRoutes.home),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.onBackground,
                      size: 28,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.05),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'SITUATION REPORT',
                              style: GoogleFonts.outfit(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'What is the\nsituation?',
                          style: GoogleFonts.outfit(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: AppColors.onBackground,
                            height: 1.1,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Select the most accurate category to ensure rapid response deployment.',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 48),
                        _TacticalIntentCard(
                          title: 'THREAT TO LIFE',
                          subtitle: 'Immediate danger to persons',
                          icon: Icons.warning_amber_rounded,
                          accent: AppColors.emergency,
                          onTap: () => _proceed(context, 'danger'),
                        ),
                        _TacticalIntentCard(
                          title: 'CRIMINAL ACTIVITY',
                          subtitle: 'Ongoing or witnessed crime',
                          icon: Icons.security_rounded,
                          accent: Colors.blueAccent,
                          onTap: () => _proceed(context, 'crime'),
                        ),
                        _TacticalIntentCard(
                          title: 'SUSPICIOUS ACTIVITY',
                          subtitle: 'Something feels wrong',
                          icon: Icons.visibility_rounded,
                          accent: Colors.amber,
                          onTap: () => _proceed(context, 'suspicious'),
                        ),
                        _TacticalIntentCard(
                          title: 'CIVIL HAZARD',
                          subtitle: 'Environmental or infrastructure risk',
                          icon: Icons.alt_route_rounded,
                          accent: Colors.tealAccent,
                          onTap: () => _proceed(context, 'environment'),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalIntentCard extends StatelessWidget {
  const _TacticalIntentCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: accent, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.onBackground,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}
