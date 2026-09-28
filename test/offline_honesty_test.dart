// What the person is told when the report did not arrive.
//
// The report screen decided between "REPORT TRANSMITTED" and "REPORT QUEUED
// LOCALLY" from `connectivityResult.contains(ConnectivityResult.none)` — a
// reading of the RADIO, taken BEFORE the submit. That answers "does this phone
// have a network interface up", which is not the question. The question is
// "did the report arrive".
//
// The two come apart in every case that matters: a captive portal, DNS
// failure, an expired token, a row-level-security refusal, a column the schema
// does not have, or the backend being down. In all of them the radio says
// connected, the insert fails, the alert goes to the local queue — and the
// person was shown a green REPORT TRANSMITTED with a shield on it.
//
// It is the same failure mode that hid `alerts.reportedBy` for months: an
// insert the database refused looked exactly like one that succeeded.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/alert_service.dart';

void main() {
  group('did this report actually reach the database', () {
    test('a real uuid means it arrived', () {
      expect(
        AlertService.wasQueuedOffline('3f2a9c10-7b4e-4f0a-9d21-8c5b6e7a1d34'),
        isFalse,
      );
    });

    test('an OFFLINE_ id means it is still on the phone', () {
      expect(AlertService.wasQueuedOffline('OFFLINE_1790500000000'), isTrue);
    });

    test('a LOCAL_ id does too', () {
      // The SOS path uses this prefix; both mean the same thing to a reader.
      expect(AlertService.wasQueuedOffline('LOCAL_1790500000000'), isTrue);
    });

    test('no id at all is not a delivery', () {
      expect(AlertService.wasQueuedOffline(null), isFalse);
      // Deliberate: a null id is a failure to submit, not a queued report, and
      // the screen has its own error path for it. What must never happen is a
      // null being read as "delivered".
    });

    test('a uuid that merely CONTAINS the word offline still counts as sent',
        () {
      // Guarding the prefix check against becoming a substring check, which
      // would start calling real deliveries queued.
      expect(AlertService.wasQueuedOffline('a1b2-OFFLINE_-c3d4'), isFalse);
    });
  });
}
