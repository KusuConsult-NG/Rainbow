// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

/// Shown after a citizen successfully files a report.
/// Displays the alert ID and live status stream for the filed incident.
class ReportSuccessScreen extends StatelessWidget {
  /// Documentation for this public member.
  const ReportSuccessScreen({
    required this.alertId,
    required this.isOffline,
    required this.reportType,
    super.key,
  });

  /// Documentation for this public member.

  final String alertId;

  /// Documentation for this public member.
  final bool isOffline;

  /// Documentation for this public member.
  final String reportType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.home),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: const Icon(
                        Icons.home_rounded,
                        color: AppColors.textDim,
                        size: 20,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'MISSION FILED',
                    style: GoogleFonts.outfit(
                      color: AppColors.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 44), // balance
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 32),

                  // Success icon
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            (isOffline ? AppColors.warning : AppColors.success)
                                .withValues(alpha: 0.1),
                        border: Border.all(
                          color: (isOffline
                                  ? AppColors.warning
                                  : AppColors.success)
                              .withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        isOffline
                            ? Icons.cloud_queue_rounded
                            : Icons.check_circle_outline_rounded,
                        color:
                            isOffline ? AppColors.warning : AppColors.success,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  Text(
                    isOffline ? 'REPORT QUEUED' : 'TRANSMISSION CONFIRMED',
                    style: GoogleFonts.outfit(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isOffline
                        ? 'Your report is stored locally and will transmit when connectivity is restored.'
                        : 'Your incident report has been received by HQ and is being assessed.',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Alert ID Card
                  if (alertId.isNotEmpty) ...[
                    Text(
                      'MISSION REFERENCE',
                      style: GoogleFonts.outfit(
                        color: AppColors.textDim,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: alertId));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'MISSION HASH COPIED',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              backgroundColor: AppColors.surfaceContainerHigh,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.tag_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                alertId.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  letterSpacing: 1,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.copy_rounded,
                              color: AppColors.textDim,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Live status stream
                  if (alertId.isNotEmpty) ...[
                    Text(
                      'LIVE STATUS',
                      style: GoogleFonts.outfit(
                        color: AppColors.textDim,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('alerts')
                          .doc(alertId)
                          .snapshots(),
                      builder: (context, snap) {
                        final data =
                            snap.data?.data() as Map<String, dynamic>? ?? {};
                        final status =
                            (data['status'] as String?) ?? 'PROCESSING';
                        final assignedTo = (data['assigned_to'] as String?) ??
                            'AWAITING DISPATCH';
                        final lga = data['geo_lga'] as String?;
                        final ward = data['geo_ward'] as String?;

                        final statusColor = status == 'RESOLVED'
                            ? AppColors.success
                            : status == 'OPEN' ||
                                    status == 'ACTIVE' ||
                                    status == 'DISPATCHED'
                                ? AppColors.primary
                                : AppColors.warning;

                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: statusColor.withValues(
                                            alpha: 0.5,
                                          ),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    status,
                                    style: GoogleFonts.outfit(
                                      color: statusColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _StatusRow(
                                Icons.radar_rounded,
                                'ASSIGNED UNIT',
                                assignedTo,
                              ),
                              if (lga != null) ...[
                                const SizedBox(height: 10),
                                _StatusRow(
                                  Icons.map_rounded,
                                  'SECTOR',
                                  '${lga.toUpperCase()}${ward != null ? ' › ${ward.toUpperCase()}' : ''}',
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.go(AppRoutes.incidentHistory),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: Text(
                        'VIEW MISSION HISTORY',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => context.go(AppRoutes.home),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textDim,
                        side: const BorderSide(color: AppColors.outline),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        'RETURN TO BASE',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textDim),
        const SizedBox(width: 10),
        Text(
          '$label  ',
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: AppColors.textDim,
            letterSpacing: 1.5,
          ),
        ),
        Expanded(
          child: Text(
            value.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
