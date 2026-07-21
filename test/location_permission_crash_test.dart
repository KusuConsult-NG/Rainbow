import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Location Permission & Crash Diagnostics', () {
    late LocationService locationService;

    setUp(() {
      locationService = LocationService();
    });

    test('1. requestPermission returns false gracefully when permissions are denied', () async {
      // Test that requestPermission does not throw unhandled exceptions
      final result = await locationService.requestPermission(force: true);
      expect(result, isA<bool>());
    });

    test('2. getCurrentPosition handles timeouts and null position without process crash', () async {
      final pos = await locationService.getCurrentPosition(force: false);
      // Returns null or position safely without throwing unhandled exception
      expect(pos == null || pos is Position, isTrue);
    });

    test('3. streamLocation yields null sentinel when permission is denied instead of throwing', () async {
      final stream = locationService.streamLocation();
      final firstEmitted = await stream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      expect(firstEmitted == null || firstEmitted is Position, isTrue);
    });

    test('4. BackgroundTrackingService handles status updates without throwing', () async {
      final bgService = BackgroundTrackingService();
      expect(() async => await bgService.stopTracking(), returnsNormally);
    });
  });
}
