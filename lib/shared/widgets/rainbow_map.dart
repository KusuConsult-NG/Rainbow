import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:rainbow_app/core/config/map_tiles.dart';
import 'package:latlong2/latlong.dart';

/// Documentation for this public member.

class RainbowMap extends StatelessWidget {
  /// Documentation for this public member.
  const RainbowMap({
    required this.center,
    required this.label,
    super.key,
    this.initialZoom = 15.0,
    this.markers = const [],
    this.polylines = const [],
    this.mapController,
    this.interactive = true,
  });

  /// Documentation for this public member.
  final LatLng center;

  /// What this map IS, for a screen reader.
  ///
  /// Required, with no default, on purpose. flutter_map registers a tap
  /// recognizer for panning and zooming, so an unwrapped map reaches the
  /// accessibility tree as an **unlabelled button covering the screen** — one
  /// a screen reader announces as "button" and that does nothing when
  /// activated. The control sweep found exactly that, and the fix was applied
  /// to `live_tracking_screen.dart`, which builds its own FlutterMap, and to
  /// nowhere else. This widget is the other three maps in the app, and it had
  /// the defect for as long as it has existed. See E2E_AUDIT_REPORT.md T-78.
  ///
  /// A default would have let the next call site skip it silently, which is
  /// the mechanism being closed here rather than one more instance of it.
  ///
  /// On a citizen screen this must come from `Translations.get`. Staff screens
  /// may pass English; `check_citizen_screens_speak_the_language.py` decides
  /// which is which.
  final String label;

  /// Documentation for this public member.
  final double initialZoom;

  /// Documentation for this public member.
  final List<Marker> markers;

  /// Documentation for this public member.
  final List<Polyline> polylines;

  /// Documentation for this public member.
  final MapController? mapController;

  /// Documentation for this public member.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    // `excludeSemantics: true` is what removes the map's own tappable node,
    // and it takes the markers' semantics with it. Any marker that needs to be
    // reachable has to be offered somewhere else on the screen as well — see
    // how safe_zone_screen.dart lists its shelters.
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: initialZoom,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: [
        // CARTO's dark basemap was here. It now answers unauthenticated
        // requests with a placeholder tile reading "API key required", so the
        // command map rendered as a grid of watermarks with the markers floating
        // on top — worse than a blank map, because it looks like somebody
        // else's configuration problem while every geographic reference is gone.
        //
        // OpenStreetMap needs no key. It is light, so it is darkened here rather
        // than bought dark. See lib/core/config/map_tiles.dart.
        if (mapTilesAreAlreadyDark)
          TileLayer(
            urlTemplate: mapTileUrl,
            userAgentPackageName: 'com.plateau.rainbow',
          )
        else
          ColorFiltered(
            colorFilter: darkenTiles,
            child: TileLayer(
              urlTemplate: mapTileUrl,
              userAgentPackageName: 'com.plateau.rainbow',
            ),
          ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
      ),
    );
  }
}
