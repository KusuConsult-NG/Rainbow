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
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: Text(
          'My Incident History',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: user == null
          ? const Center(child: Text('Authentication required'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('alerts')
                  .where('reportedBy', isEqualTo: user.uid)
                  .orderBy('reportedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 64, color: AppColors.outline.withAlpha(100)),
                        const SizedBox(height: 16),
                        Text(
                          'No incidents reported yet.',
                          style: GoogleFonts.inter(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Stay safe. Your incident history will appear here.',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final alerts = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: alerts.length,
                  itemBuilder: (context, index) {
                    final doc = alerts[index];
                    final alert = doc.data() as Map<String, dynamic>? ?? {};
                    final type = alert['type'] ?? 'EMERGENCY';
                    final status = alert['status'] ?? 'UNKNOWN';
                    final desc = alert['description'] ?? 'No description';
                    final priority = alert['priority'] ?? 'MEDIUM';
                    final assignedTo = alert['assigned_to'] ?? '—';
                    final geoLga = alert['geo_lga'] as String?;
                    final geoWard = alert['geo_ward'] as String?;
                    final attachments = (alert['attachments'] as List<dynamic>?) ?? [];

                    String timeStr = '';
                    if (alert['reportedAt'] != null) {
                      try {
                        final ts = (alert['reportedAt'] as Timestamp).toDate();
                        timeStr = '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}';
                      } catch (_) {}
                    }

                    final statusColor = status == 'RESOLVED'
                        ? Colors.green
                        : status == 'DURESS'
                            ? AppColors.error
                            : Colors.orange;

                    return GestureDetector(
                      onTap: () => _showDetailSheet(context, alert, doc.id, attachments),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: statusColor.withAlpha(40), width: 1),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      type,
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withAlpha(20),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      status,
                                      style: GoogleFonts.inter(color: statusColor, fontWeight: FontWeight.w800, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 13, color: AppColors.outline),
                                  const SizedBox(width: 5),
                                  Text(timeStr, style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline, fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  // Priority badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: priority == 'CRITICAL'
                                          ? AppColors.error.withAlpha(15)
                                          : AppColors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      priority,
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                        color: priority == 'CRITICAL' ? AppColors.error : AppColors.outline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (geoLga != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined, size: 13, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$geoLga › $geoWard',
                                      style: GoogleFonts.inter(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                                    ),
                                    const Spacer(),
                                    Text(
                                      assignedTo.replaceAll('_', ' '),
                                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.outline, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ],
                              if (attachments.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.attach_file_rounded, size: 13, color: AppColors.secondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${attachments.length} attachment${attachments.length > 1 ? 's' : ''}',
                                      style: GoogleFonts.inter(fontSize: 10, color: AppColors.secondary, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text('Tap to view details', style: GoogleFonts.inter(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.primary),
                                ],
                              ),
                            ],
                          ),
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
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.outline.withAlpha(80), borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  children: [
                    // Header
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert['type'] ?? 'EMERGENCY',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 20),
                          ),
                        ),
                        _StatusChip(alert['status'] ?? 'UNKNOWN'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Report ID: ${alertId.substring(0, 8).toUpperCase()}',
                      style: GoogleFonts.inter(fontSize: 10, color: AppColors.outline, fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                    const SizedBox(height: 20),
                    const _DetailLabel('DESCRIPTION'),
                    const SizedBox(height: 6),
                    Text(
                      alert['description'] ?? 'No description provided.',
                      style: GoogleFonts.inter(fontSize: 14, height: 1.6, color: AppColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),

                    // Jurisdiction info
                    if (alert['geo_lga'] != null) ...[
                      const _DetailLabel('JURISDICTION'),
                      const SizedBox(height: 6),
                      _InfoRow(Icons.location_city_outlined, '${alert['geo_lga']} › ${alert['geo_ward']} › ${alert['geo_pu']}'),
                      const SizedBox(height: 16),
                    ],

                    const _DetailLabel('ESCALATION STATUS'),
                    const SizedBox(height: 6),
                    _InfoRow(Icons.account_tree_outlined, 'Assigned to: ${(alert['assigned_to'] ?? '—').replaceAll('_', ' ')}'),
                    const SizedBox(height: 4),
                    _InfoRow(Icons.flag_outlined, 'Priority: ${alert['priority'] ?? 'MEDIUM'}'),
                    const SizedBox(height: 20),

                    // Location actions
                    if (lat != null && lng != null) ...[
                      const _DetailLabel('INCIDENT LOCATION'),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () async {
                          final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
                          if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0).withAlpha(10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF1565C0).withAlpha(40)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.map_outlined, color: Color(0xFF1565C0), size: 20),
                              const SizedBox(width: 10),
                              Text(
                                'LAT: ${lat.toStringAsFixed(4)}  LON: ${lng.toStringAsFixed(4)}',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1565C0)),
                              ),
                              const Spacer(),
                              const Icon(Icons.open_in_new, size: 14, color: Color(0xFF1565C0)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Attachments
                    if (attachments.isNotEmpty) ...[
                      const _DetailLabel('ATTACHMENTS'),
                      const SizedBox(height: 10),
                      ...attachments.map((url) => GestureDetector(
                            onTap: () async {
                              final uri = Uri.parse(url.toString());
                              if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.image_outlined, color: AppColors.secondary, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      url.toString().split('/').last.split('?').first,
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.open_in_new, size: 14, color: AppColors.outline),
                                ],
                              ),
                            ),
                          )),
                      const SizedBox(height: 16),
                    ],

                    // Copy report ID
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: alertId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Report ID copied'), behavior: SnackBarBehavior.floating),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.copy_outlined, size: 16, color: AppColors.outline),
                            const SizedBox(width: 10),
                            Text('Copy Report ID', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.outline)),
                          ],
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
    final color = status == 'RESOLVED' ? Colors.green : status == 'DURESS' ? AppColors.error : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: GoogleFonts.inter(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}

class _DetailLabel extends StatelessWidget {
  final String label;
  const _DetailLabel(this.label);
  @override
  Widget build(BuildContext context) => Text(
        label,
        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.outline, letterSpacing: 2),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15, color: AppColors.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      );
}
