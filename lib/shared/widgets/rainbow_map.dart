import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RainbowMap extends StatelessWidget {
  final LatLng center;
  final double initialZoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final MapController? mapController;
  final bool interactive;

  const RainbowMap({
    super.key,
    required this.center,
    this.initialZoom = 15.0,
    this.markers = const [],
    this.polylines = const [],
    this.mapController,
    this.interactive = true,
  });

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
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.plateau.rainbow',
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }
}
