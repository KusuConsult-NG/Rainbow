import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';

class IncidentHistoryScreen extends ConsumerWidget {
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
            color: Colors.white,
            letterSpacing: 2.0,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.white.withValues(alpha: 0.05), height: 1),
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
                  .where('reportedBy', isEqualTo: user.uid)
                  .orderBy('reportedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.02)),
                        const SizedBox(height: 24),
                        Text(
                          'NO ARCHIVED MISSIONS',
                          style: GoogleFonts.outfit(
                            color: Colors.white24,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Incident history will populate post-deployment.',
                          style: GoogleFonts.outfit(fontSize: 11, color: Colors.white10, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final alerts = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  itemCount: alerts.length,
                  itemBuilder: (context, index) {
                    final doc = alerts[index];
                    final alert = doc.data() as Map<String, dynamic>? ?? {};
                    final type = alert['type'] ?? 'EMERGENCY';
                    final status = alert['status'] ?? 'UNKNOWN';
                    final desc = alert['description'] ?? 'No description';
                    final priority = alert['priority'] ?? 'MEDIUM';
                    final geoLga = alert['geo_lga'] as String?;
                    final attachments = (alert['attachments'] as List<dynamic>?) ?? [];

                    String timeStr = '—';
                    if (alert['reportedAt'] != null) {
                      try {
                        final ts = (alert['reportedAt'] as Timestamp).toDate();
                        timeStr = '${ts.day}/${ts.month} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}';
                      } catch (_) {}
                    }

                    final statusColor = status == 'RESOLVED'
                        ? AppColors.safe
                        : status == 'DURESS'
                            ? AppColors.emergency
                            : AppColors.primary;

                    final isCritical = priority == 'CRITICAL';

                    return GestureDetector(
                      onTap: () => _showDetailSheet(context, alert, doc.id, attachments),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isCritical 
                                ? AppColors.emergency.withValues(alpha: 0.3) 
                                : Colors.white.withValues(alpha: 0.05),
                          ),
                          boxShadow: isCritical ? [
                            BoxShadow(
                              color: AppColors.emergency.withValues(alpha: 0.05),
                              blurRadius: 15,
                              spreadRadius: -5,
                            )
                          ] : [],
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
                                          child: Icon(Icons.warning_amber_rounded, color: AppColors.emergency, size: 16),
                                        ),
                                      Text(
                                        type.toUpperCase(),
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    status,
                                    style: GoogleFonts.outfit(
                                      color: statusColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 1.0,
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
                                color: Colors.white54,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                const Icon(Icons.schedule_rounded, size: 14, color: Colors.white12),
                                const SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: Colors.white24,
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
                                      color: AppColors.primary.withValues(alpha: 0.4),
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

  void _showDetailSheet(BuildContext context, Map<String, dynamic> alert, String alertId, List<dynamic> attachments) {
    final lat = alert['lat'] as double?;
    final lng = alert['lng'] as double?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
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
                            (alert['type'] ?? 'EMERGENCY').toUpperCase(),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        _StatusChip(alert['status'] ?? 'UNKNOWN'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${alertId.toUpperCase()}',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: Colors.white12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    const _DetailLabel('OPERATIONAL NARRATIVE'),
                    const SizedBox(height: 12),
                    Text(
                      alert['description'] ?? 'No description provided.',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        height: 1.6,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 40),

                    if (alert['geo_lga'] != null) ...[
                      const _DetailLabel('DEPLOYMENT SECTOR'),
                      const SizedBox(height: 12),
                      _InfoRow(Icons.map_rounded, '${alert['geo_lga']} › ${alert['geo_ward']}'),
                      const SizedBox(height: 32),
                    ],

                    const _DetailLabel('MISSION TELEMETRY'),
                    const SizedBox(height: 12),
                    _InfoRow(Icons.radar_rounded, 'UNIT: ${(alert['assigned_to'] ?? 'UNASSIGNED').replaceAll('_', ' ')}'),
                    const SizedBox(height: 8),
                    _InfoRow(Icons.trending_up_rounded, 'PRIORITY: ${alert['priority'] ?? 'MEDIUM'}'),
                    const SizedBox(height: 40),

                    if (lat != null && lng != null) ...[
                      const _DetailLabel('GEOSPATIAL BEACON'),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
                          if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 24),
                              const SizedBox(width: 16),
                              Text(
                                '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: AppColors.primary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],

                    if (attachments.isNotEmpty) ...[
                      const _DetailLabel('INTEL ATTACHMENTS'),
                      const SizedBox(height: 12),
                      ...attachments.map((url) => GestureDetector(
                        onTap: () async {
                          final uri = Uri.parse(url.toString());
                          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.file_copy_rounded, color: Colors.white24, size: 20),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'INTEL_FILE_${attachments.indexOf(url) + 1}.DAT',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white54,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const Icon(Icons.download_rounded, size: 18, color: Colors.white10),
                            ],
                          ),
                        ),
                      )),
                      const SizedBox(height: 40),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: alertId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('LOG ID COPIED', style: GoogleFonts.outfit(fontWeight: FontWeight.w900)),
                              backgroundColor: AppColors.surfaceContainerHigh,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: Text(
                          'COPY MISSION HASH',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 2.0,
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
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) {
    final color = status == 'RESOLVED' 
        ? AppColors.safe 
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
        style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.0),
      ),
    );
  }
}

class _DetailLabel extends StatelessWidget {
  final String label;
  const _DetailLabel(this.label);
  @override
  Widget build(BuildContext context) => Text(
        label,
        style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 2.0),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: Colors.white24),
          const SizedBox(width: 12),
          Expanded(child: Text(text.toUpperCase(), style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 0.5))),
        ],
      );
}
