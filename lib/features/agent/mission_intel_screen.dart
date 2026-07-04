// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// Documentation for this public member.

class MissionIntelScreen extends ConsumerWidget {
  /// Documentation for this public member.
  const MissionIntelScreen({required this.alertDoc, super.key});

  /// Documentation for this public member.

  final DocumentSnapshot alertDoc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = alertDoc.data()! as Map<String, dynamic>;
    final reporterUid = alert['reportedByUid'] as String?;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'MISSION INTEL',
        subtitle: 'DETAILED OPERATIONAL VIEW',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IntelSection(
              title: 'INCIDENT PROFILE',
              icon: Icons.assignment_late_rounded,
              children: [
                _IntelField(
                  label: 'TYPE',
                  value: alert['type']?.toString() ?? 'UNKNOWN',
                ),
                _IntelField(
                  label: 'SUBTYPE',
                  value: alert['subType']?.toString() ?? 'N/A',
                ),
                _IntelField(
                  label: 'NARRATIVE',
                  value: alert['description']?.toString() ??
                      'No narrative provided',
                ),
                _IntelField(
                  label: 'STATUS',
                  value: alert['status']?.toString() ?? 'OPEN',
                ),
                _IntelField(
                  label: 'REPORTED AT',
                  value: _formatTime(alert['reportedAt'] ?? alert['createdAt']),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _IntelSection(
              title: 'LOCATION INTEL',
              icon: Icons.radar_rounded,
              children: [
                _IntelField(
                  label: 'LGA',
                  value: alert['geo_lga']?.toString() ?? 'PLATEAU',
                ),
                _IntelField(
                  label: 'WARD',
                  value: alert['geo_ward']?.toString() ?? 'HQ',
                ),
                _IntelField(
                  label: 'POLLING UNIT',
                  value: alert['geo_pu']?.toString() ?? 'UNIT',
                ),
                _IntelField(
                  label: 'COORDINATES',
                  value: '${alert['lat'] ?? 'N/A'}, ${alert['lng'] ?? 'N/A'}',
                ),
              ],
            ),
            const SizedBox(height: 24),
            _IntelSection(
              title: 'CITIZEN REPORTING DATA',
              icon: Icons.contact_emergency_rounded,
              children: [
                if (reporterUid != null)
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(reporterUid)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final user =
                          snapshot.data?.data() as Map<String, dynamic>?;
                      if (user == null) {
                        return const _IntelField(
                          label: 'CONTACT INFO',
                          value: 'Anonymous / Not Found',
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _IntelField(
                            label: 'CITIZEN NAME',
                            value: user['displayName']?.toString() ?? 'Unknown',
                          ),
                          _IntelField(
                            label: 'PHONE',
                            value: user['phone']?.toString() ??
                                'No phone provided',
                          ),
                          _IntelField(
                            label: 'ADDRESS',
                            value: user['address']?.toString() ??
                                'No address provided',
                          ),
                          _IntelField(
                            label: 'EMERGENCY CONTACT',
                            value: user['emergencyContactPhone']?.toString() ??
                                'None',
                          ),
                        ],
                      );
                    },
                  )
                else
                  const _IntelField(
                    label: 'CONTACT INFO',
                    value: 'Anonymous Alert',
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _IntelSection(
              title: 'ATTACHED MEDIA',
              icon: Icons.perm_media_rounded,
              children: [
                if (alert['mediaUrls'] != null &&
                    (alert['mediaUrls'] as List).isNotEmpty)
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: (alert['mediaUrls'] as List).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final url = (alert['mediaUrls'] as List)[i].toString();
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            url,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              width: 120,
                              height: 120,
                              color: AppColors.surfaceContainer,
                              child: const Icon(
                                Icons.broken_image_rounded,
                                color: AppColors.textDim,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  const _IntelField(
                    label: 'MEDIA',
                    value: 'No operational media attached',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'T-00:00';
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} HRS';
    }
    return 'RECENT';
  }
}

class _IntelSection extends StatelessWidget {
  const _IntelSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.outline, height: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _IntelField extends StatelessWidget {
  const _IntelField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: AppColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: AppColors.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
