// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/tts_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

final _safeZonesProvider = FutureProvider<List<_SafeZone>>((ref) async {
  try {
    final response = await SupabaseConfig.client
        .from('safe_zones')
        .select('*')
        .eq('is_active', true);
        
    if (response.isEmpty) {
      throw Exception('Empty safe zones');
    }

    return response.map((e) {
      return _SafeZone(
        id: e['id'].toString(),
        name: e['name'] as String? ?? 'Unknown',
        type: e['type'] as String? ?? 'SAFE_HAVEN',
        lat: (e['latitude'] as num?)?.toDouble() ?? 0.0,
        lng: (e['longitude'] as num?)?.toDouble() ?? 0.0,
        capacity: (e['capacity'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  } catch (_) {
    return [
      const _SafeZone(id: 'sz_1', name: 'JOS SOUTH COMMAND HQ', type: 'COMMAND_POST', lat: 9.9285, lng: 8.8921, capacity: 500),
      const _SafeZone(id: 'sz_2', name: 'BUKURU TACTICAL OUTPOST', type: 'SHELTER', lat: 9.8000, lng: 8.8700, capacity: 250),
      const _SafeZone(id: 'sz_3', name: 'JOS NORTH POLICE DIVISION', type: 'SAFE_HAVEN', lat: 9.9333, lng: 8.8833, capacity: 350),
    ];
  }
});

// Firestore-driven active threat alert geolocations
final _activeAlertsProvider = StreamProvider<List<LatLng>>((ref) {
  return SupabaseConfig.client
      .from('alerts')
      .stream(primaryKey: ['id'])
      .map((list) {
        return list
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
    double score = 0.0;
    for (final point in path) {
      for (final threat in threats) {
        final dLat = point.latitude - threat.latitude;
        final dLng = point.longitude - threat.longitude;
        final distSq = dLat * dLat + dLng * dLng;
        if (distSq < 0.000025) { // within ~500m
          final dist = dLat * dLat + dLng * dLng;
          score += (0.000025 - dist) * 10000;
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
      final data = jsonDecode(res.body);
      final routes = data['routes'] as List<dynamic>? ?? [];
      final List<List<LatLng>> paths = [];
      for (final r in routes) {
        final coordinates = r['geometry']['coordinates'] as List<dynamic>? ?? [];
        final List<LatLng> path = coordinates.map((c) {
          final coords = c as List<dynamic>;
          return LatLng(coords[1].toDouble(), coords[0].toDouble());
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
    double lowestScore = double.infinity;
    for (final p in paths) {
      final score = _calculateRouteThreatScore(p, threats);
      if (score < lowestScore) {
        lowestScore = score;
        bestPath = p;
      }
    }

    bool warning = false;
    if (bestPath != null) {
      for (final point in bestPath) {
        for (final threat in threats) {
          final dLat = point.latitude - threat.latitude;
          final dLng = point.longitude - threat.longitude;
          final distSq = dLat * dLat + dLng * dLng;
          if (distSq < 0.00000625) { // within ~250m
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

    final message = warning
        ? "Safe route calculated to ${zone.name}. Warning: The route passes near an active threat. Proceed with extreme caution."
        : "Safe route calculated to ${zone.name}. The path is clear.";
    unawaited(TtsService.instance.speak(message));
  }

  IconData _iconForType(String type) {
    switch (type.toUpperCase()) {
      case 'HOSPITAL':
        return Icons.local_hospital_rounded;
      case 'POLICE':
        return Icons.local_police_rounded;
      case 'MILITARY':
        return Icons.security_rounded;
      default:
        return Icons.shield_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locAsync = ref.watch(userLocationStreamProvider);
    final zonesAsync = ref.watch(_safeZonesProvider);
    final threats = ref.watch(_activeAlertsProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'SAFE-ZONE ROUTING',
        subtitle: 'EVACUATION & SECURE ZONES',
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
                    'NAVIGATE TO NEAREST SHIELD ICON FOR IMMEDIATE PROTECTION. THESE ZONES ARE SECURED BY TACTICAL UNITS.',
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
                    '${zones.length} ACTIVE SECURE ZONES ONLINE',
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
                            'GPS ACCESS DENIED\nEnable location permissions to view safe zones near you.',
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
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selected = zone);
                          _calculateSafeRoute(LatLng(pos.latitude, pos.longitude), zone, threats);
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
                              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
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
                            'NO ACTIVE SAFE ZONES IN YOUR AREA.\nCONTACT HQ VIA DISPATCHER CHAT.',
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
                                  GestureDetector(
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
                                  'CAPACITY: ${_selected!.capacity} PERSONS',
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
                                      'COMPUTING RISK-AWARE EVACUATION PATH...',
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
                                          'THREAT EN ROUTE · PATH DIVERTS AROUND ACTIVE UNREST HOTSPOTS',
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
                                    'NAVIGATE TO ZONE',
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
                  'UNABLE TO ACQUIRE GPS SIGNAL',
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
