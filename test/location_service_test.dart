// LocationService — POSITIVE-path coverage.
//
// The existing suite only ever hit `MissingPluginException`, so every location
// test passed through the *error* branch. Nothing proved that an SOS captures
// the right coordinates when the GPS actually works — which matters, because
// those coordinates are what dispatches responders to a person in danger.
//
// These tests swap `GeolocatorPlatform.instance` for a mock, so the real
// LocationService logic runs against controllable hardware responses.
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGeolocatorPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {}

Position _position({double lat = 9.8965, double lng = 8.8583}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026, 8, 13, 14),
    accuracy: 5,
    altitude: 1200,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockGeolocatorPlatform geo;
  late LocationService service;

  setUpAll(() {
    registerFallbackValue(const LocationSettings());
  });

  setUp(() {
    geo = MockGeolocatorPlatform();
    GeolocatorPlatform.instance = geo;
    service = LocationService();
    SharedPreferences.setMockInitialValues({});
  });

  group('requestPermission', () {
    test('returns false when location services are switched off', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => false);
      expect(await service.requestPermission(), isFalse);
    });

    test('returns true when permission is already granted', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);

      expect(await service.requestPermission(), isTrue);
    });

    // Play Store policy: the prominent-disclosure dialog must be accepted before
    // a permission prompt. Without `force`, an un-disclosed request is refused.
    test('refuses an un-forced request before disclosure is accepted', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);

      expect(await service.requestPermission(), isFalse);
      verifyNever(() => geo.requestPermission());
    });

    // ...but an SOS passes force: true, which must reach the real prompt.
    test('force: true prompts even without prior disclosure', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => geo.requestPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);

      expect(await service.requestPermission(force: true), isTrue);
      verify(() => geo.requestPermission()).called(1);
    });

    test('returns false when the user denies the prompt', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => geo.requestPermission())
          .thenAnswer((_) async => LocationPermission.denied);

      expect(await service.requestPermission(force: true), isFalse);
    });

    test('returns false when permission is permanently denied', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.deniedForever);

      expect(await service.requestPermission(force: true), isFalse);
    });

    // REGRESSION: `unableToDetermine` used to fall through to a trailing
    // `return true`, so the service reported permission it had not confirmed.
    // Callers then attempted a fix, failed, and fell back to a fabricated
    // location (C-5). An unconfirmed permission is not a granted one.
    test('REGRESSION: unableToDetermine fails closed', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.unableToDetermine);

      expect(await service.requestPermission(force: true), isFalse);
    });
  });

  group('getCurrentPosition', () {
    test('returns the real fix when permission is granted', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(() => geo.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),).thenAnswer((_) async => _position());

      final pos = await service.getCurrentPosition(force: true);

      expect(pos, isNotNull);
      expect(pos!.latitude, closeTo(9.8965, 0.000001));
      expect(pos.longitude, closeTo(8.8583, 0.000001));
    });

    test('returns null rather than a guess when permission is refused',
        () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => false);

      expect(await service.getCurrentPosition(force: true), isNull);
      verifyNever(() => geo.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),);
    });

    // A live fix is preferred, but a recent cached one beats nothing for an SOS.
    test('falls back to the last known position when the live fix fails',
        () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(() => geo.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),).thenThrow(const LocationServiceDisabledException());
      when(() => geo.getLastKnownPosition())
          .thenAnswer((_) async => _position(lat: 9.5, lng: 8.5));

      final pos = await service.getCurrentPosition(force: true);

      expect(pos, isNotNull);
      expect(pos!.latitude, closeTo(9.5, 0.000001));
    });

    test('returns null when both the live and cached fixes fail', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(() => geo.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),).thenThrow(const LocationServiceDisabledException());
      when(() => geo.getLastKnownPosition()).thenAnswer((_) async => null);

      expect(await service.getCurrentPosition(force: true), isNull);
    });
  });

  group('streamLocation', () {
    test('emits a null sentinel instead of hanging when denied', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => false);

      expect(await service.streamLocation().first, isNull);
    });

    test('emits the initial fix before the continuous stream', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(() => geo.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),).thenAnswer((_) async => _position());
      when(() => geo.getPositionStream(
            locationSettings: any(named: 'locationSettings'),
          ),).thenAnswer((_) => const Stream<Position>.empty());

      final first = await service.streamLocation().first;

      expect(first, isNotNull);
      expect(first!.latitude, closeTo(9.8965, 0.000001));
    });
  });
}
