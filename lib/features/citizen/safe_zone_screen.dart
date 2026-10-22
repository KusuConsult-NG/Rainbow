// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:rainbow_app/core/config/map_tiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/tts_service.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// The shelters a frightened person may be told to run to.
///
/// NOTHING IS INVENTED HERE, and the three things this used to do were each a
/// way of inventing one.
///
/// It returned three hardcoded zones from a bare `catch (_)` — "JOS SOUTH
/// COMMAND HQ", "BUKURU TACTICAL OUTPOST", "JOS NORTH POLICE DIVISION", with
/// round-numbered coordinates and invented capacities. Any failure reached it:
/// no network, a refused row, a missing table. The screen then drew a ROUTE to
/// the nearest one. A citizen fleeing an armed attack was being given turn-by-
/// turn directions to a position produced by a literal in a catch block, with
/// nothing on screen to say so.
///
/// It also THREW when the query succeeded and returned nothing, so a correctly
/// configured project with no shelters recorded yet showed the same three
/// invented ones. An empty list is a true answer and is now returned as one —
/// the screen already has an empty state that says no zones are published.
///
/// And a zone whose latitude or longitude was null became `0.0, 0.0`: a point
/// in the Gulf of Guinea, 700km off the coast, drawn on the map as a shelter.
/// Such a row is dropped instead.
///
/// This is C-5 again, one screen further out. A missing location must read as
/// missing. See E2E_AUDIT_REPORT.md C-5 and T-74.
final _safeZonesProvider = FutureProvider<List<_SafeZone>>((ref) async {
  final response = await SupabaseConfig.client
      .from('safe_zones')
      .select()
      .eq('is_active', true);

  return response
      .map((e) {
        final lat = (e['latitude'] as num?)?.toDouble();
        final lng = (e['longitude'] as num?)?.toDouble();
        // No position, no pin. A shelter nobody can be routed to is worse
        // than one the list does not mention.
        if (lat == null || lng == null) return null;
        return _SafeZone(
          id: e['id'].toString(),
          name: e['name'] as String? ?? 'Unknown',
          type: e['type'] as String? ?? 'SAFE_HAVEN',
          lat: lat,
          lng: lng,
          capacity: (e['capacity'] as num?)?.toInt() ?? 0,
        );
      })
      .whereType<_SafeZone>()
      .toList();
});

// Firestore-driven active threat alert geolocations
final _activeAlertsProvider = StreamProvider<List<LatLng>>((ref) {
  final cutoff = DateTime.now().subtract(const Duration(hours: 24));
  return SupabaseConfig.client
      .from('alerts')
      .stream(primaryKey: ['id'])
      .map((list) {
        return list
            .where((data) {
              // Only show active/escalated alerts from last 24 hours — BUG #13
              final status = (data['status'] as String? ?? '').toUpperCase();
              final isActive = status == 'ACTIVE' || status == 'ESCALATED';
              final createdRaw = data['created_at'] as String?;
              final isRecent = createdRaw == null || (DateTime.tryParse(createdRaw)?.isAfter(cutoff) ?? true);
              return isActive && isRecent;
            })
            .map((data) {
              final lat = (data['latitude'] ?? data['lat']) as double?;
              final lng = (data['longitude'] ?? data['lng']) as double?;
              if (lat != null && lng != null) return LatLng(lat, lng);
              return null;
            })
            .whereType<LatLng>()
            .toList();
      });
});

class _SafeZone {
  const _SafeZone({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.capacity,
  });
  final String id;
  final String name;
  final String type;
  final double lat;
  final double lng;
  final int capacity;
}

/// Documentation for this public member.

class SafeZoneScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const SafeZoneScreen({super.key});

  @override
  ConsumerState<SafeZoneScreen> createState() => _SafeZoneScreenState();
}

class _SafeZoneScreenState extends ConsumerState<SafeZoneScreen> {
  final MapController _mapCtrl = MapController();
  _SafeZone? _selected;
  List<LatLng>? _currentRoute;
  bool _routePassesNearThreat = false;
  bool _isCalculatingRoute = false;

