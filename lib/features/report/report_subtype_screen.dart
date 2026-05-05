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
      appBar: const RainbowAppBar(title: 'REPORT INCIDENT', subtitle: 'STEP 2 OF 3 — SELECT TYPE', showBack: true),
      body: Column(
        children: [
          // Category banner
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cat.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cat.color.withAlpha(80)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: cat.color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                child: Icon(cat.icon, color: cat.color, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SELECTED CATEGORY', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: cat.color, letterSpacing: 1.5)),
                  Text(cat.label, style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, color: cat.color)),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Text('CHANGE', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: cat.color, letterSpacing: 1.0)),
                ),
              ),
            ]),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('WHAT HAPPENED?', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.outline, letterSpacing: 2.0)),
                const SizedBox(height: 12),
                ...cat.subTypes.map((sub) => _SubTypeRow(
                  label: sub,
                  color: cat.color,
                  bg: cat.bg,
                  selected: _selected == sub,
                  onTap: () => setState(() => _selected = sub),
                )),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, -5))]),
        child: ElevatedButton(
          onPressed: _selected == null ? null : () {
            context.push(AppRoutes.reportDetails, extra: {
              'category': cat,
              'subType': _selected,
            });
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: _selected == null ? AppColors.surfaceContainerHigh : AppColors.primary,
          ),
          child: Text(
            _selected == null ? 'SELECT A TYPE TO CONTINUE' : 'NEXT: ADD DETAILS',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5, color: _selected == null ? AppColors.outline : Colors.white),
          ),
        ),
      ),
    );
  }
}

class _SubTypeRow extends StatelessWidget {
  final String label;
  final Color color, bg;
  final bool selected;
  final VoidCallback onTap;
  const _SubTypeRow({required this.label, required this.color, required this.bg, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(15) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : AppColors.outlineVariant.withAlpha(100), width: selected ? 2 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(selected ? 15 : 6), blurRadius: selected ? 12 : 8)],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? color : Colors.transparent,
                border: Border.all(color: selected ? color : AppColors.outline, width: 2),
              ),
              child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: GoogleFonts.inter(fontWeight: selected ? FontWeight.w800 : FontWeight.w500, fontSize: 15, color: selected ? color : AppColors.onSurface))),
            if (selected) Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
          ],
        ),
      ),
    );
  }
}
