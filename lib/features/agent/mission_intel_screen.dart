// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

class MissionIntelScreen extends ConsumerWidget {
  const MissionIntelScreen({required this.alertData, super.key});

  final Map<String, dynamic> alertData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = alertData['type'] as String? ?? 'INCIDENT';
    final severity = alertData['severity'] as String? ?? 'MEDIUM';
    final desc = alertData['description'] as String? ?? 'No details provided';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'TACTICAL MISSION INTEL',
        subtitle: 'INCIDENT DATA DOSSIER',
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type.toUpperCase(),
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'SEVERITY: $severity',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.warning,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              desc,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.onBackground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
