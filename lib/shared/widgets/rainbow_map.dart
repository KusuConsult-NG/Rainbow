import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:rainbow_app/core/config/map_tiles.dart';
import 'package:latlong2/latlong.dart';

/// Documentation for this public member.

class RainbowMap extends StatelessWidget {
  /// Documentation for this public member.
  const RainbowMap({
    required this.center,
    super.key,
    this.initialZoom = 15.0,
    this.markers = const [],
    this.polylines = const [],
    this.mapController,
    this.interactive = true,
  });

  /// Documentation for this public member.
  final LatLng center;

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
    return FlutterMap(
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
    );
  }
}
