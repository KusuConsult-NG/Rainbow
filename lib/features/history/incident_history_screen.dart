// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// Documentation for this public member.

class IncidentHistoryScreen extends ConsumerWidget {
  /// Documentation for this public member.
  const IncidentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'MISSION LOGS',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
            letterSpacing: 2,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackground),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.outline, height: 1),
        ),
      ),
      body: user == null
          ? Center(
              child: Text(
                'AUTHORIZATION REQUIRED',
                style: GoogleFonts.outfit(
                  color: AppColors.emergency,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('alerts')
                  .where('reportedByUid', isEqualTo: user.uid)
                  .orderBy('reportedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.history_toggle_off_rounded,
                          size: 64,
                          color: AppColors.outline,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'NO ARCHIVED MISSIONS',
                          style: GoogleFonts.outfit(
                            color: AppColors.textDim,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Incident history will populate post-deployment.',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: AppColors.textDim.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final alerts = snapshot.data!.docs;

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  itemCount: alerts.length,
                  itemBuilder: (context, index) {
                    final doc = alerts[index];
                    final alert = doc.data() as Map<String, dynamic>? ?? {};
                    final type = (alert['type'] as String?) ?? 'EMERGENCY';
                    final status = (alert['status'] as String?) ?? 'UNKNOWN';
                    final desc =
                        (alert['description'] as String?) ?? 'No description';
                    final priority = (alert['priority'] as String?) ?? 'MEDIUM';
                    final geoLga = alert['geo_lga'] as String?;
                    final attachments =
                        (alert['mediaUrls'] as List<dynamic>?) ?? [];

                    var timeStr = '—';
                    if (alert['reportedAt'] != null) {
                      try {
                        final ts = (alert['reportedAt'] as Timestamp).toDate();
                        timeStr =
                            '${ts.day}/${ts.month} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}';
                        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
                      } catch (_) {}
                    }

                    final statusColor = status == 'RESOLVED'
                        ? AppColors.success
                        : status == 'DURESS'
                            ? AppColors.emergency
                            : AppColors.primary;

                    final isCritical = priority == 'CRITICAL';

                    return GestureDetector(
                      onTap: () => unawaited(
                        _showDetailSheet(context, doc, attachments),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isCritical
                                ? AppColors.emergency.withValues(alpha: 0.3)
                                : AppColors.outline,
                          ),
                          boxShadow: isCritical
                              ? [
                                  BoxShadow(
                                    color: AppColors.emergency
                                        .withValues(alpha: 0.05),
                                    blurRadius: 15,
                                    spreadRadius: -5,
                                  ),
                                ]
                              : [],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      if (isCritical)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: Icon(
                                            Icons.warning_amber_rounded,
                                            color: AppColors.emergency,
                                            size: 16,
                                          ),
                                        ),
                                      Text(
                                        type.toUpperCase(),
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: AppColors.onBackground,
                                          letterSpacing: 0.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: statusColor.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    status,
                                    style: GoogleFonts.outfit(
                                      color: statusColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 14,
                                  color: AppColors.textDim,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: AppColors.textDim,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const Spacer(),
                                if (geoLga != null)
                                  Text(
                                    geoLga.toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      color: AppColors.primary
                                          .withValues(alpha: 0.4),
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _showDetailSheet(
    BuildContext context,
    QueryDocumentSnapshot doc,
    List<dynamic> attachments,
  ) async {
    final alert = doc.data()! as Map<String, dynamic>;
    final alertId = doc.id;
    final lat = alert['lat'] as double?;
    final lng = alert['lng'] as double?;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ((alert['type'] as String?) ?? 'EMERGENCY')
                                .toUpperCase(),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                              color: AppColors.onBackground,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        _StatusChip((alert['status'] as String?) ?? 'UNKNOWN'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${alertId.toUpperCase()}',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: AppColors.textDim,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const _DetailLabel('OPERATIONAL NARRATIVE'),
                    const SizedBox(height: 12),
                    Text(
                      (alert['description'] as String?) ??
                          'No description provided.',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 40),
                    if (alert['geo_lga'] != null) ...[
                      const _DetailLabel('DEPLOYMENT SECTOR'),
                      const SizedBox(height: 12),
                      _InfoRow(
                        Icons.map_rounded,
                        '${alert['geo_lga']} › ${alert['geo_ward']}',
                      ),
                      const SizedBox(height: 32),
                    ],
                    const _DetailLabel('MISSION TELEMETRY'),
                    const SizedBox(height: 12),
                    _InfoRow(
                      Icons.radar_rounded,
                      'UNIT: ${((alert['assigned_to'] as String?) ?? 'UNASSIGNED').replaceAll('_', ' ')}',
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      Icons.trending_up_rounded,
                      'PRIORITY: ${(alert['priority'] as String?) ?? 'MEDIUM'}',
                    ),
                    const SizedBox(height: 40),
                    if (lat != null && lng != null) ...[
                      const _DetailLabel('GEOSPATIAL BEACON'),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final url = Uri.parse(
                            'https://www.google.com/maps?q=$lat,$lng',
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: AppColors.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: AppColors.primary,
                                  letterSpacing: 1,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                    if (attachments.isNotEmpty) ...[
                      const _DetailLabel('INTEL ATTACHMENTS'),
                      const SizedBox(height: 12),
                      ...attachments.map(
                        (url) => GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse(url.toString());
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.file_copy_rounded,
                                  color: AppColors.textDim,
                                  size: 20,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'INTEL_FILE_${attachments.indexOf(url) + 1}.DAT',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textSecondary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.download_rounded,
                                  size: 18,
                                  color: AppColors.textDim,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          unawaited(
                            context.push(
                              AppRoutes.dispatcherChat,
                              extra: doc.id,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AppColors.accent.withValues(alpha: 0.1),
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'CONTACT HQ DISPATCHER',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: alertId));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'LOG ID COPIED',
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceContainer,
                          foregroundColor: AppColors.onBackground,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'COPY MISSION HASH',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'RESOLVED'
        ? AppColors.success
        : status == 'DURESS'
            ? AppColors.emergency
            : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: GoogleFonts.outfit(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _DetailLabel extends StatelessWidget {
  const _DetailLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: AppColors.textDim,
          letterSpacing: 2,
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textDim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      );
}
