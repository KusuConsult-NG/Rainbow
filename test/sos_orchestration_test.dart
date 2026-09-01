// Coverage for `EmergencyNotifier.startEmergency` — the SOS orchestration.
//
// This path had NO test at all, which was found during an audit pass, after the
// path had already been restructured twice: the escalation SMS was moved from
// before the alert write to after it (H-3), and then out of the try/catch
// entirely. Both were changes to the code that runs when a citizen presses the
// panic button, and nothing would have failed if either had been wrong.
//
// The assertions here are about ORDERING and INDEPENDENCE, not about SMS
// plumbing (covered in sos_dispatch_service_test.dart) or alert payloads
// (covered in offline_queue_test.dart). Specifically:
//
//   * the alert row is written, and it is written FIRST;
//   * the escalation SMS still fires when the alert write fails — a redundant
//     channel that only works when the primary succeeded is not redundancy;
//   * a local/offline id is never quoted to a dispatcher as a real reference;
//   * a missing GPS fix propagates as null and is never substituted (C-5).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/sos_dispatch_service.dart';

class _MockAlertService extends Mock implements AlertService {}

class _MockSosDispatchService extends Mock implements SosDispatchService {}

/// `AuthNotifier`'s constructor calls `initAuth()`, which starts a 5s timer and
/// talks to Supabase. It is a public instance method, so a subclass can
/// neutralise it — Dart dispatches virtually even from the base constructor body.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(AuthState initial) {
    state = initial;
  }

  @override
  void initAuth() {}
}

