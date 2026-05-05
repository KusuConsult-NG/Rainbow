import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final userLocationStreamProvider = StreamProvider<Position>((ref) {
  return ref.watch(locationServiceProvider).streamLocation();
});



/// Handles all raw hardware bindings for GPS and network location tracking
/// via the `geolocator` plugin.
class LocationService {
  LocationService();

  /// Requests hardware location permissions from the user.
  Future<bool> requestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are disabled.
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied.
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever.
      return false;
    } 

    return true;
  }

  /// Gets the current instantaneous position.
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );
  }

  /// Streams the user's location in real time natively from hardware GPS streams.
  Stream<Position> streamLocation() async* {
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      debugPrint('[LOC_TRACE] Hardware GPS permissions denied, stream yields empty.');
      return;
    }

    debugPrint('[LOC_TRACE] Requesting continuous hardware location stream lock...');
    
    // Configured for Navigation profile (high density tracking)
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 10, // Only trigger stream updates after moving 10 physical meters
    );

    yield* Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
