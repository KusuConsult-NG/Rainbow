// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

class ReportSuccessScreen extends StatelessWidget {
  const ReportSuccessScreen({
    required this.alertId,
    required this.isOffline,
    required this.reportType,
    super.key,
  });

  final String alertId;
  final bool isOffline;
  final String reportType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: (isOffline ? AppColors.warning : AppColors.success).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOffline ? Icons.cloud_off_rounded : Icons.check_circle_rounded,
                  size: 64,
                  color: isOffline ? AppColors.warning : AppColors.success,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isOffline ? 'REPORT QUEUED LOCALLY' : 'REPORT TRANSMITTED',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onBackground,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Incident Reference ID:',
                style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 4),
              SelectableText(
                alertId,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isOffline ? AppColors.warning : AppColors.success).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isOffline ? AppColors.warning : AppColors.success).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isOffline ? Icons.wifi_off_rounded : Icons.shield_rounded,
                          color: isOffline ? AppColors.warning : AppColors.success,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isOffline ? 'QUEUED IN OFFLINE STORAGE' : 'RECEIVED BY COMMAND CENTER',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: isOffline ? AppColors.warning : AppColors.success,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isOffline
                            ? 'Your incident report has been securely saved to your local offline queue. As soon as a cellular or Wi-Fi network connection is restored, it will automatically sync to Command HQ.'
                            : 'Emergency Responders and Command HQ have received your geo-tagged incident report. Patrol units in your area have been notified.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.go(AppRoutes.reportCategory),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'REPORT ANOTHER',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.go(AppRoutes.home),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'RETURN TO MAP',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
