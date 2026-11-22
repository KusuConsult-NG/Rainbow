// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

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
  /// [retryDelay] overrides how long the location stream waits before looking
  /// again for a permission it has not got yet. Tests pass a short one;
  /// nothing else should pass anything.
  LocationService({Duration Function(int attempt)? retryDelay})
      : _retryDelay = retryDelay ?? permissionRetryDelay;

  final Duration Function(int attempt) _retryDelay;

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

  /// A position for an SOS: only if location is already allowed, never by
  /// asking, and within [limit]; null otherwise.
  ///
  /// [getCurrentPosition] may show the permission dialog and waits up to 30 s
  /// for an answer, then 5 s for a fix. An SOS waited on all of that before
  /// its alert was written, and in the background, where a dialog cannot
  /// show, it waited the full 30 s; a dialog during a SILENT SOS would also
  /// show anyone watching that help was being called. The alert goes first;
  /// tracking, which starts right after it, can still ask.
  Future<Position?> positionWithoutAsking({Duration limit = const Duration(seconds: 5)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: _buildLocationSettings(),
        ).timeout(limit);
      } catch (_) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null &&
            DateTime.now().difference(lastKnown.timestamp).inMinutes < 30) {
          return lastKnown;
        }
        return null;
      }
    } catch (e) {
      debugPrint('[LOC_ERR] positionWithoutAsking: $e');
      return null;
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

  /// How long the location stream waits before looking again for a permission
  /// the person may have granted since, by attempt number.
  ///
  /// WHY THE STREAM NO LONGER ENDS. It used to `yield null` once at the first
  /// refusal and `return`. The stream was then shut for the life of the app:
  /// granting location afterwards — in Android's settings, or from the
  /// emergency screen's own prompt — changed nothing, and every screen went on
  /// reading `---` until the app was restarted. On the emergency screen that is
  /// a person watching empty coordinates while they believe a squad is being
  /// sent to them. The stream now keeps looking.
  ///
  /// Quick at first, so granting permission feels immediate, then slow, so a
  /// phone with location switched off is not paying for it all day.
  static Duration permissionRetryDelay(int attempt) =>
      attempt < 10 ? const Duration(seconds: 3) : const Duration(seconds: 20);

  /// Whether location may be used right now. Asks for nothing and shows no
  /// dialog, so the stream can keep checking without pestering anybody.
  Future<bool> hasPermissionNow() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return false;
      }
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      debugPrint('[LOC_ERR] hasPermissionNow failed: $e');
      return false;
    }
  }

  /// Streams the user's location in real time natively from hardware GPS streams.
  ///
  /// Emits null as soon as it knows there is no fix, so no screen hangs on the
  /// loading state, and then keeps watching — see [permissionRetryDelay]. Only
  /// the first attempt may prompt; later ones just look ([hasPermissionNow]),
  /// so nobody is shown the system dialog over and over.
  ///
  /// WHY A CONTROLLER AND NOT `async*`. A generator only notices that its
  /// listener has gone at a `yield`, and this loop deliberately yields nothing
  /// while it waits (one null per outage, not one every few seconds). Written
  /// as `async*` the waiting loop was therefore impossible to cancel: it ran
  /// for the rest of the process, and `subscription.cancel()` never completed.
  /// A test that cancelled one hung for thirty seconds, which is how this was
  /// found.
  Stream<Position?> streamLocation() {
    var cancelled = false;
    StreamSubscription<Position>? hardware;
    late StreamController<Position?> out;

    void emit(Position? value) {
      if (!cancelled && !out.isClosed) out.add(value);
    }

    Future<void> run() async {
      var attempt = 0;
      var toldNoFix = false;

      while (!cancelled) {
        bool hasPermission;
        try {
          hasPermission = attempt == 0
              ? await requestPermission().timeout(
                  const Duration(seconds: 30),
                  onTimeout: () => false,
                )
              : await hasPermissionNow();
        } catch (e) {
          debugPrint('[LOC_ERR] Permission check failed: $e');
          hasPermission = false;
        }
        if (cancelled) return;

        if (!hasPermission) {
          if (!toldNoFix) {
            debugPrint(
              '[LOC_TRACE] No location permission yet — emitting the null sentinel and watching for one.',
            );
            emit(null);
            toldNoFix = true;
          }
          await Future<void>.delayed(_retryDelay(attempt));
          attempt++;
          continue;
        }

        toldNoFix = false;
        attempt = 0;

        try {
          // The first fix, as soon as there is one.
          try {
            final initialPosition = await Geolocator.getCurrentPosition(
              locationSettings: _buildLocationSettings(),
            ).timeout(const Duration(seconds: 4));
            emit(initialPosition);
          } catch (e) {
            debugPrint('[LOC_TRACE] Failed to get initial position for stream: $e');
            try {
              final lastKnown = await Geolocator.getLastKnownPosition();
              if (lastKnown != null) {
                // Only use cached position if it's less than 30 minutes old
                final age = DateTime.now().difference(lastKnown.timestamp);
                if (age.inMinutes < 30) {
                  emit(lastKnown);
                } else {
                  debugPrint('[LOC] Last known position is ${age.inMinutes} minutes old — ignoring stale data');
                }
              }
            } catch (_) {}
          }
          if (cancelled) return;

          debugPrint(
            '[LOC_TRACE] Requesting continuous hardware location stream lock...',
          );

          final ended = Completer<void>();
          hardware = Geolocator.getPositionStream(
            locationSettings: _buildLocationSettings(),
          ).listen(
            emit,
            onError: (Object e) {
              debugPrint('[LOC_ERR] Position stream error: $e');
              if (!ended.isCompleted) ended.complete();
            },
            onDone: () {
              if (!ended.isCompleted) ended.complete();
            },
            cancelOnError: true,
          );
          await ended.future;
          await hardware?.cancel();
          hardware = null;
          debugPrint('[LOC_TRACE] Position stream ended — looking again.');
        } catch (e) {
          debugPrint('[LOC_ERR] Stream loop exception: $e');
        }
        if (cancelled) return;

        // The hardware stream ended or threw: location may have been switched
        // off, or permission revoked. Look again rather than go quiet for good.
        await Future<void>.delayed(_retryDelay(attempt));
        attempt++;
      }
    }

    out = StreamController<Position?>(
      onListen: () => unawaited(run()),
      onCancel: () async {
        cancelled = true;
        await hardware?.cancel();
        hardware = null;
      },
    );
    return out.stream;
  }
}
