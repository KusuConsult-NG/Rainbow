import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
        // CartoDB Dark Matter Tiles for Tactical Aesthetic
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.plateau.rainbow',
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }
}
