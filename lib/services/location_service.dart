// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Documentation for this public member.

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Documentation for this public member.

final userLocationStreamProvider = StreamProvider<Position?>((ref) {
  return ref.watch(locationServiceProvider).streamLocation();
});

/// Handles all raw hardware bindings for GPS and network location tracking
/// via the `geolocator` plugin.
class LocationService {
  /// Documentation for this public member.
  LocationService();

  /// Requests hardware location permissions from the user.
  Future<bool> requestPermission({bool force = false}) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are disabled.
      return false;
    }

    // 1. First check if permission has ALREADY been granted at OS level
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      // Ensure disclosure flag is marked accepted since OS permission is active
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('location_disclosure_accepted', true);
      return true;
    }

    if (!force) {
      // 2. Guard against native popups if user has not accepted prominent disclosure
      final prefs = await SharedPreferences.getInstance();
      final isDisclosureAccepted =
          prefs.getBool('location_disclosure_accepted') ?? false;
      if (!isDisclosureAccepted) {
        debugPrint(
          '[LOC_WARN] LocationService: Prominent disclosure not yet accepted. Aborting permission request.',
        );
        return false;
      }
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('location_disclosure_accepted', true);
      return true;
    }

    return true;
  }

  /// Gets the current instantaneous position.
  Future<Position?> getCurrentPosition({bool force = false}) async {
    try {
      final hasPermission = await requestPermission(force: force).timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(
        const Duration(seconds: 5),
      );
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[LOC_ERR] Failed to get current position: $e');
      return null;
    }
  }

  /// Streams the user's location in real time natively from hardware GPS streams.
  /// Returns a nullable stream — emits null immediately if permissions are denied
  /// so that consumers never hang on the loading state.
  Stream<Position?> streamLocation() async* {
    try {
      final hasPermission = await requestPermission().timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
      if (!hasPermission) {
        debugPrint(
          '[LOC_TRACE] Hardware GPS permissions denied, yielding null sentinel.',
        );
        yield null;
        return;
      }

      // Fetch and yield the current/initial position immediately to populate the UI instantly
      try {
        final initialPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
          ),
        ).timeout(const Duration(seconds: 3));
        yield initialPosition;
      } catch (e) {
        debugPrint('[LOC_TRACE] Failed to get initial position for stream: $e');
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          yield lastKnown;
        }
      }

      debugPrint(
        '[LOC_TRACE] Requesting continuous hardware location stream lock...',
      );

      // Configured for Navigation profile (high density tracking, no distance filter during active SOS)
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );

      yield* Geolocator.getPositionStream(locationSettings: locationSettings)
          .handleError((Object error) {
        debugPrint('[LOC_ERR] Continuous stream error: $error');
      });
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[LOC_ERR] Failed to initialize location stream: $e');
      yield null;
    }
  }
}
