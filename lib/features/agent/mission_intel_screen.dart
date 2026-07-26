// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';

class MissionIntelScreen extends ConsumerStatefulWidget {
  const MissionIntelScreen({required this.alertData, super.key});

  final Map<String, dynamic> alertData;

  @override
  ConsumerState<MissionIntelScreen> createState() => _MissionIntelScreenState();
}

class _MissionIntelScreenState extends ConsumerState<MissionIntelScreen> {
  late Map<String, dynamic> alertData;

  @override
  void initState() {
    super.initState();
    alertData = Map.from(widget.alertData);
  }

  Future<void> _updateStatus(String newStatus) async {
    final alertId = alertData['id'];
    if (alertId != null) {
      try {
        await SupabaseConfig.client.from('alerts').update({'status': newStatus}).eq('id', alertId);
        setState(() {
          alertData['status'] = newStatus;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to $newStatus')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = alertData['type'] as String? ?? 'INCIDENT';
    final severity = alertData['severity'] as String? ?? 'MEDIUM';
    final desc = alertData['description'] as String? ?? 'No details provided';
    final lat = (alertData['latitude'] as num?)?.toDouble();
    final lng = (alertData['longitude'] as num?)?.toDouble();
    final alertId = alertData['id'] as String?;
    
    final mediaUrls = (alertData['media_urls'] as List<dynamic>?)?.cast<String>() ?? [];
    
    final authState = ref.watch(authProvider);
    final isAgent = authState.role == UserRole.responder;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'TACTICAL MISSION INTEL',
        subtitle: 'INCIDENT DATA DOSSIER',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type.toUpperCase(),
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'SEVERITY: $severity',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.warning,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (lat != null && lng != null) ...[
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RainbowMap(
                    center: LatLng(lat, lng),
                    markers: [
                      Marker(
                        point: LatLng(lat, lng),
                        child: const Icon(Icons.location_on, color: AppColors.danger),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              desc,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.onBackground,
              ),
            ),
            const SizedBox(height: 24),
            if (mediaUrls.isNotEmpty) ...[
              Text(
                'EVIDENCE ACQUIRED',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: mediaUrls.length,
                  itemBuilder: (context, index) {
                    final url = mediaUrls[index];
                    final isImage = url.toLowerCase().endsWith('.png') ||
                        url.toLowerCase().endsWith('.jpg') ||
                        url.toLowerCase().endsWith('.jpeg');
                    return Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: isImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(
                                    Icons.broken_image,
                                    color: AppColors.textDim),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.movie,
                                  color: AppColors.primary, size: 40)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (isAgent) ...[
              Text(
                'TACTICAL STATUS',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateStatus('RESOLVED'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      child: const Text('RESOLVE', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateStatus('DISPATCHED'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                      ),
                      child: const Text('DISPATCH', style: TextStyle(color: Colors.black)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (alertId != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/dispatcher-chat?alertId=$alertId'),
                  icon: const Icon(Icons.chat, color: Colors.white),
                  label: Text(
                    'DISPATCHER CHAT',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
