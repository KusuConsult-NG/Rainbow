// Where a responder's map opens.
//
// It opened at a fixed point in Jos, at zoom 13 — street level. An officer in
// Wase or Shendam got a map of a city 150km away with their own incidents
// off-screen, and had to pan to find the emergency they were being dispatched to.
//
// This is deliberately NOT the same thing as C-5, and the distinction is the
// whole point of the tests below: a VIEWPORT centre is where the camera starts,
// and a fabricated POSITION is a lie attached to a report. An alert with no fix
// still has no coordinates, is still absent from the map, and still belongs in
// HQ's unlocated panel. Centring the camera on the incidents that do have a fix
// invents nothing.
//
// The arithmetic is extracted here rather than driven through the widget, because
// the widget needs a Supabase stream and a tile server; the decision under test
// is which point and which zoom, and that is arithmetic.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// The centre and zoom the responder map opens at, given the alerts it can plot.
///
/// Mirrors `_buildMap` in `agent_dashboard_screen.dart`.
({LatLng centre, double zoom}) viewportFor(List<Map<String, dynamic>> alerts) {
  final plotted = <LatLng>[
    for (final data in alerts)
      if ((data['latitude'] ?? data['lat']) is double &&
          (data['longitude'] ?? data['lng']) is double)
        LatLng(
          (data['latitude'] ?? data['lat']) as double,
          (data['longitude'] ?? data['lng']) as double,
        ),
  ];
  if (plotted.isEmpty) {
    return (centre: const LatLng(9.2182, 9.5179), zoom: 8);
  }
  return (
    centre: LatLng(
      plotted.map((p) => p.latitude).reduce((a, b) => a + b) / plotted.length,
      plotted.map((p) => p.longitude).reduce((a, b) => a + b) / plotted.length,
    ),
    zoom: plotted.length == 1 ? 14 : 10,
  );
}

Map<String, dynamic> at(double lat, double lng) =>
    {'latitude': lat, 'longitude': lng};

void main() {
  test('one incident: the map opens on that incident, close in', () {
    // Shendam, nowhere near Jos. This is the case that was broken.
    final v = viewportFor([at(8.8800, 9.5300)]);
    expect(v.centre.latitude, closeTo(8.88, 0.001));
    expect(v.centre.longitude, closeTo(9.53, 0.001));
    expect(v.zoom, 14);
  });

  test('several incidents: the map opens between them, wider', () {
    final v = viewportFor([at(9.90, 8.85), at(8.88, 9.53)]);
    expect(v.centre.latitude, closeTo(9.39, 0.01));
    expect(v.centre.longitude, closeTo(9.19, 0.01));
    expect(v.zoom, 10, reason: 'two incidents 150km apart need a wider view');
  });

  test('no located incidents: the state, not a street in Jos', () {
    // The honest view is "nothing located anywhere in Plateau", which is a
    // state-wide zoom. A street-level view of Jos says "nothing here", which is
    // a different and misleading claim.
    final v = viewportFor([]);
    expect(v.zoom, 8);
    expect(v.centre.latitude, closeTo(9.2182, 0.001));
  });

  test('an alert with no fix does not drag the viewport anywhere', () {
    // The C-5 boundary. A report with no GPS contributes NOTHING — it is not
    // plotted at a guessed point, and it does not move the camera.
    final withFix = viewportFor([at(8.88, 9.53)]);
    final plusUnlocated = viewportFor([
      at(8.88, 9.53),
      {'latitude': null, 'longitude': null},
      <String, dynamic>{},
    ]);
    expect(plusUnlocated.centre.latitude, withFix.centre.latitude);
    expect(plusUnlocated.centre.longitude, withFix.centre.longitude);
    expect(plusUnlocated.zoom, withFix.zoom);
  });

  test('only unlocated alerts is the same as none, not a point at zero', () {
    // (0, 0) is in the Atlantic. An earlier version of this system reported an
    // SOS with no fix at the centre of Jos; reporting it at Null Island would be
    // the same class of mistake with a different coordinate.
    final v = viewportFor([
      {'latitude': null, 'longitude': null},
      {'lat': null, 'lng': null},
    ]);
    expect(v.zoom, 8);
    expect(v.centre.latitude, closeTo(9.2182, 0.001));
  });

  test('the legacy lat/lng spelling is plotted too', () {
    // SQLite stores `lat`/`lng`; Supabase stores `latitude`/`longitude`. Reading
    // only one spelling is how every offline-queued alert reached HQ with no
    // coordinates.
    final v = viewportFor([{'lat': 9.90, 'lng': 8.85}]);
    expect(v.zoom, 14);
    expect(v.centre.latitude, closeTo(9.90, 0.001));
  });
}
