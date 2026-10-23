// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:rainbow_app/core/config/map_tiles.dart';
import 'package:rainbow_app/core/config/routing.dart';
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
          // Absent column, absent value and empty string all mean the same
          // thing: nobody has said they know where this is. A database that
          // has not had 20261030000000 yet returns no such key, and the
          // honest reading of that is "not confirmed", not "confirmed".
          verified: (e['verified_at'] as String?)?.isNotEmpty ?? false,
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
    required this.verified,
  });
  final String id;
  final String name;
  final String type;
  final double lat;
  final double lng;
  final int capacity;

  /// Whether anybody has confirmed this position on the ground.
  ///
  /// `safe_zones.verified_at` is NULL for every row this project shipped,
  /// because none of the seeded coordinates was measured: `PLATEAU STATE HQ`
  /// sat at the centroid of Jos to four decimal places, and three of the seven
  /// were outside every surveyed ward of the LGA their own row named — the
  /// worst by 9.6km. Those three are deactivated now and never reach this
  /// screen. The rest are still guesses, and a person running from something
  /// is owed the difference between "this is where it is" and "this is where
  /// we think it is". T-94.
  final bool verified;
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

  /// The sentence `_calculateSafeRoute` speaks, kept so it can also be READ.
  ///
  /// It used to be spoken and nowhere else — see T-80. The threat warning was
  /// always written; the sentence saying whether the way is clear was not.
  String? _routeMessage;
  bool _directionsShown = false;

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

  /// Ask the routing service for ways from [start] to [end].
  ///
  /// Returns the paths AND whether they came from the router. A straight line
  /// between two points is not a route — it crosses buildings, rivers and the
  /// thing the person is running from — so the caller has to be able to tell
  /// the two apart. It could not before: the direct-line fallback was returned
  /// as though it were a road route, and the screen then announced "safe route
  /// calculated, the path is clear".
  ///
  /// A NON-200 USED TO RETURN `[]`, which the caller treated as "nothing to
  /// draw" and silently stopped. A refusing server is the likeliest failure of
  /// the two — the public OSRM demo answered **403** in the field — so the one
  /// that gave the person nothing at all was the one that happened. It falls
  /// back like the exception does now, and says which it was.
  /// See E2E_AUDIT_REPORT.md T-83.
  Future<({List<List<LatLng>> paths, bool fromRouter})> _fetchRoutes(
      LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
          '$routingBaseUrl/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson&alternatives=true');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        debugPrint(
          '[ROUTING_ERR] ${res.statusCode} from $routingBaseUrl'
          '${routingIsDemoServer ? " — this build is pointed at OSRM's public "
              "demonstration server, which rate-limits and refuses. Set "
              "ROUTING_URL." : ""}',
        );
        return (paths: [[start, end]], fromRouter: false);
      }
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
      if (paths.isEmpty) return (paths: [[start, end]], fromRouter: false);
      return (paths: paths, fromRouter: true);
    } catch (e) {
      debugPrint('[ROUTING_ERR] Failed to reach $routingBaseUrl: $e');
      return (paths: [[start, end]], fromRouter: false);
    }
  }

  Future<void> _calculateSafeRoute(LatLng userPos, _SafeZone zone, List<LatLng> threats) async {
    setState(() {
      _isCalculatingRoute = true;
      _currentRoute = null;
      _routePassesNearThreat = false;
    });

    final end = LatLng(zone.lat, zone.lng);
    final result = await _fetchRoutes(userPos, end);
    final paths = result.paths;

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
    // A STRAIGHT LINE IS NOT A ROUTE, AND MUST NOT BE ANNOUNCED AS ONE.
    //
    // When the routing service cannot be reached or refuses, the fallback is a
    // direct line from here to the shelter. It crosses buildings, rivers and
    // whatever the person is running from, and the threat check above has
    // tested that line rather than any road. Saying "safe route calculated,
    // the path is clear" over it is inventing an answer — the same move as the
    // shelters T-74 removed, one layer up. So the caveat is appended to the
    // sentence that is both spoken and written. T-83.
    // TWO SEPARATE CAVEATS, AND A ROUTE CAN NEED BOTH.
    //
    // `fromRouter` is about the PATH: a straight line is not a road route.
    // `verified` is about the DESTINATION: the shelter's own row may not know
    // where it is. They fail independently — a perfectly routed path to an
    // unconfirmed pin is the dangerous case, because the turn directions make
    // it look surveyed — so neither caveat may replace the other. T-94.
    final message = tmpl.replaceAll('{name}', zone.name)
        + (result.fromRouter
            ? ''
            : ' ${Translations.get('sz_route_is_a_direct_line', lang)}')
        + (zone.verified
            ? ''
            : ' ${Translations.get('sz_position_not_confirmed', lang)}');
    // Spoken AND kept. The screen shows it on request; a muted phone, an
    // unavailable TtsService or a deaf user must not be the difference between
    // knowing the way is clear and not knowing.
    if (mounted) {
      setState(() {
        _routeMessage = message;
        _directionsShown = false;
      });
    }
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
                    // THE MAP IS NOT A BUTTON.
                    //
                    // flutter_map registers a tap recognizer for panning and
                    // zooming, so an unwrapped map reaches the accessibility
                    // tree as an unlabelled button covering the screen. The
                    // control sweep had been failing on exactly this — one
                    // control on this route, named `(icon)`, that did nothing
                    // when pressed — and the identical fix had already been
                    // written on `live_tracking_screen.dart` and applied
                    // nowhere else. See E2E_AUDIT_REPORT.md T-78.
                    //
                    // `excludeSemantics: true` is what removes that node, and
                    // it takes the shelter markers' labels with it. The list
                    // below carries the same shelters, as ordinary buttons a
                    // screen reader can read and press.
                    Semantics(
                      container: true,
                      label: Translations.get('sz_semantics_map_label', lang),
                      excludeSemantics: true,
                      child: FlutterMap(
                      mapController: _mapCtrl,
                      options: MapOptions(
                        initialCenter: LatLng(pos.latitude, pos.longitude),
                        onTap: (_, __) => setState(() {
                          _selected = null;
                          _currentRoute = null;
                          _routePassesNearThreat = false;
                          _routeMessage = null;
                          _directionsShown = false;
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
                    ),

                    // THE SHELTERS, AS A LIST.
                    //
                    // Not decoration, and not a second way to do the same
                    // thing for the sake of it. The markers above are inside
                    // the excluded subtree, so their labels — correct as they
                    // are — cannot be read or pressed by a screen reader. This
                    // strip carries the same shelters as ordinary buttons with
                    // text, outside the exclusion, each doing exactly what its
                    // marker does: select the shelter and compute the route.
                    //
                    // It is also simply better for the screen's purpose. A
                    // frightened person looking for somewhere to go reads
                    // "NARAGUTA WARD COMMAND POST" faster than they find a
                    // small circle on a map.
                    if (zones.isNotEmpty)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Semantics(
                          container: true,
                          label: Translations.get(
                            'sz_semantics_shelter_list',
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
                                for (final zone in zones)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _ShelterChip(
                                      name: zone.name,
                                      icon: _iconForType(zone.type),
                                      chosen: _selected?.id == zone.id,
                                      onTap: () {
                                        setState(() => _selected = zone);
                                        unawaited(_calculateSafeRoute(
                                          LatLng(pos.latitude, pos.longitude),
                                          zone,
                                          threats,
                                        ),);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
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
                                      'sz_semantics_close_details',
                                      lang,
                                    ),
                                    excludeSemantics: true,
                                    onTap: () => setState(() {
                                      _selected = null;
                                      _currentRoute = null;
                                      _routePassesNearThreat = false;
                                      _routeMessage = null;
                                      _directionsShown = false;
                                    }),
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _selected = null;
                                        _currentRoute = null;
                                        _routePassesNearThreat = false;
                                        _routeMessage = null;
                                        _directionsShown = false;
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
                              // ON SCREEN AS WELL AS SPOKEN.
                              //
                              // The caveat is appended to the route message,
                              // which is spoken and shown on request. This
                              // panel is what somebody looks at while deciding
                              // WHICH shelter to run to, and that is the
                              // decision the warning belongs to — after the
                              // route is announced it is too late to pick a
                              // different one. Warning-coloured rather than
                              // dim: it is not a footnote. T-94.
                              if (!_selected!.verified) ...[
                                const SizedBox(height: 6),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.help_outline,
                                      size: 13,
                                      color: AppColors.warning,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        '${Translations.get('sz_not_confirmed_chip', lang)} — '
                                        '${Translations.get('sz_position_not_confirmed', lang)}',
                                        style: GoogleFonts.outfit(
                                          color: AppColors.warning,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
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
                              // THE WAY, IN WRITING.
                              //
                              // This control was labelled NAVIGATE TO ZONE and
                              // its entire body was `_mapCtrl.move(...)` — a
                              // camera pan. The name promised navigation and
                              // delivered a nudge, and because the screen had
                              // never had a shelter to select, the button had
                              // never once been rendered or pressed by anything.
                              //
                              // It now shows and hides the sentence the screen
                              // SPEAKS when it computes a route, which was
                              // audio-only: lost on a muted phone, with TTS
                              // unavailable, in a loud street, or to a deaf
                              // user. It still re-centres the map, and it
                              // re-speaks the sentence when revealing it, so a
                              // person already walking can ask for it again.
                              // T-80.
                              if (_routeMessage != null && _directionsShown) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.success.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    _routeMessage!,
                                    style: GoogleFonts.outfit(
                                      color: AppColors.onBackground,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      height: 1.5,
                                    ),
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
                                    final showing = !_directionsShown;
                                    setState(
                                      () => _directionsShown = showing,
                                    );
                                    final said = _routeMessage;
                                    if (showing && said != null) {
                                      unawaited(
                                        TtsService.instance.speak(said),
                                      );
                                    }
                                  },
                                  icon: Icon(
                                    _directionsShown
                                        ? Icons.visibility_off_rounded
                                        : Icons.navigation_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Translations.get(
                                      _directionsShown
                                          ? 'sz_hide_directions'
                                          : 'sz_show_directions',
                                      lang,
                                    ),
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

/// One shelter, as a button with its name on it.
///
/// A `Semantics(button: true)` wrapper is not needed and would be wrong: the
/// chip has TEXT, so its accessible name is that text, and `ElevatedButton`
/// already announces itself as a button. The whole point of this widget is
/// that it is an ordinary control rather than an icon in a map layer.
class _ShelterChip extends StatelessWidget {
  const _ShelterChip({
    required this.name,
    required this.icon,
    required this.chosen,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(
        name.toUpperCase(),
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: chosen
            ? AppColors.success
            : AppColors.surfaceContainer.withValues(alpha: 0.92),
        foregroundColor: chosen ? Colors.white : AppColors.onBackground,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: chosen ? AppColors.success : AppColors.outline,
          ),
        ),
      ),
    );
  }
}
