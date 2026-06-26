import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// Documentation for this public member.

class ReportSubtypeScreen extends StatefulWidget {
  /// Documentation for this public member.
  const ReportSubtypeScreen({required this.categoryInfo, super.key});

  /// Documentation for this public member.
  final AlertCategoryInfo categoryInfo;

  @override
  State<ReportSubtypeScreen> createState() => _ReportSubtypeScreenState();
}

class _ReportSubtypeScreenState extends State<ReportSubtypeScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final cat = widget.categoryInfo;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'REPORT PROTOCOL',
        subtitle: 'SELECT SPECIFIC INCIDENT TYPE',
        showBack: true,
      ),
      body: Column(
        children: [
          // Category banner
          Container(
            margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cat.color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cat.color.withValues(alpha: 0.2)),
                  ),
                  child: Icon(cat.icon, color: cat.color, size: 24),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TACTICAL CATEGORY',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: cat.color.withValues(alpha: 0.6),
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        cat.label.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: AppColors.onBackground,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Text(
                      'CHANGE',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textSecondary,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              children: [
                Text(
                  'IDENTIFY INCIDENT TYPE',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDim,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                ...cat.subTypes.map(
                  (sub) => _TacticalSubTypeRow(
                    label: sub,
                    color: cat.color,
                    selected: _selected == sub,
                    onTap: () => setState(() => _selected = sub),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: _selected == null
                ? null
                : () {
                    unawaited(
                      context.push(
                        AppRoutes.reportDetails,
                        extra: {
                          'categoryInfo': cat,
                          'subType': _selected,
                        },
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.black.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            child: Text(
              _selected == null
                  ? 'IDENTIFICATION REQUIRED'
                  : 'INITIATE TACTICAL REPORT',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.5,
                color: _selected == null ? AppColors.textDim : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TacticalSubTypeRow extends StatelessWidget {
  const _TacticalSubTypeRow({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? color : Colors.transparent,
                border: Border.all(
                  color: selected ? color : AppColors.outline,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
                    )
                  : null,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.outfit(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 15,
                  color: selected
                      ? AppColors.onBackground
                      : AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (selected) Icon(Icons.radar_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
