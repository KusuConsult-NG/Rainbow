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

  /// How this was arrived at: 'GPS', 'GPS_WARD_REGISTER', 'PROFILE', 'MANUAL'
  /// or 'UNRESOLVED'. Carried so a reader can tell a measured jurisdiction
  /// from an assumed one — and, for 'GPS_WARD_REGISTER', one the two
  /// geography datasets had to be reconciled for. See [JurisdictionResolver].
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
/// * **A seam between two polygons — the ward register answers.** The ADM2
///   polygons and the ward centroids are independently published datasets and
///   they do not quite agree. 1.5% of inhabited Plateau falls inside NO LGA
///   polygon while sitting between two or more of them: a hairline gap where
///   neighbouring boundaries fail to meet. Two real ward centroids land in
///   one, KANAM/DUGUB and KANKE/NEMEL. An incident there used to resolve to
///   nothing at all — no LGA, no ward, no tier — which is the failure this
///   class exists to end, arriving by a different route.
///
///   The ward register is authoritative for which LGA a ward belongs to; the
///   polygons are authoritative for which LGA a point is in. So when no
///   polygon owns the point and the point is inside the state's extent, the
///   nearest ward centroid's REGISTERED lga is used, and the jurisdiction's
///   `source` says 'GPS_WARD_REGISTER' so it is never mistaken for a boundary
///   hit. Outside the extent nothing is returned, because the nearest Plateau
///   ward to a point in Kaduna is not an answer.
///
///   The extent is a rectangle, so it holds some ground that is not Plateau:
///   the corners, and a fringe along the border. A report from just outside
///   the state therefore now resolves to the nearest Plateau LGA where it used
///   to resolve to nothing. That is deliberate. This is Plateau's emergency
///   service: sending a near-border report to the nearest Plateau command is a
///   better failure than sending it nowhere, and 'GPS_WARD_REGISTER' tells HQ
///   the boundary did not actually place it. Measured over sampled ground
///   within 8km of a ward centroid, 1.5% is interior seam and 3.9% is that
///   fringe.
///
/// * **No radius bound on the ward.** An earlier design bounded the ward by
///   its centroid's radius — half the distance to its nearest neighbour — and
///   returned no ward beyond it. That was wrong. Wards TILE an LGA, so the
///   nearest centroid IS the Voronoi assignment and a ward's real extent runs
///   past that radius in every direction but one. Measured over 5,100 sampled
///   points inside their own LGA, the bound would have blanked the ward for
///   57.4% of them, discarding correct answers. The radius is for DRAWING an
///   area; it was never a membership test.
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

  /// The state's extent, DERIVED from the loaded polygons rather than written
  /// down. It decides whether a point that no polygon owns is in a seam
  /// between LGAs or simply somewhere else, and a literal here would be one
  /// more number nobody measured.
  double _minLat = double.infinity;
  double _maxLat = double.negativeInfinity;
  double _minLng = double.infinity;
  double _maxLng = double.negativeInfinity;

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
    _computeExtent();
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

    _computeExtent();
    _loaded = true;
  }

  void _computeExtent() {
    _minLat = double.infinity;
    _maxLat = double.negativeInfinity;
    _minLng = double.infinity;
    _maxLng = double.negativeInfinity;
    for (final rings in _polygons.values) {
      for (final ring in rings) {
        for (final p in ring) {
          if (p[1] < _minLat) _minLat = p[1];
          if (p[1] > _maxLat) _maxLat = p[1];
          if (p[0] < _minLng) _minLng = p[0];
          if (p[0] > _maxLng) _maxLng = p[0];
        }
      }
    }
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
    if (lga != null) {
      return Jurisdiction(
        lga: lga,
        ward: _nearestWard(lga, lat, lng),
        source: 'GPS',
      );
    }

    // No polygon owns this point. That is either a seam between two LGAs whose
    // boundaries fail to meet — 1.5% of inhabited Plateau, where an incident
    // used to resolve to nothing — or somewhere that is not Plateau at all.
    // The extent tells them apart, and the ward register answers the first.
    final beyondExtent =
        lat < _minLat || lat > _maxLat || lng < _minLng || lng > _maxLng;
    if (beyondExtent) {
      return Jurisdiction.unresolved;
    }
    final seam = _nearestWardAnywhere(lat, lng);
    if (seam == null) return Jurisdiction.unresolved;
    return Jurisdiction(
      lga: seam.lga,
      ward: seam.point.ward,
      source: 'GPS_WARD_REGISTER',
    );
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

  /// The nearest ward centroid across EVERY LGA, with the LGA the ward
  /// register files it under.
  ///
  /// Only ever consulted when no polygon owns the point. Searching all wards
  /// inside a polygon would be wrong: near any LGA border the nearest centroid
  /// is often across the line, which is ordinary Voronoi behaviour and not a
  /// reason to overrule a boundary the polygon is sure about.
  _NearestWard? _nearestWardAnywhere(double lat, double lng) {
    _NearestWard? best;
    var bestDist = double.infinity;
    for (final entry in _wards.entries) {
      for (final w in entry.value) {
        final dx = (w.lng - lng) * math.cos(lat * math.pi / 180);
        final dy = w.lat - lat;
        final d = dx * dx + dy * dy;
        if (d < bestDist) {
          bestDist = d;
          best = _NearestWard(entry.key, w);
        }
      }
    }
    return best;
  }
}

class _NearestWard {
  const _NearestWard(this.lga, this.point);
  final String lga;
  final _WardPoint point;
}

class _WardPoint {
  const _WardPoint(this.ward, this.lat, this.lng);
  final String ward;
  final double lat;
  final double lng;
}
