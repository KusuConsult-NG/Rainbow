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
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('location_disclosure_accepted', true);
        return true;
      }

      if (!force) {
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

      // Any remaining state — notably LocationPermission.unableToDetermine —
      // means permission was NOT confirmed. This used to `return true`, so the
      // service reported access it did not have; callers then attempted a fix,
      // failed, and (before C-5 was fixed) fell back to a fabricated location.
      // Fail closed: an unconfirmed permission is not a granted one.
      debugPrint('[LOC_WARN] Permission state unresolved ($permission) — treating as denied.');
      return false;
    } catch (e) {
      debugPrint('[LOC_ERR] Exception during requestPermission: $e');
      return false;
    }
  }

  LocationSettings _buildLocationSettings({int distanceFilter = 0}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 5),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: distanceFilter,
      );
    } else {
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      );
    }
  }

  /// Gets the current instantaneous position.
  Future<Position?> getCurrentPosition({bool force = false}) async {
    try {
      final hasPermission = await requestPermission(force: force).timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: _buildLocationSettings(),
      ).timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('[LOC_ERR] Failed to get current position: $e');
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          // Only use cached position if it's less than 30 minutes old
          final age = DateTime.now().difference(lastKnown.timestamp);
          if (age.inMinutes < 30) {
            return lastKnown;
          } else {
            debugPrint('[LOC] Last known position is ${age.inMinutes} minutes old — ignoring stale data');
          }
        }
        return null;
      } catch (_) {
        return null;
      }
    }
  }

  /// Streams the user's location in real time natively from hardware GPS streams.
  /// Returns a nullable stream — emits null immediately if permissions are denied
  /// so that consumers never hang on the loading state.
  Stream<Position?> streamLocation() async* {
    try {
      final hasPermission = await requestPermission().timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (!hasPermission) {
        debugPrint(
          '[LOC_TRACE] Hardware GPS permissions denied, yielding null sentinel.',
        );
        yield null;
        return;
      }

      // Fetch and yield initial position immediately
      try {
        final initialPosition = await Geolocator.getCurrentPosition(
          locationSettings: _buildLocationSettings(),
        ).timeout(const Duration(seconds: 4));
        yield initialPosition;
      } catch (e) {
        debugPrint('[LOC_TRACE] Failed to get initial position for stream: $e');
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            // Only use cached position if it's less than 30 minutes old
            final age = DateTime.now().difference(lastKnown.timestamp);
            if (age.inMinutes < 30) {
              yield lastKnown;
            } else {
              debugPrint('[LOC] Last known position is ${age.inMinutes} minutes old — ignoring stale data');
            }
          }
        } catch (_) {}
      }

      debugPrint(
        '[LOC_TRACE] Requesting continuous hardware location stream lock...',
      );

      final settings = _buildLocationSettings();

      try {
        final stream = Geolocator.getPositionStream(locationSettings: settings);
        await for (final pos in stream) {
          yield pos;
        }
      } catch (e) {
        debugPrint('[LOC_ERR] Stream loop exception: $e');
      }
    } catch (e) {
      debugPrint('[LOC_ERR] Failed to initialize location stream: $e');
      yield null;
    }
  }
}
