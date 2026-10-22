// A tracked SOS must be bound to an id the database will accept.
//
// `alerts.id` is a UUID. `telemetry.alert_id` and `incident_tracks.alert_id`
// are UUID columns with a foreign key to it. An SOS raised while the handset
// has no data path is filed into the local SQLite queue and tracked against
// `newOfflineLocalId()` — `OFFLINE_<millis>_<12 hex>` — which is not a UUID.
//
// Writing that fails at the TYPE, before the foreign key is consulted:
// `22P02 invalid input syntax for type uuid`. The cost was not only the route.
// `alert_id` sits in the same payload as the position, so the whole telemetry
// upsert was rejected and the dispatcher watching an offline SOS saw NO DOT —
// for the entire emergency, with a `[TELEMETRY_FAIL]` debug line as the only
// trace.
//
// And it never recovered. The queue flush computes a local-id-to-UUID mapping,
// returned it, and nothing consumed it, so the track stayed bound to an id no
// table would take even after the alert had a real row.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';

void main() {
  group('an offline id is never written to a UUID column', () {
    test('the id an offline SOS is tracked against is refused', () {
      // The exact shape `newOfflineLocalId()` mints.
      expect(
        BackgroundTrackingService.isServerAlertId('OFFLINE_1761132000000_a1b2c3d4e5f6'),
        isFalse,
      );
    });

    test('a real alert id is accepted', () {
      expect(
        BackgroundTrackingService.isServerAlertId(
          'aaaa1111-0000-4000-8000-00000000a001',
        ),
        isTrue,
      );
    });

    test('no id at all is refused rather than written as null text', () {
      expect(BackgroundTrackingService.isServerAlertId(null), isFalse);
      expect(BackgroundTrackingService.isServerAlertId(''), isFalse);
    });

    // The guard must not be a `startsWith('OFFLINE_')` check in disguise: any
    // id that is not a UUID has to be refused, whatever it looks like.
    test('anything that is not a UUID is refused', () {
      for (final notAUuid in [
        'null',
        '12345',
        'aaaa1111-0000-4000-8000-00000000a001-extra',
        'aaaa1111-0000-4000-8000-00000000a00',
        'zzzzzzzz-0000-4000-8000-00000000a001',
        ' aaaa1111-0000-4000-8000-00000000a001',
      ]) {
        expect(
          BackgroundTrackingService.isServerAlertId(notAUuid),
          isFalse,
          reason: '$notAUuid is not a UUID and must not reach a UUID column',
        );
      }
    });

    // Upper case is a UUID. PostgreSQL accepts it, so refusing it would drop
    // the route for a perfectly good id.
    test('an uppercase UUID is still a UUID', () {
      expect(
        BackgroundTrackingService.isServerAlertId(
          'AAAA1111-0000-4000-8000-00000000A001',
        ),
        isTrue,
      );
    });
  });
}
