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

/// A fix, fresh by default.
///
/// The timestamp used to be a fixed `DateTime.utc(2026, 8, 13, 14)`. A cached
/// position is now refused once it is more than thirty minutes old, so that
/// fixture passed on the day it was written and failed every day afterwards —
/// by the time this was noticed it was forty-six days stale. Age is the thing
/// under test in one case below, so it is a parameter rather than a constant.
Position _position({
  double lat = 9.8965,
  double lng = 8.8583,
  Duration age = const Duration(minutes: 1),
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.now().toUtc().subtract(age),
    accuracy: 5,
    altitude: 1200,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

/// Waits for [condition] or fails. Real time: the stream's retry is a real
/// delay, shortened by the LocationService under test but not removed.
Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String what = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what was still not true after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
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

    test('refuses a cached position that is too old to act on', () async {
      // The rule this fixture used to violate by accident, asserted on
      // purpose. Sending a unit to where somebody was an hour ago is worse
      // than admitting there is no fix: the dispatcher can see "unlocated" and
      // ring them, and cannot see that a confident pin is an hour stale.
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(() => geo.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),).thenThrow(const LocationServiceDisabledException());
      when(() => geo.getLastKnownPosition()).thenAnswer(
        (_) async => _position(lat: 9.5, lng: 8.5, age: const Duration(hours: 1)),
      );

      expect(await service.getCurrentPosition(force: true), isNull);
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

    // THE BUG THIS PROVES GONE. streamLocation() used to `yield null` once at
    // the first refusal and `return`. The stream was then closed for the life
    // of the app: a permission granted afterwards — in Android's settings, or
    // from the emergency screen's own TURN ON LOCATION button — changed
    // nothing, and every screen went on reading `---` until the app was
    // restarted. On the emergency screen that is a person watching empty
    // coordinates while the banner told them their location was broadcasting.
    test('keeps looking, so a permission granted later reaches the app',
        () async {
      // Location is switched off for the whole phone to begin with.
      var serviceOn = false;
      when(() => geo.isLocationServiceEnabled())
          .thenAnswer((_) async => serviceOn);
      when(() => geo.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(() => geo.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),).thenAnswer((_) async => _position());
      when(() => geo.getPositionStream(
            locationSettings: any(named: 'locationSettings'),
          ),).thenAnswer((_) => const Stream<Position>.empty());

      final quick = LocationService(
        retryDelay: (_) => const Duration(milliseconds: 5),
      );
      final seen = <Position?>[];
      final sub = quick.streamLocation().listen(seen.add);
      addTearDown(sub.cancel);

      await _until(() => seen.isNotEmpty, what: 'the no-fix sentinel');
      expect(seen.first, isNull, reason: 'it should say so when it has no fix');

      // The person switches location on. Nothing re-subscribes to the stream.
      serviceOn = true;

      await _until(() => seen.any((p) => p != null),
          what: 'a fix after permission was granted');
      expect(seen.last, isNotNull);
      expect(seen.last!.latitude, closeTo(9.8965, 0.000001));
    });

    // The flag that stops the retry loop turning into a null every few
    // milliseconds. Without it every screen watching this provider would
    // rebuild on a loop for as long as location stayed off.
    test('says it has no fix once, not on every look', () async {
      when(() => geo.isLocationServiceEnabled()).thenAnswer((_) async => false);

      final quick = LocationService(
        retryDelay: (_) => const Duration(milliseconds: 1),
      );
      final seen = <Position?>[];
      final sub = quick.streamLocation().listen(seen.add);
      addTearDown(sub.cancel);

      await _until(() => seen.isNotEmpty, what: 'the no-fix sentinel');
      // Long enough for many retries at a 1 ms delay.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(seen, hasLength(1),
          reason: 'one null, however many times it looked again');
    });

    test('the real retry schedule is quick first, then slow', () {
      expect(LocationService.permissionRetryDelay(0).inSeconds, 3);
      expect(LocationService.permissionRetryDelay(9).inSeconds, 3);
      expect(LocationService.permissionRetryDelay(10).inSeconds, 20);
      expect(LocationService.permissionRetryDelay(500).inSeconds, 20);
    });
  });
}