void main() {
  // Geolocator and the background-tracking service have no platform
  // implementation here; both catch their own failures, so the SOS proceeds
  // with no GPS fix. That is exactly the C-5 scenario, reproduced for free.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAlertService alerts;
  late _MockSosDispatchService sms;

  /// Records the order in which the two collaborators were called, which is the
  /// property under test: the system of record must not wait on the SMS.
  late List<String> callOrder;

  ProviderContainer containerWith({
    required Future<String?> Function() onSubmit,
  }) {
    when(
      () => alerts.submitAlert(
        type: any(named: 'type'),
        description: any(named: 'description'),
        reportedBy: any(named: 'reportedBy'),
        latitude: any(named: 'latitude'),
        longitude: any(named: 'longitude'),
        isCritical: any(named: 'isCritical'),
        geoLga: any(named: 'geoLga'),
        geoWard: any(named: 'geoWard'),
      ),
    ).thenAnswer((_) async {
      callOrder.add('alert');
      return onSubmit();
    });

    when(
      () => sms.dispatchSos(
        alertId: any(named: 'alertId'),
        latitude: any(named: 'latitude'),
        longitude: any(named: 'longitude'),
      ),
    ).thenAnswer((_) async {
      callOrder.add('sms');
      return SosDispatchResult.sent;
    });

    return ProviderContainer(
      overrides: [
        alertServiceProvider.overrideWithValue(alerts),
        sosDispatchServiceProvider.overrideWithValue(sms),
        authProvider.overrideWith(
          (ref) => _FakeAuthNotifier(
            AuthState(
              role: UserRole.citizen,
              isLoading: false,
              profile: const {'geo_lga': 'JOS NORTH', 'geo_ward': 'NARAGUTA'},
            ),
          ),
        ),
      ],
    );
  }

  setUp(() {
    alerts = _MockAlertService();
    sms = _MockSosDispatchService();
    callOrder = <String>[];
  });

  /// Lets the unawaited SMS dispatch settle before assertions run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('startEmergency — happy path', () {
    test('writes the alert BEFORE dispatching the SMS', () async {
      final c = containerWith(onSubmit: () async => 'server-uuid-1234');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      expect(
        callOrder,
        ['alert', 'sms'],
        reason: 'The alert row is the system of record. The SMS used to run '
            'first, blocking it behind an SMS provider latency.',
      );
    });

    test('quotes the real alert id to dispatch', () async {
      final c = containerWith(onSubmit: () async => 'server-uuid-1234');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      final captured = verify(
        () => sms.dispatchSos(
          alertId: captureAny(named: 'alertId'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        ),
      ).captured.single;
      expect(captured, 'server-uuid-1234');
      expect(c.read(emergencyProvider).alertId, 'server-uuid-1234');
      expect(c.read(emergencyProvider).isEmergencyActive, isTrue);
    });
  });

  group('startEmergency — the redundant channel must be independent', () {
    // REGRESSION. The SMS dispatch sat inside the try, after submitAlert.
    // AlertService swallows everything today so it could not throw — but that
    // made the SOS fallback silently depend on an implementation detail of a
    // different class. A later `rethrow` would have removed the fallback in
    // exactly the situation it exists for, with no test failing.
    test('SMS still fires when the alert write THROWS', () async {
      final c = containerWith(
        onSubmit: () async => throw StateError('database unreachable'),
      );
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      verify(
        () => sms.dispatchSos(
          alertId: any(named: 'alertId'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        ),
      ).called(1);
    });

    test('a thrown alert write surfaces an error but keeps the SOS active', () async {
      final c = containerWith(
        onSubmit: () async => throw StateError('database unreachable'),
      );
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      final s = c.read(emergencyProvider);
      expect(s.isEmergencyActive, isTrue,
          reason: 'A failed write must not cancel the emergency.');
      expect(s.errorMessage, isNotNull);
      expect(s.alertId, isNull);
    });
  });

  group('startEmergency — offline / local ids', () {
    // 'LOCAL_1723…' means nothing to a dispatcher and would read as a real
    // reference on an SMS. Null is honest; the row syncs later under its own id.
    test('an OFFLINE_ id is not quoted to dispatch', () async {
      final c = containerWith(onSubmit: () async => 'OFFLINE_1699999999999');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      final captured = verify(
        () => sms.dispatchSos(
          alertId: captureAny(named: 'alertId'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        ),
      ).captured.single;
      expect(captured, isNull);
      expect(c.read(emergencyProvider).alertId, isNull);
    });

    test('a LOCAL_ id is not quoted to dispatch either', () async {
      final c = containerWith(onSubmit: () async => 'LOCAL_1699999999999');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      expect(c.read(emergencyProvider).alertId, isNull);
    });

    test('the SMS is still dispatched for an offline alert', () async {
      final c = containerWith(onSubmit: () async => 'OFFLINE_1699999999999');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      expect(callOrder, ['alert', 'sms']);
    });
  });

  group('startEmergency — C-5, no fabricated coordinates', () {
    // Geolocator has no platform implementation under `flutter test`, so
    // getCurrentPosition throws and the SOS proceeds with no fix. That is the
    // exact scenario C-5 was about, and it is reproduced here for free.
    test('a missing GPS fix reaches both collaborators as null', () async {
      final c = containerWith(onSubmit: () async => 'server-uuid-1234');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      final alertCoords = verify(
        () => alerts.submitAlert(
          type: any(named: 'type'),
          description: any(named: 'description'),
          reportedBy: any(named: 'reportedBy'),
          latitude: captureAny(named: 'latitude'),
          longitude: captureAny(named: 'longitude'),
          isCritical: any(named: 'isCritical'),
          geoLga: any(named: 'geoLga'),
          geoWard: any(named: 'geoWard'),
        ),
      ).captured;
      expect(alertCoords, [null, null],
          reason: 'No fix must stay null — 9.9167/8.8917 was a real dispatch bug.');

      final smsCoords = verify(
        () => sms.dispatchSos(
          alertId: any(named: 'alertId'),
          latitude: captureAny(named: 'latitude'),
          longitude: captureAny(named: 'longitude'),
        ),
      ).captured;
      expect(smsCoords, [null, null]);
    });

    test('jurisdiction is still attached when the position is unknown', () async {
      final c = containerWith(onSubmit: () async => 'server-uuid-1234');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      final captured = verify(
        () => alerts.submitAlert(
          type: any(named: 'type'),
          description: any(named: 'description'),
          reportedBy: any(named: 'reportedBy'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
          isCritical: any(named: 'isCritical'),
          geoLga: captureAny(named: 'geoLga'),
          geoWard: captureAny(named: 'geoWard'),
        ),
      ).captured;
      expect(captured, ['JOS NORTH', 'NARAGUTA'],
          reason: 'An unlocated alert is still routable by jurisdiction.');
    });

    test('the alert is marked critical', () async {
      final c = containerWith(onSubmit: () async => 'server-uuid-1234');
      addTearDown(c.dispose);

      await c.read(emergencyProvider.notifier).startEmergency();
      await settle();

      final captured = verify(
        () => alerts.submitAlert(
          type: any(named: 'type'),
          description: any(named: 'description'),
          reportedBy: any(named: 'reportedBy'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
          isCritical: captureAny(named: 'isCritical'),
          geoLga: any(named: 'geoLga'),
          geoWard: any(named: 'geoWard'),
        ),
      ).captured.single;
      expect(captured, isTrue);
    });
  });
}
