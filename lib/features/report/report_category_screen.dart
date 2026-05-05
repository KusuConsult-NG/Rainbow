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
      appBar: const RainbowAppBar(title: 'REPORT INCIDENT', subtitle: 'STEP 2 OF 3 — SELECT CATEGORY'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.help_outline_rounded, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(child: Text('Select the category that best describes the incident. Your location will be auto-attached.', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant, height: 1.5))),
            ]),
          ),
          const SizedBox(height: 20),
          Text('INCIDENT CATEGORIES', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.outline, letterSpacing: 2.0)),
          const SizedBox(height: 12),
          ...alertCategories.map((cat) => _CategoryCard(
            info: cat,
            onTap: () => context.push(AppRoutes.reportSubtype, extra: cat),
          )),
          const SizedBox(height: 80),
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

  Color get _textColor => info.color;
  Color get _bgColor => info.bg;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border(left: BorderSide(color: _textColor, width: 5)),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 12)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(14)),
              child: Icon(info.icon, color: _textColor, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(info.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(info.label.toUpperCase(), style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, color: _textColor, letterSpacing: 0.5)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${info.subTypes.length} incident types', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: info.subTypes.take(3).map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(20)),
                      child: Text(s, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: _textColor)),
                    )).toList(),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _textColor, size: 24),
          ],
        ),
      ),
    );
  }
}
