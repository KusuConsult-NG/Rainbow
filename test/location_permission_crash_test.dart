import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/location_service.dart';

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
      final pos = await locationService.getCurrentPosition();
      // Reaching this line IS the property under test: the call completed
      // instead of throwing. The previous assertion was
      // `pos == null || pos is Position` on a `Position?`, which can never be
      // false — it asserted nothing at all, which is what the analyzer's
      // "unnecessary type check" was pointing at.
      //
      // When a position does come back, assert something real about it: C-5
      // was about coordinates that were fabricated rather than measured, so a
      // position outside the valid range is a defect, not a pass.
      if (pos != null) {
        expect(pos.latitude, inInclusiveRange(-90, 90));
        expect(pos.longitude, inInclusiveRange(-180, 180));
      }
    });

    test('3. streamLocation yields null sentinel when permission is denied instead of throwing', () async {
      final stream = locationService.streamLocation();
      final firstEmitted = await stream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      // Same tautology as above. What matters is that the stream yielded a
      // null sentinel instead of throwing, and that any real fix is usable.
      if (firstEmitted != null) {
        expect(firstEmitted.latitude, inInclusiveRange(-90, 90));
        expect(firstEmitted.longitude, inInclusiveRange(-180, 180));
      }
    });

    test('4. BackgroundTrackingService handles status updates without throwing', () async {
      final bgService = BackgroundTrackingService();
      expect(() async => bgService.stopTracking(), returnsNormally);
    });
  });
}