  double _calculateRouteThreatScore(List<LatLng> path, List<LatLng> threats) {
    // `0.0`, not `0`: this accumulates a double threat score. `dart fix`
    // rewrote `double score = 0.0` to `var score = 0` and silently changed the
    // type, which the analyzer then caught as two hard errors.
    var score = 0.0;
    for (final point in path) {
      for (final threat in threats) {
        final dLat = point.latitude - threat.latitude;
        final dLng = point.longitude - threat.longitude;
        final distSq = dLat * dLat + dLng * dLng;
        const threshold = 0.000025; // ~500m radius
        if (distSq < threshold) {
          score += (threshold - distSq) * 100000;
        }
      }
    }
    return score;
  }

  Future<List<List<LatLng>>> _fetchRoutes(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson&alternatives=true');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>? ?? [];
      final paths = <List<LatLng>>[];
      for (final r in routes.cast<Map<String, dynamic>>()) {
        final geometry = r['geometry'] as Map<String, dynamic>? ?? const {};
        final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
        final path = coordinates.map((c) {
          final coords = c as List<dynamic>;
          // GeoJSON is [lng, lat]; values arrive as num (int or double).
          return LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          );
        }).toList();
        paths.add(path);
      }
      return paths;
    } catch (e) {
      debugPrint('[ROUTING_ERR] Failed to fetch OSRM route: $e');
      return [[start, end]]; // Direct path fallback
    }
  }

  Future<void> _calculateSafeRoute(LatLng userPos, _SafeZone zone, List<LatLng> threats) async {
    setState(() {
      _isCalculatingRoute = true;
      _currentRoute = null;
      _routePassesNearThreat = false;
    });

    final end = LatLng(zone.lat, zone.lng);
    final paths = await _fetchRoutes(userPos, end);

    if (paths.isEmpty) {
      setState(() => _isCalculatingRoute = false);
      return;
    }

    List<LatLng>? bestPath;
    var lowestScore = double.infinity;

    for (final p in paths) {
      final score = _calculateRouteThreatScore(p, threats);
      if (score < lowestScore) {
        lowestScore = score;
        bestPath = p;
      }
    }

    var warning = false;
    if (bestPath != null) {
      for (final point in bestPath) {
        for (final threat in threats) {
          final dLat = point.latitude - threat.latitude;
          final dLng = point.longitude - threat.longitude;
          final distSq = dLat * dLat + dLng * dLng;
          if (distSq < 0.00000625) {
            warning = true;
            break;
          }
        }
      }
    }

    setState(() {
      _currentRoute = bestPath;
      _routePassesNearThreat = warning;
      _isCalculatingRoute = false;
    });

    final lang = ref.read(languageProvider);
    final tmpl = warning
        ? Translations.get('sz_route_calculated_warning', lang)
        : Translations.get('sz_route_calculated_clear', lang);
    final message = tmpl.replaceAll('{name}', zone.name);
    unawaited(TtsService.instance.speak(message));
  }

  IconData _iconForType(String type) {
    switch (type.toUpperCase()) {
      case 'HOSPITAL':
      case 'MEDICAL':
        return Icons.local_hospital_rounded;
      case 'POLICE':
        return Icons.local_police_rounded;
      case 'MILITARY':
      case 'COMMAND_HQ':
      case 'COMMAND_POST':
        return Icons.security_rounded;
      case 'OUTPOST':
        return Icons.radar_rounded;
      case 'SHELTER':
      case 'SAFE_POINT':
      case 'SAFE_HAVEN':
        return Icons.shield_rounded;
      default:
        return Icons.shield_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final locAsync = ref.watch(userLocationStreamProvider);
    final zonesAsync = ref.watch(_safeZonesProvider);
    final threats = ref.watch(_activeAlertsProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: Translations.get('sz_safe_zone_routing', lang),
        subtitle: Translations.get('sz_evacuation_zones', lang),
        showBack: true,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.success,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    Translations.get('sz_navigate_shield_desc', lang),
                    style: GoogleFonts.outfit(
                      color: AppColors.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Zone count badge
          zonesAsync.when(
            data: (zones) => Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              color: AppColors.surfaceContainer,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${zones.length} ${Translations.get('sz_active_zones_online', lang)}',
                    style: GoogleFonts.outfit(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          Expanded(
            child: locAsync.when(
              data: (pos) {
                // pos is null when GPS permission is denied
                if (pos == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_off_rounded,
                            color: AppColors.warning,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            Translations.get('sz_gps_denied', lang),
                            style: GoogleFonts.outfit(
                              color: AppColors.textDim,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final zones = zonesAsync.valueOrNull ?? [];
                final markers = <Marker>[
                  // User position
                  Marker(
                    point: LatLng(pos.latitude, pos.longitude),
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_pin_circle_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  // Dynamic safe zone markers from Firestore
                  ...zones.map(
                    (zone) => Marker(
                      point: LatLng(zone.lat, zone.lng),
                      width: 44,
                      height: 44,
                      // The control that picks which shelter a frightened
                      // person is routed to, and it had no accessible name:
                      // the interaction sweep could only report it as
                      // `(icon)`. The name carries the shelter's own name,
                      // because there is one of these per shelter and
                      // "shelter" alone does not tell them apart.
                      child: Semantics(
                        button: true,
                        label: Translations.get('sz_semantics_route_to', lang)
                            .replaceAll('{name}', zone.name),
                        excludeSemantics: true,
                        onTap: () {
                          setState(() => _selected = zone);
                          unawaited(_calculateSafeRoute(LatLng(pos.latitude, pos.longitude), zone, threats));
                        },
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selected = zone);
                            unawaited(_calculateSafeRoute(LatLng(pos.latitude, pos.longitude), zone, threats));
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              _iconForType(zone.type),
                              color: AppColors.success,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ];

                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapCtrl,
                      options: MapOptions(
                        initialCenter: LatLng(pos.latitude, pos.longitude),
                        onTap: (_, __) => setState(() {
                          _selected = null;
                          _currentRoute = null;
                          _routePassesNearThreat = false;
                        }),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              mapTileUrl,
                                                  ),
                        if (_currentRoute != null)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _currentRoute!,
                                strokeWidth: 4,
                                color: _routePassesNearThreat
                                    ? AppColors.warning
                                    : AppColors.success,
                              ),
                            ],
                          ),
                        MarkerLayer(markers: markers),
                      ],
                    ),

                    // Empty state overlay
                    if (zones.isEmpty)
                      Positioned(
                        bottom: 24,
                        left: 24,
                        right: 24,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Text(
                            Translations.get('sz_no_active_zones', lang),
                            style: GoogleFonts.outfit(
                              color: AppColors.textDim,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),

                    // Selected zone detail card
                    if (_selected != null)
                      Positioned(
                        bottom: 24,
                        left: 24,
                        right: 24,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _iconForType(_selected!.type),
                                    color: AppColors.success,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _selected!.name.toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        color: AppColors.onBackground,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        letterSpacing: 0.5,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Semantics(
                                    button: true,
                                    label: Translations.get(
                                        'sz_semantics_close_details', lang),
                                    excludeSemantics: true,
                                    onTap: () => setState(() {
                                      _selected = null;
                                      _currentRoute = null;
                                      _routePassesNearThreat = false;
                                    }),
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _selected = null;
                                        _currentRoute = null;
                                        _routePassesNearThreat = false;
                                      }),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: AppColors.textDim,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selected!.type.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  color: AppColors.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                              if (_selected!.capacity > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${Translations.get('sz_capacity', lang)}: ${_selected!.capacity} ${Translations.get('sz_persons', lang)}',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.textDim,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (_isCalculatingRoute) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      Translations.get('sz_computing_path', lang),
                                      style: GoogleFonts.outfit(
                                        color: AppColors.success,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else if (_routePassesNearThreat) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          Translations.get('sz_threat_en_route', lang),
                                          style: GoogleFonts.outfit(
                                            color: AppColors.warning,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _mapCtrl.move(
                                      LatLng(
                                        _selected!.lat,
                                        _selected!.lng,
                                      ),
                                      16,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.navigation_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Translations.get('sz_navigate_to_zone', lang),
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  Translations.get('sz_unable_acquire_gps', lang),
                  style: GoogleFonts.outfit(color: AppColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
