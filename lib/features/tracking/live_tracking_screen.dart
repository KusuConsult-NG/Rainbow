import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:rainbow_app/core/config/map_tiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

final respondersStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  // Stream telemetry, then enrich with profile names
  return SupabaseConfig.client.from('telemetry').stream(primaryKey: ['user_id']).asyncMap(
    (telemetryList) async {
      if (telemetryList.isEmpty) return <Map<String, dynamic>>[];
      final userIds = telemetryList.map((t) => t['user_id'] as String).toList();
      try {
        final profiles = await SupabaseConfig.client
            .from('profiles')
            .select('id, full_name, role')
            .inFilter('id', userIds);
        final nameMap = <String, String>{};
        for (final p in (profiles as List).cast<Map<String, dynamic>>()) {
          nameMap[p['id'] as String] = p['full_name'] as String? ?? 'Officer';
        }
        return telemetryList.map((t) => {
          ...t,
          'officer_name': nameMap[t['user_id'] as String] ?? 'Unknown Officer',
        },).toList();
      } catch (_) {
        return telemetryList;
      }
    },
  );
});

final alertsMapStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return SupabaseConfig.client.from('alerts').stream(primaryKey: ['id']).map((alerts) {
    return alerts.where((alert) => alert['status'] != 'RESOLVED').toList();
  });
});

class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  LatLng? _currentPos;
  bool _locationDenied = false;
  StreamSubscription<Position?>? _sub;

  @override
  void initState() {
    super.initState();
    unawaited(_startPosStream());
  }

  Future<void> _startPosStream() async {
    try {
      _sub = LocationService().streamLocation().listen((pos) {
        if (!mounted) return;
        if (pos == null) {
          setState(() => _locationDenied = true);
          return;
        }
        setState(() {
          _locationDenied = false;
          _currentPos = LatLng(pos.latitude, pos.longitude);
        });
      });
    } catch (e) {
      debugPrint('[TRACKING_ERR] Location stream failed: $e');
      if (mounted) setState(() => _locationDenied = true);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Color _getMarkerColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'PATROLLING':
        return AppColors.success;
      case 'DISPATCHED':
        return AppColors.warning;
      case 'EMERGENCY':
      case 'SOS':
        return AppColors.danger;
      default:
        return AppColors.primary;
    }
  }

  void _showResponderDetails(Map<String, dynamic> telemetry) {
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESPONDER DETAILS',
              style: GoogleFonts.outfit(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              telemetry['officer_name'] as String? ?? 'Unknown Officer',
              style: GoogleFonts.inter(color: AppColors.onBackground, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${(telemetry['user_id'] as String? ?? '').substring(0, 8)}...',
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${telemetry['status'] ?? 'ONLINE'}',
              style: GoogleFonts.inter(color: _getMarkerColor(telemetry['status'] as String?)),
            ),
            const SizedBox(height: 8),
            Text(
              'Battery: ${telemetry['battery'] != null ? "${telemetry['battery']}%" : "Unknown"}',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Last Updated: ${telemetry['updated_at'] ?? 'Unknown'}',
              style: GoogleFonts.inter(color: AppColors.textDim),
            ),
          ],
        ),
      ),
    ),);
  }

  @override
  Widget build(BuildContext context) {
    final respondersAsync = ref.watch(respondersStreamProvider);
    final alertsAsync = ref.watch(alertsMapStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'TACTICAL MAP',
        subtitle: 'LIVE COMMAND FEED',
      ),
      body: _locationDenied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_off_rounded, color: AppColors.danger, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'LOCATION ACCESS DENIED',
                      style: GoogleFonts.outfit(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enable location in device Settings to use the tactical map.',
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : _currentPos == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(
              children: [
                // THE MAP IS NOT A BUTTON.
                //
                // flutter_map registers a tap recognizer for panning and
                // zooming, so the whole map surface reached the accessibility
                // tree as an unlabelled button covering the screen — one a
                // screen reader announced as "button" and that did nothing
                // when activated. The mobile control sweep found exactly that.
                // Named as what it is, with its gesture layer kept out of the
                // tree; the legend below stays readable.
                Semantics(
                  container: true,
                  label: 'Tactical map of incidents and responders',
                  excludeSemantics: true,
                  child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _currentPos!,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: mapTileUrl,
                                            userAgentPackageName: 'com.rainbow.app',
                    ),
                    MarkerLayer(
                      markers: [
                        // Own marker
                        Marker(
                          point: _currentPos!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: AppColors.primary,
                            size: 32,
                          ),
                        ),
                        // Alerts
                        if (alertsAsync.hasValue)
                          ...alertsAsync.value!.map((a) {
                            final lat = (a['latitude'] ?? a['lat']) as double?;
                            final lng = (a['longitude'] ?? a['lng']) as double?;
                            if (lat == null || lng == null) return null;
                            return Marker(
                              point: LatLng(lat, lng),
                              child: const Icon(
                                Icons.warning_rounded,
                                color: AppColors.warning,
                                size: 24,
                              ),
                            );
                          }).whereType<Marker>(),
                        // Responders
                        if (respondersAsync.hasValue)
                          ...respondersAsync.value!.map((r) {
                            final lat = (r['latitude'] ?? r['lat']) as double?;
                            final lng = (r['longitude'] ?? r['lng']) as double?;
                            if (lat == null || lng == null) return null;
                            // Don't duplicate own pos if they have telemetry row
                            if (SupabaseConfig.client.auth.currentUser?.id == r['user_id']) return null;
                            
                            return Marker(
                              point: LatLng(lat, lng),
                              child: GestureDetector(
                                onTap: () => _showResponderDetails(r),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _getMarkerColor(r['status'] as String?).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _getMarkerColor(r['status'] as String?)),
                                  ),
                                  child: Icon(
                                    Icons.person_pin_circle_rounded,
                                    color: _getMarkerColor(r['status'] as String?),
                                    size: 16,
                                  ),
                                ),
                              ),
                            );
                          }).whereType<Marker>(),
                      ],
                    ),
                  ],
                  ),
                ),
                // Legend
                Positioned(
                  bottom: 24,
                  left: 24,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LegendItem(color: AppColors.success, label: 'PATROLLING'),
                        SizedBox(height: 4),
                        _LegendItem(color: AppColors.warning, label: 'DISPATCHED / ALERT'),
                        SizedBox(height: 4),
                        _LegendItem(color: AppColors.danger, label: 'EMERGENCY'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.outfit(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
