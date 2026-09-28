import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Where an incident happened, in the terms the command chain uses.
class Jurisdiction {
  const Jurisdiction({this.lga, this.ward, this.pu, required this.source});

  /// Nothing could be determined.
  static const Jurisdiction unresolved = Jurisdiction(source: 'UNRESOLVED');

  final String? lga;
  final String? ward;

  /// Always null from coordinates. See [JurisdictionResolver] for why.
  final String? pu;

  /// How this was arrived at: 'GPS', 'PROFILE', 'MANUAL' or 'UNRESOLVED'.
  /// Carried so a reader can tell a measured jurisdiction from an assumed one.
  final String source;

  bool get isResolved => lga != null;

  @override
  String toString() => 'Jurisdiction($lga / $ward / $pu via $source)';
}

/// Resolves a coordinate to the LGA and ward that own it.
///
/// WHY THIS EXISTS
///
/// An alert has to reach the tier responsible for the ground it happened on.
/// Nothing populated that: a citizen incident report attached no geography at
/// all unless the reporter opened the manual override, and the panic SOS
/// attached the REPORTER'S REGISTERED LGA and ward — where they live, not
/// where they are. Every tier filter then fell through its `IS NULL`
/// fail-open and showed every alert to everybody.
///
/// WHAT IT CAN AND CANNOT DO
///
/// * **LGA — a real boundary test.** `plateau_boundaries.json` holds the 17
///   actual ADM2 polygons. Before this, that file held 17 axis-aligned
///   RECTANGLES, so a point-in-polygon test returned a confident answer with
///   no relationship to where the boundary runs.
///
/// * **Ward — nearest centroid, not a boundary test.** The open ward data is
///   one point per ward, not a polygon. The nearest centroid *within the
///   resolved LGA* is a good approximation and a poor guarantee: it will be
///   wrong near a boundary between two wards of very different size. That
///   error is stated rather than hidden, and `source` records it.
///
/// * **Polling unit — never.** No open dataset gives polling-unit
///   coordinates. INEC's hierarchy lists every unit with a name and a code
///   and no position; the geocoded sets that exist are per-state research
///   data for election analysis and none covers Plateau. [pu] is therefore
///   always null here, and a PU can only come from the reporter choosing one.
///   Returning a guessed PU would be worse than returning none: it would send
///   a unit to the wrong village with full confidence.
class JurisdictionResolver {
  JurisdictionResolver._();

  static final JurisdictionResolver instance = JurisdictionResolver._();

  static const _boundariesAsset = 'assets/geo/plateau_boundaries.json';
  static const _wardsAsset = 'assets/geo/plateau_wards.json';

  /// lga name -> list of rings, each a list of [lng, lat] pairs.
  final Map<String, List<List<List<double>>>> _polygons = {};

  /// lga name -> [(ward, lat, lng)]
  final Map<String, List<_WardPoint>> _wards = {};

  bool _loaded = false;

  /// Test seam: install geometry without touching the asset bundle.
  // ignore: use_setters_to_change_properties
  void loadForTest({
    required Map<String, List<List<List<double>>>> polygons,
    required Map<String, List<List<dynamic>>> wards,
  }) {
    _polygons
      ..clear()
      ..addAll(polygons);
    _wards
      ..clear()
      ..addAll(wards.map((lga, list) => MapEntry(
            lga,
            list
                .map((w) => _WardPoint(
                      w[0] as String,
                      (w[1] as num).toDouble(),
                      (w[2] as num).toDouble(),
                    ))
                .toList(),
          )));
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;

    final boundaries =
        json.decode(await rootBundle.loadString(_boundariesAsset))
            as Map<String, dynamic>;
    for (final f in (boundaries['features'] as List<dynamic>)) {
      final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      final name = (props['lga'] as String).toUpperCase();
      final geom = f['geometry'] as Map<String, dynamic>;
      final rings = <List<List<double>>>[];

      if (geom['type'] == 'Polygon') {
        for (final ring in (geom['coordinates'] as List<dynamic>)) {
          rings.add(_ring(ring as List<dynamic>));
        }
      } else if (geom['type'] == 'MultiPolygon') {
        for (final poly in (geom['coordinates'] as List<dynamic>)) {
          for (final ring in (poly as List<dynamic>)) {
            rings.add(_ring(ring as List<dynamic>));
          }
        }
      }
      _polygons[name] = rings;
    }

    final wardDoc =
        json.decode(await rootBundle.loadString(_wardsAsset)) as Map<String, dynamic>;
    for (final w in (wardDoc['wards'] as List<dynamic>)) {
      final m = w as Map<String, dynamic>;
      final lga = (m['lga'] as String).toUpperCase();
      _wards.putIfAbsent(lga, () => []).add(
            _WardPoint(
              (m['ward'] as String).toUpperCase(),
              (m['lat'] as num).toDouble(),
              (m['lng'] as num).toDouble(),
            ),
          );
    }

    _loaded = true;
  }

  static List<List<double>> _ring(List<dynamic> raw) => raw
      .map<List<double>>((p) => [
            ((p as List<dynamic>)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
          ])
      .toList();

  /// The LGA and ward containing [lat], [lng], or [Jurisdiction.unresolved].
  ///
  /// Unresolved is a real answer, not a failure to be papered over: a
  /// coordinate outside Plateau, or no coordinate at all, must not be assigned
  /// to a jurisdiction. C-5 was this mistake one field over — a missing GPS
  /// fix rendered as a pin in central Jos.
  Jurisdiction resolve(double? lat, double? lng) {
    if (lat == null || lng == null || !_loaded) return Jurisdiction.unresolved;
    if (lat.isNaN || lng.isNaN) return Jurisdiction.unresolved;

    String? lga;
    for (final entry in _polygons.entries) {
      if (_inAnyRing(entry.value, lng, lat)) {
        lga = entry.key;
        break;
      }
    }
    if (lga == null) return Jurisdiction.unresolved;

    return Jurisdiction(lga: lga, ward: _nearestWard(lga, lat, lng), source: 'GPS');
  }

  /// Even-odd point-in-polygon. A point inside a hole of a multi-ring polygon
  /// toggles back out, which is the behaviour we want.
  bool _inAnyRing(List<List<List<double>>> rings, double x, double y) {
    var inside = false;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final xi = ring[i][0], yi = ring[i][1];
        final xj = ring[j][0], yj = ring[j][1];
        final intersects = ((yi > y) != (yj > y)) &&
            (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
        if (intersects) inside = !inside;
      }
    }
    return inside;
  }

  String? _nearestWard(String lga, double lat, double lng) {
    final candidates = _wards[lga];
    if (candidates == null || candidates.isEmpty) return null;

    String? best;
    var bestDist = double.infinity;
    for (final w in candidates) {
      // Equirectangular approximation. Over one LGA the error is far smaller
      // than the distance between ward centroids, and this runs on a phone
      // that may be mid-emergency.
      final dx = (w.lng - lng) * math.cos(lat * math.pi / 180);
      final dy = w.lat - lat;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = w.ward;
      }
    }
    return best;
  }
}

class _WardPoint {
  const _WardPoint(this.ward, this.lat, this.lng);
  final String ward;
  final double lat;
  final double lng;
}
