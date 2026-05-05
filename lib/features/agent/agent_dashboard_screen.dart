import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../services/background_tracking_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/widgets/rainbow_map.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AgentDashboardScreen extends StatefulWidget {
  final String roleId;
  const AgentDashboardScreen({super.key, required this.roleId});

  @override
  State<AgentDashboardScreen> createState() => _AgentDashboardScreenState();
}

class _AgentDashboardScreenState extends State<AgentDashboardScreen> {
  String get _roleTitle {
    switch (widget.roleId) {
      case 'POLLING_UNIT': return 'Polling Unit Alerts';
      case 'WARD_OFFICER': return 'Ward Alerts';
      case 'LGA_OFFICER': return 'LGA Alerts';
      default: return 'Agent Dashboard';
    }
  }

  String get _assignedTier {
    switch (widget.roleId) {
      case 'POLLING_UNIT': return 'POLLING_UNIT';
      case 'WARD_OFFICER': return 'WARD';
      case 'LGA_OFFICER': return 'LGA';
      default: return 'POLLING_UNIT';
    }
  }

  bool get _isReadOnly => false;
  bool _showMap = false;

  void _showActionDialog(DocumentSnapshot alertDoc) {
    if (_isReadOnly) return;
    final alert = alertDoc.data() as Map<String, dynamic>? ?? {};

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Alert Actions',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What would you like to do with alert ${alertDoc.id}?'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (alert['reportedBy'] != null)
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.green),
                    onPressed: () async {
                      final url = Uri.parse('tel:${alert['reportedBy']}');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      }
                    },
                    tooltip: 'Call User',
                  ),
                if (alert['lat'] != null && alert['lng'] != null)
                  IconButton(
                    icon: const Icon(Icons.navigation, color: Colors.blue),
                    onPressed: () async {
                      final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${alert['lat']},${alert['lng']}');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    tooltip: 'Navigate',
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              final userId = FirebaseAuth.instance.currentUser?.uid ?? 'AGENT';
              await FirebaseFirestore.instance.collection('alerts').doc(alertDoc.id).update({
                'responder': userId,
                'responder_assigned_at': FieldValue.serverTimestamp(),
              });
              
              await BackgroundTrackingService().startTracking(alertDoc.id, userId);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Alert Accepted & Live Tracking Started!')),
                );
              }
            },
            child: Text('Accept', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              String nextTier = 'WARD';
              if (_assignedTier == 'WARD') nextTier = 'LGA';
              if (_assignedTier == 'LGA') nextTier = 'HQ';
              await FirebaseFirestore.instance.collection('alerts').doc(alertDoc.id).update({'assigned_to': nextTier});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Alert Escalated Successfully')),
                );
              }
            },
            child: Text('Escalate', style: GoogleFonts.inter(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('alerts').doc(alertDoc.id).update({'status': 'RESOLVED'});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Alert Resolved')),
                );
              }
            },
            child: Text('Resolve', style: GoogleFonts.inter(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          title: Text(
            _roleTitle,
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white),
          ),
          actions: [
            IconButton(
              icon: Icon(_showMap ? Icons.list_alt_rounded : Icons.map_rounded, color: Colors.white),
              onPressed: () => setState(() => _showMap = !_showMap),
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => context.go(AppRoutes.login),
            )
          ],
        ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('alerts')
            .where('status', whereIn: ['ACTIVE', 'DURESS'])
            .where('assigned_to', isEqualTo: _assignedTier)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No Active Alerts',
                style: GoogleFonts.inter(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          final alerts = snapshot.data!.docs;

          if (_showMap) {
            final markers = alerts.map((doc) {
              final alert = doc.data() as Map<String, dynamic>? ?? {};
              final lat = alert['lat'] as double? ?? 9.9167;
              final lng = alert['lng'] as double? ?? 8.8917;
              final isCritical = alert["priority"] == "CRITICAL" || alert["isCritical"] == true;
              return Marker(
                point: LatLng(lat, lng),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => _showActionDialog(doc),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCritical ? Colors.red : Colors.orange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 4)],
                    ),
                    child: const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
                  ),
                ),
              );
            }).toList();

            final center = alerts.isNotEmpty 
                ? LatLng(
                    (alerts.first.data() as Map<String, dynamic>)['lat'] ?? 9.9167, 
                    (alerts.first.data() as Map<String, dynamic>)['lng'] ?? 8.8917
                  ) 
                : const LatLng(9.9167, 8.8917);

            return RainbowMap(
              center: center,
              initialZoom: 13,
              markers: markers,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alertDoc = alerts[index];
              final alert = alertDoc.data() as Map<String, dynamic>? ?? {};
              final isCritical = alert["priority"] == "CRITICAL" || alert["isCritical"] == true;
              final type = alert["type"] ?? "EMERGENCY";
              
              String timeStr = "Active";
              if (alert['timestamp'] != null) {
                try {
                  final ts = (alert['timestamp'] as Timestamp).toDate();
                  timeStr = '${ts.hour}:${ts.minute.toString().padLeft(2, '0')}';
                } catch (_) {}
              } else if (alert['time'] != null) {
                timeStr = alert['time'].toString();
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  onTap: () => _showActionDialog(alertDoc),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCritical ? Colors.red.withAlpha(25) : Colors.orange.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                type,
                                style: GoogleFonts.inter(
                                  color: isCritical ? Colors.red : Colors.orange,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (alert['assigned_to'] != null)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withAlpha(25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'TIER: ${alert['assigned_to']}',
                                  style: GoogleFonts.inter(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            Text(
                              timeStr,
                              style: GoogleFonts.inter(
                                color: AppColors.outline,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (alert['responder'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline, size: 14, color: AppColors.secondary),
                                const SizedBox(width: 4),
                                Text(
                                  'RESPONDER: ${alert['responder'].toString().substring(0, 8)}...',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.secondary),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                alert["description"] ?? 'Location Pending...',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!_isReadOnly)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Tap to take action',
                                style: GoogleFonts.inter(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_ios, color: AppColors.primary, size: 12),
                            ],
                          ),
                        if (_isReadOnly)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Read Only View',
                                style: GoogleFonts.inter(
                                  color: AppColors.outline,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
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
    ));
  }
}
