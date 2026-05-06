import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/alert_categories.dart';
import '../../shared/widgets/rainbow_app_bar.dart';

class ReportSubtypeScreen extends StatefulWidget {
  final AlertCategoryInfo categoryInfo;
  const ReportSubtypeScreen({super.key, required this.categoryInfo});

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
        showBack: true
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
                          letterSpacing: 1.5
                        )
                      ),
                      Text(
                        cat.label.toUpperCase(), 
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900, 
                          fontSize: 18, 
                          color: Colors.white, 
                          letterSpacing: 0.5
                        )
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05), 
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(
                      'CHANGE', 
                      style: GoogleFonts.outfit(
                        fontSize: 10, 
                        fontWeight: FontWeight.w900, 
                        color: Colors.white70, 
                        letterSpacing: 1.0
                      )
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
                    color: Colors.white24, 
                    letterSpacing: 2.0
                  )
                ),
                const SizedBox(height: 20),
                ...cat.subTypes.map((sub) => _TacticalSubTypeRow(
                  label: sub,
                  color: cat.color,
                  selected: _selected == sub,
                  onTap: () => setState(() => _selected = sub),
                )),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: _selected == null ? null : () {
              context.push(AppRoutes.reportDetails, extra: {
                'category': cat,
                'subType': _selected,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.02),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: Text(
              _selected == null ? 'IDENTIFICATION REQUIRED' : 'INITIATE TACTICAL REPORT',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900, 
                fontSize: 13, 
                letterSpacing: 1.5, 
                color: _selected == null ? Colors.white10 : Colors.black
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TacticalSubTypeRow extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _TacticalSubTypeRow({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05), 
            width: selected ? 2 : 1
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? color : Colors.transparent,
                border: Border.all(
                  color: selected ? color : Colors.white24, 
                  width: 2
                ),
              ),
              child: selected 
                ? const Icon(Icons.check_rounded, color: Colors.black, size: 14) 
                : null,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.outfit(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 15,
                  color: selected ? Colors.white : Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (selected) 
              Icon(Icons.radar_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
