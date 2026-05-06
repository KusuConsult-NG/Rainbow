import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/alert_categories.dart';
import '../../shared/widgets/rainbow_app_bar.dart';
import '../../shared/widgets/bottom_nav_bar.dart';

class ReportCategoryScreen extends StatelessWidget {
  const ReportCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'INCIDENT PROTOCOL', 
        subtitle: 'SELECT CATEGORY FOR TACTICAL REPORT'
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hub_rounded, color: AppColors.primary, size: 24),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'SELECT THE CATEGORY THAT BEST DESCRIBES THE CURRENT EMERGENCY. LOCATION TELEMETRY IS AUTO-ATTACHED.',
                    style: GoogleFonts.outfit(
                      fontSize: 10, 
                      color: Colors.white70, 
                      height: 1.5, 
                      fontWeight: FontWeight.w800, 
                      letterSpacing: 0.5
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'AVAILABLE CATEGORIES',
            style: GoogleFonts.outfit(
              fontSize: 10, 
              fontWeight: FontWeight.w900, 
              color: Colors.white24, 
              letterSpacing: 2.0
            ),
          ),
          const SizedBox(height: 20),
          ...alertCategories.map((cat) => _CategoryCard(
            info: cat,
            onTap: () => context.push(AppRoutes.reportSubtype, extra: cat),
          )),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: const RainbowBottomNav(currentIndex: 2),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final AlertCategoryInfo info;
  final VoidCallback onTap;
  const _CategoryCard({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = info.color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${info.subTypes.length} OPERATIONAL SUBTYPES',
                    style: GoogleFonts.outfit(
                      fontSize: 10, 
                      color: Colors.white24, 
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: info.subTypes.take(2).map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Text(
                        s.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 8, 
                          fontWeight: FontWeight.w900, 
                          color: Colors.white38, 
                          letterSpacing: 0.5
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.05), size: 16),
          ],
        ),
      ),
    );
  }
}
