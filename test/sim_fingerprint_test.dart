// Noticing that the SIM has gone — and, more importantly, not claiming it has
// when we simply cannot see.
//
// A false "SIM removed" costs an operator a call to somebody whose phone is
// fine. A few of those and the whole console learns to ignore the alert, which
// is worse than not having it at all. So most of these tests are about
// silence.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/device/sim_fingerprint.dart';

const mtn = SimSnapshot(
  presence: SimPresence.present,
  operatorCode: '62130',
  operatorName: 'MTN',
);
const airtel = SimSnapshot(
  presence: SimPresence.present,
  operatorCode: '62120',
  operatorName: 'Airtel',
);
const empty = SimSnapshot(presence: SimPresence.absent);
const blind = SimSnapshot.unavailable();

void main() {
  group('what is detected', () {
    test('the SIM being taken out', () {
      expect(compareSim(mtn, empty), SimChange.removed);
    });

    test('a SIM being put in', () {
      // Reported too: a handset that was running without a SIM and now has one
      // is the second half of a swap whose first half happened while the app
      // was closed.
      expect(compareSim(empty, mtn), SimChange.inserted);
    });

    test('a SIM from a different network', () {
      expect(compareSim(mtn, airtel), SimChange.replaced);
    });
  });

  group('what is honestly NOT detected', () {
    test('one MTN SIM swapped for another MTN SIM', () {
      // The commonest swap of all, and it is invisible: the ICCID and the IMSI
      // have needed READ_PRIVILEGED_PHONE_STATE since Android 10, which is a
      // signature-level permission no ordinary app can hold. An operator who
      // believed "SIM swap" was covered would be wrong about this case, so it
      // is asserted rather than left to be discovered.
      const otherMtn = SimSnapshot(
        presence: SimPresence.present,
        operatorCode: '62130',
        operatorName: 'MTN',
      );
      expect(compareSim(mtn, otherMtn), SimChange.none);
    });

    test('anything at all on a platform that will not say', () {
      // iOS 16+ returns a placeholder carrier. "We cannot see" must never be
      // reported as "it has been removed".
      expect(compareSim(mtn, blind), SimChange.none);
      expect(compareSim(blind, empty), SimChange.none);
      expect(compareSim(blind, blind), SimChange.none);
    });

    test('the first reading of all', () {
      // Fresh install, or the first run after this feature shipped. There is
      // no change, only a baseline.
      expect(compareSim(null, empty), SimChange.none);
      expect(compareSim(null, mtn), SimChange.none);
    });

    test('a present SIM whose network cannot be read', () {
      const unnamed = SimSnapshot(presence: SimPresence.present);
      expect(compareSim(mtn, unnamed), SimChange.none);
      expect(compareSim(unnamed, mtn), SimChange.none);
    });

    test('an empty operator code is treated as no code, not as a change', () {
      const blankCode = SimSnapshot(
        presence: SimPresence.present,
        operatorCode: '',
      );
      expect(compareSim(mtn, blankCode), SimChange.none);
    });

    test('still no SIM is not news', () {
      expect(compareSim(empty, empty), SimChange.none);
    });

    test('the same SIM is not news', () {
      expect(compareSim(mtn, mtn), SimChange.none);
    });
  });

  group('reading a stored baseline back', () {
    test('round-trips', () {
      final back = SimSnapshot.fromJson(mtn.toJson());
      expect(back.presence, SimPresence.present);
      expect(back.operatorCode, '62130');
      expect(back.operatorName, 'MTN');
      expect(compareSim(back, mtn), SimChange.none);
    });

    test('a record from an older build reads as unavailable, not as absent', () {
      // The difference decides whether a silent upgrade raises "SIM REMOVED"
      // on every handset in the state at once.
      expect(SimSnapshot.fromJson(null).presence, SimPresence.unavailable);
      expect(
        SimSnapshot.fromJson(<String, dynamic>{'something': 'else'}).presence,
        SimPresence.unavailable,
      );
      expect(
        SimSnapshot.fromJson(<String, dynamic>{'presence': 'PRESENT'}).presence,
        SimPresence.unavailable,
        reason: 'the enum is lower-case; a near-miss must not be guessed at',
      );
    });

    test('an unreadable record raises nothing', () {
      final stored = SimSnapshot.fromJson(<String, dynamic>{'presence': 'junk'});
      expect(compareSim(stored, empty), SimChange.none);
    });
  });

  group('what is said about it', () {
    test('HQ is told what the change means for the channel', () {
      final removed = describeSimChange(SimChange.removed);
      expect(removed, contains('SIM REMOVED'));
      expect(removed.toLowerCase(), contains('sms'));

      final replaced = describeSimChange(
        SimChange.replaced,
        operatorName: 'Airtel',
      );
      expect(replaced, contains('Airtel'));
    });

    test('the person is told, on the handset, that this was reported', () {
      // Reporting a change to a state console without telling the holder is
      // surveillance. This app is used by people who report things they can be
      // harmed for reporting.
      for (final change in <SimChange>[
        SimChange.removed,
        SimChange.replaced,
      ]) {
        final notice = simChangeNoticeForUser(change);
        expect(notice.toLowerCase(), contains('hq has been told'));
        expect(
          notice.toLowerCase(),
          contains('not where you are'),
          reason: 'the record is about the channel, never about a location',
        );
      }
    });

    test('nothing is said when nothing changed', () {
      expect(simChangeNoticeForUser(SimChange.none), isEmpty);
      expect(shouldReport(SimChange.none), isFalse);
      expect(shouldReport(SimChange.removed), isTrue);
    });
  });
}
