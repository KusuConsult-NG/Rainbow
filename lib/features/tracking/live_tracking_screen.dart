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
import 'package:rainbow_app/shared/localization/translations.dart';
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
          'officer_name': nameMap[t['user_id'] as String] ?? Translations.get('trk_unknown_officer', ref.read(languageProvider)),
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
    final lang = ref.read(languageProvider);
    final statusVal = telemetry['status'] as String? ?? 'ONLINE';
    final batteryVal = telemetry['battery'] != null ? '${telemetry['battery']}%' : Translations.get('trk_unknown', lang);
    final updatedVal = telemetry['updated_at'] as String? ?? Translations.get('trk_unknown', lang);
    final officerName = telemetry['officer_name'] as String? ?? Translations.get('trk_unknown_officer', lang);

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
              Translations.get('trk_responder_details', lang),
              style: GoogleFonts.outfit(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              officerName,
              style: GoogleFonts.inter(color: AppColors.onBackground, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '${Translations.get('trk_id', lang)}: ${(telemetry['user_id'] as String? ?? '').substring(0, 8)}...',
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '${Translations.get('trk_status', lang)}: $statusVal',
              style: GoogleFonts.inter(color: _getMarkerColor(telemetry['status'] as String?)),
            ),
            const SizedBox(height: 8),
            Text(
              '${Translations.get('trk_battery', lang)}: $batteryVal',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '${Translations.get('trk_last_updated', lang)}: $updatedVal',
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
    // Read once, unwrapped once. The list below iterated
    // `respondersAsync.value!` a dozen lines below its `hasValue` guard, and
    // `check_async_reads_cannot_rethrow.py` wants the guard beside the use —
    // `AsyncValue.value` throws before the `!` is reached, so the guard is the
    // only thing making it safe. A local removes the bang rather than moving
    // the guard closer to it.
    final onDuty = respondersAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    final alertsAsync = ref.watch(alertsMapStreamProvider);
    final lang = ref.watch(languageProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: Translations.get('trk_tactical_map', lang),
        subtitle: Translations.get('trk_live_command_feed', lang),
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
                      Translations.get('trk_location_denied', lang),
                      style: GoogleFonts.outfit(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Translations.get('trk_enable_location_settings', lang),
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
                  label: Translations.get('trk_semantics_map_label', lang),
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
                            
                            final who = (r['full_name'] ?? r['badge_number']
                                ?? Translations.get(
                                    'trk_semantics_a_responder', lang))
                                .toString();
                            final how = (r['status'] as String? ?? 'unknown')
                                .toUpperCase();
                            return Marker(
                              point: LatLng(lat, lng),
                              // SEMANTICS-UNREACHABLE: the label below is
                              // correct and a screen reader cannot reach it.
                              //
                              // The Semantics above excludes the map surface
                              // because flutter_map's pan-and-zoom recognizer
                              // otherwise presents the whole screen as one
                              // unlabelled button — a defect the control sweep
                              // already found once. Excluding a subtree
                              // excludes its markers with it, so the two
                              // requirements conflict and no label here can
                              // win.
                              //
                              // REACHABLE EQUIVALENT: the responder list at
                              // the top of this Stack — one ordinary button
                              // per responder, outside the exclusion, each
                              // opening these same details. It landed in T-88:
                              // one ordinary button per responder, outside the
                              // exclusion, each opening the same details this
                              // marker opens. The marker stays unreachable —
                              // that is what the token above acknowledges —
                              // but the FUNCTION is no longer only available
                              // through it.
                              //
                              // Recorded in E2E_AUDIT_REPORT.md T-76 and T-88.
                              // The label here is still correct and still
                              // written, so it is right if the exclusion ever
                              // becomes unnecessary.
                              child: Semantics(
                                button: true,
                                label: Translations.get(
                                        'trk_semantics_open_responder', lang)
                                    .replaceAll('{who}', who)
                                    .replaceAll('{status}', how),
                                excludeSemantics: true,
                                onTap: () => _showResponderDetails(r),
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
                              ),
                            );
                          }).whereType<Marker>(),
                      ],
                    ),
                  ],
                  ),
                ),
                // THE RESPONDERS, AS A LIST.
                //
                // The markers above carry correct labels and a screen reader
                // cannot reach any of them: the map surface is inside a
                // `Semantics(excludeSemantics: true)` because flutter_map's
                // pan-and-zoom recognizer otherwise presents the whole screen
                // as one unlabelled button, and excluding a subtree excludes
                // its markers with it. The two requirements conflict and no
                // label on a pin can win. T-76 recorded that and said the
                // resolution was a LIST. This is it.
                //
                // Same shape as the shelter strip on safe_zone_screen.dart:
                // ordinary buttons with text, outside the exclusion, each
                // doing exactly what its marker does — open that responder's
                // details. It is also better for the screen's purpose. A
                // dispatcher looking for one officer reads a name faster than
                // they find a coloured circle among several. T-88.
                if (onDuty.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Semantics(
                      container: true,
                      label: Translations.get(
                        'trk_semantics_responder_list',
                        lang,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            for (final r in onDuty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ResponderChip(
                                  name: (r['full_name'] ??
                                          r['badge_number'] ??
                                          Translations.get(
                                            'trk_semantics_a_responder',
                                            lang,
                                          ))
                                      .toString(),
                                  status: (r['status'] as String? ??
                                          Translations.get(
                                            'trk_status_unknown',
                                            lang,
                                          ))
                                      .toUpperCase(),
                                  colour:
                                      _getMarkerColor(r['status'] as String?),
                                  onTap: () => _showResponderDetails(r),
                                ),
                              ),
                          ],
                        ),
                      ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _LegendItem(color: AppColors.success, label: 'PATROLLING'),
                        const SizedBox(height: 4),
                        _LegendItem(color: AppColors.warning, label: Translations.get('trk_dispatched_alert', lang)),
                        const SizedBox(height: 4),
                        const _LegendItem(color: AppColors.danger, label: 'EMERGENCY'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One responder, as a button with their name and status on it.
///
/// No `Semantics` wrapper and none needed: the chip has TEXT, so its accessible
/// name is that text, and `ElevatedButton` announces itself as a button. That
/// is the whole point of this widget — the markers on the map are icons inside
/// an excluded subtree, and this is an ordinary control outside it. T-88.
class _ResponderChip extends StatelessWidget {
  const _ResponderChip({
    required this.name,
    required this.status,
    required this.colour,
    required this.onTap,
  });

  final String name;
  final String status;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surfaceContainer.withValues(alpha: 0.92),
        foregroundColor: AppColors.onBackground,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.outline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The status colour is also stated in words beside it. A colour on
          // its own is not information somebody with low vision receives, and
          // the legend that explains the colours is at the other end of the
          // screen.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '${name.toUpperCase()} · $status',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1,
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
