import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

class ReportInitialScreen extends StatelessWidget {
  const ReportInitialScreen({super.key});

  void _proceed(BuildContext context, String filter) {
    HapticFeedback.lightImpact();
    // We can pass the filter to the next screen using extra if needed,
    // but for now we just transition to the category list as Step 2.
    context.push(AppRoutes.reportList);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
           padding: const EdgeInsets.symmetric(horizontal: 24),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               const SizedBox(height: 16),
               Text(
                 "What's going on?",
                 style: GoogleFonts.inter(
                   fontSize: 32,
                   fontWeight: FontWeight.w900,
                   color: AppColors.onSurface,
                   letterSpacing: -1.0,
                 ),
               ),
               const SizedBox(height: 8),
               Text(
                 "Tell us briefly. We'll guide you through the rest.",
                 style: GoogleFonts.inter(
                   fontSize: 16,
                   color: AppColors.onSurfaceVariant,
                   fontWeight: FontWeight.w500,
                 ),
               ),
               const SizedBox(height: 48),

               _IntentCard(
                 title: 'Someone is in danger',
                 icon: Icons.warning_rounded,
                 color: const Color(0xFFD32F2F),
                 bg: const Color(0xFFFFEBEE),
                 onTap: () => _proceed(context, 'danger'),
               ),
               _IntentCard(
                 title: "There's a crime",
                 icon: Icons.local_police_rounded,
                 color: const Color(0xFF1976D2),
                 bg: const Color(0xFFE3F2FD),
                 onTap: () => _proceed(context, 'crime'),
               ),
               _IntentCard(
                 title: 'Something feels wrong',
                 icon: Icons.visibility_rounded,
                 color: const Color(0xFFF57F17),
                 bg: const Color(0xFFFFF9C4),
                 onTap: () => _proceed(context, 'suspicious'),
               ),
               _IntentCard(
                 title: "It's an environmental issue",
                 icon: Icons.water_damage_rounded,
                 color: const Color(0xFF00796B),
                 bg: const Color(0xFFE0F2F1),
                 onTap: () => _proceed(context, 'environment'),
               ),
             ],
           ),
        ),
      ),
    );
  }
}

class _IntentCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _IntentCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(50), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color.withAlpha(220),
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: color.withAlpha(100)),
          ],
        ),
      ),
    );
  }
}
