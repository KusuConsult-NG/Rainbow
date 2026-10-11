// Which incidents reach a handset.
//
// This rule lived inside `alertsStreamProvider` as a `.where()`, and every test
// that touches the feed overrides that provider — so it had no test at all.
// These cover the behaviours it already had, and the one it did not: the word
// "liaison" appeared nowhere in lib/, while RLS hands an agency liaison exactly
// the incidents escalated to their agency and nothing else.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/alert_audience.dart';

const _me = 'bbbb2222-0000-4000-8000-00000000b002';

Map<String, dynamic> alert({
  String? lga = 'JOS NORTH',
  String? ward = 'NARAGUTA',
  String? pu = 'PU-01',
  String? agency,
  String? assignedTo,
  List<String>? team,
}) =>
    <String, dynamic>{
      'id': 'a1',
      'geo_lga': lga,
      'geo_ward': ward,
      'geo_pu': pu,
      'escalated_to_agency': agency,
      'assigned_to': assignedTo,
      'assigned_responders': team,
    };

const jos = AlertAudience(
  userId: _me,
  role: 'RESPONDER',
  geoLga: 'JOS NORTH',
  geoWard: 'NARAGUTA',
  geoPu: 'PU-01',
);

void main() {
  group('theirs by name', () {
    test('the lead sees it wherever it is', () {
      final far = alert(lga: 'MANGU', ward: 'PANYAM', pu: 'PU-11', assignedTo: _me);
      expect(alertReaches(far, jos), isTrue);
    });

    test('so does an officer on the dispatched team', () {
      final far = alert(lga: 'MANGU', ward: 'PANYAM', pu: 'PU-11', team: [_me]);
      expect(alertReaches(far, jos), isTrue);
    });

    test('and a session with no id is not assigned anything', () {
      final unassigned = AlertAudience(role: jos.role, geoLga: jos.geoLga);
      expect(alertReaches(alert(assignedTo: null, team: null), unassigned), isTrue);
      // ^ reached on place, not on assignment. The point is the next one:
      final far = alert(lga: 'MANGU', ward: 'PANYAM', pu: 'PU-11', assignedTo: _me);
      expect(alertReaches(far, unassigned), isFalse);
    });
  });

  group('an outside agency sees what was handed to them', () {
    const army = AlertAudience(
      userId: 'liaison-1',
      role: 'ARMY_LIAISON',
      agency: 'ARMY',
      geoLga: 'MANGU',
      geoWard: 'PANYAM',
      geoPu: 'PU-11',
    );

    test('an incident escalated to their agency reaches them', () {
      // The case that was broken: RLS hands them exactly this row, and the
      // filter dropped it because JOS NORTH is not MANGU.
      expect(alertReaches(alert(agency: 'ARMY'), army), isTrue);
    });

    test('wherever in the state it is, because their posting is not the point', () {
      expect(alertReaches(alert(lga: 'BOKKOS', ward: 'MUSHERE', pu: 'PU-03', agency: 'ARMY'), army), isTrue);
      expect(alertReaches(alert(lga: null, ward: null, pu: null, agency: 'ARMY'), army), isTrue);
    });

    test('an incident handed to another agency does not', () {
      expect(alertReaches(alert(agency: 'POLICE'), army), isFalse);
    });

    test('nor one on their own doorstep that was handed to nobody', () {
      // Against the local stand-in, which applies no RLS, the place rules used
      // to admit exactly this — so the Police liaison, posted where the fixture
      // incidents are, saw incidents never handed to the Police. Empty against
      // production, wrong against the stand-in, green in both.
      final home = alert(lga: 'MANGU', ward: 'PANYAM', pu: 'PU-11');
      expect(alertReaches(home, army), isFalse);
    });

    test('an incident assigned to them personally still reaches them', () {
      final mine = alert(lga: 'BOKKOS', agency: 'POLICE', assignedTo: 'liaison-1');
      expect(alertReaches(mine, army), isTrue);
    });

    test('the agency code is matched case- and space-insensitively', () {
      expect(alertReaches(alert(agency: '  army  '), army), isTrue);
    });

    test('a blank handover reaches no agency', () {
      expect(alertReaches(alert(agency: ''), army), isFalse);
      expect(alertReaches(alert(agency: null), army), isFalse);
    });

    test('and a liaison is never treated as state command', () {
      // `commandsWholeState` tests `role.contains('HQ')`. No agency code holds
      // those letters today, and relying on that is how one eventually would.
      const hqish = AlertAudience(role: 'HQSH_LIAISON', agency: 'HQSH');
      expect(hqish.commandsWholeState, isFalse);
      expect(alertReaches(alert(), hqish), isFalse);
    });
  });

  group('the role decides the agency, not the badge', () {
    test('reads it off a _LIAISON role', () {
      expect(agencyOfRole('POLICE_LIAISON'), 'POLICE');
      expect(agencyOfRole('police_liaison'), 'POLICE');
      expect(agencyOfRole(' NSCDC_LIAISON '), 'NSCDC');
    });

    test('and nothing else is a liaison', () {
      expect(agencyOfRole('HQ_COMMAND'), isNull);
      expect(agencyOfRole('RESPONDER'), isNull);
      expect(agencyOfRole('LIAISON'), isNull);
      expect(agencyOfRole('_LIAISON'), isNull);
      expect(agencyOfRole(null), isNull);
      expect(agencyOfRole(''), isNull);
    });

    test('fromProfile derives it from the role, not from profiles.agency', () {
      // `profiles.agency` is a decorative badge (T-28); the role is what the
      // RLS helpers key on.
      final a = AlertAudience.fromProfile(
        {'role': 'ARMY_LIAISON', 'agency': 'POLICE', 'geo_lga': 'MANGU'},
        userId: 'x',
      );
      expect(a.agency, 'ARMY');
      expect(a.isLiaison, isTrue);
    });
  });

  group('state command', () {
    test('HQ sees the state', () {
      const hq = AlertAudience(role: 'HQ_COMMAND', geoLga: 'JOS NORTH');
      expect(alertReaches(alert(lga: 'BOKKOS', ward: 'MUSHERE', pu: 'PU-09'), hq), isTrue);
    });

    test('so does an administrator', () {
      const admin = AlertAudience(role: 'ADMIN');
      expect(alertReaches(alert(lga: 'BOKKOS'), admin), isTrue);
    });
  });

  group('a role that has not loaded', () {
    test('still gets the unlocated incidents, because empty reads as ALL CLEAR', () {
      // Deliberately the OPPOSITE of the console's advisory banner (T-34).
      // Withholding an advisory addressed to another agency loses nothing; an
      // empty mission feed on a handset asserts there is no emergency, which is
      // the fault `AlertsFeed.liveness` exists to prevent.
      const resolving = AlertAudience(userId: _me, role: '');
      expect(alertReaches(alert(lga: null, ward: null, pu: null), resolving), isTrue);
    });

    test('and an incident assigned to them by name still arrives', () {
      const resolving = AlertAudience(userId: _me, role: '');
      expect(alertReaches(alert(assignedTo: _me), resolving), isTrue);
    });

    test('but not one scoped to a place it cannot know it is in', () {
      const resolving = AlertAudience(userId: _me, role: '');
      expect(alertReaches(alert(), resolving), isFalse);
    });
  });

  group('handed down to an LGA by name', () {
    // HQ delegates by naming a target LGA in the last escalation_log entry, and
    // `alert_delegated_to_my_lga()` grants it to that LGA's staff whatever the
    // incident's own location says. The old inline filter's comment claimed
    // this — "Show alerts matching LGA, unassigned, or escalated to LGA" — and
    // the code under it read only `geo_lga`.
    Map<String, dynamic> delegated(String toLga, {String lga = 'BOKKOS'}) =>
        <String, dynamic>{
          ...alert(lga: lga, ward: 'MUSHERE', pu: 'PU-03'),
          'escalation_log': [
            {'from_tier': 'WARD', 'to_tier': 'LGA', 'to_lga': 'JOS SOUTH'},
            {'from_tier': 'LGA', 'to_tier': 'LGA', 'to_lga': toLga},
          ],
        };

    const josLga = AlertAudience(role: 'LGA_COMMAND', geoLga: 'JOS NORTH');

    test('reaches the commander it was handed to, across an LGA boundary', () {
      expect(alertReaches(delegated('JOS NORTH'), josLga), isTrue);
    });

    test('and not the commander of the LGA it used to be with', () {
      const josSouth = AlertAudience(role: 'LGA_COMMAND', geoLga: 'JOS SOUTH');
      // Only the LAST entry counts: the log is append-only and an earlier
      // handover has been superseded.
      expect(alertReaches(delegated('JOS NORTH'), josSouth), isFalse);
    });

    test('nor anybody it was not handed to', () {
      const mangu = AlertAudience(role: 'LGA_COMMAND', geoLga: 'MANGU');
      expect(alertReaches(delegated('JOS NORTH'), mangu), isFalse);
    });

    test('an officer with no posting is not handed anything by delegation', () {
      // `geo_lga` is self-writable, and blank must never mean "everywhere".
      expect(delegatedToLga(delegated('JOS NORTH'), null), isFalse);
      expect(delegatedToLga(delegated('JOS NORTH'), '  '), isFalse);
    });

    test('a log with no to_lga delegates to nobody', () {
      expect(delegatedLga(alert()), isNull);
      expect(delegatedLga(<String, dynamic>{...alert(), 'escalation_log': []}), isNull);
      expect(
        delegatedLga(<String, dynamic>{
          ...alert(),
          'escalation_log': [
            {'from_tier': 'UNIT', 'to_tier': 'WARD'},
          ],
        }),
        isNull,
      );
      expect(
        delegatedLga(<String, dynamic>{
          ...alert(),
          'escalation_log': [
            {'to_lga': '   '},
          ],
        }),
        isNull,
      );
    });

    test('a malformed log is not an exception', () {
      expect(delegatedLga(<String, dynamic>{...alert(), 'escalation_log': 'nope'}), isNull);
      expect(delegatedLga(<String, dynamic>{...alert(), 'escalation_log': ['nope']}), isNull);
    });

    test('it does not override the liaison rule', () {
      // A liaison is answered by what was handed to their AGENCY, and nothing
      // else; a target LGA in the log is not a handover to them.
      const army = AlertAudience(role: 'ARMY_LIAISON', agency: 'ARMY', geoLga: 'JOS NORTH');
      expect(alertReaches(delegated('JOS NORTH'), army), isFalse);
    });
  });

  group('an incident with no LGA is unlocated', () {
    // `alert_in_my_area()` tests only the LGA: "Unlocated incidents fail OPEN
    // ... an emergency nobody can see is worse than one seen too widely." This
    // filter used to require all three of LGA, ward and PU to be absent, so an
    // incident with a ward but no LGA was granted by the database to every
    // officer and shown by the handset only to that ward's.
    test('reaches a responder in another ward', () {
      final wardOnly = alert(lga: null, ward: 'PANYAM', pu: 'PU-11');
      expect(alertReaches(wardOnly, jos), isTrue);
    });

    test('reaches a ward commander elsewhere', () {
      const ward = AlertAudience(
        role: 'WARD_COMMAND', geoLga: 'JOS NORTH', geoWard: 'NARAGUTA');
      expect(alertReaches(alert(lga: null, ward: 'PANYAM'), ward), isTrue);
    });

    test('but an outside agency is still answered by the handover', () {
      const army = AlertAudience(role: 'ARMY_LIAISON', agency: 'ARMY');
      expect(alertReaches(alert(lga: null, ward: 'PANYAM'), army), isFalse);
      expect(alertReaches(alert(lga: null, ward: 'PANYAM', agency: 'ARMY'), army), isTrue);
    });
  });

  group('place scoping, as it was', () {
    test('LGA command gets its LGA and anything unlocated', () {
      const lga = AlertAudience(role: 'LGA_COMMAND', geoLga: 'JOS NORTH');
      expect(alertReaches(alert(), lga), isTrue);
      expect(alertReaches(alert(lga: 'MANGU'), lga), isFalse);
      expect(alertReaches(alert(lga: null), lga), isTrue);
    });

    test("LGA command posted to ALL gets everything in the app's own feed", () {
      const everywhere = AlertAudience(role: 'LGA_COMMAND', geoLga: 'ALL');
      expect(alertReaches(alert(lga: 'MANGU'), everywhere), isTrue);
    });

    test('ward command gets its ward, or its LGA', () {
      const ward = AlertAudience(
        role: 'WARD_COMMAND', geoLga: 'JOS NORTH', geoWard: 'NARAGUTA');
      expect(alertReaches(alert(), ward), isTrue);
      expect(alertReaches(alert(ward: 'GANGARE'), ward), isTrue); // same LGA
      expect(alertReaches(alert(lga: 'MANGU', ward: 'PANYAM'), ward), isFalse);
    });

    test('a beat responder gets PU, ward or LGA', () {
      expect(alertReaches(alert(), jos), isTrue);
      expect(alertReaches(alert(pu: 'PU-99'), jos), isTrue); // ward matches
      expect(alertReaches(alert(ward: 'GANGARE', pu: 'PU-99'), jos), isTrue); // LGA
      expect(alertReaches(alert(lga: 'MANGU', ward: 'PANYAM', pu: 'PU-11'), jos), isFalse);
    });

    test('an incident with no jurisdiction at all fails open', () {
      // AlertService writes NULL rather than guess (T-36), and withholding a
      // warning from somebody inside the area costs more than showing it to
      // somebody outside.
      expect(alertReaches(alert(lga: null, ward: null, pu: null), jos), isTrue);
    });

    test('place names are compared on geoKey', () {
      const gindiri = AlertAudience(
        role: 'WARD_COMMAND', geoLga: 'MANGU', geoWard: 'GINDIRI  1');
      // The GPS centroid asset writes the roman numeral; the tactical map
      // writes the digit. Four Mangu wards failed the raw comparison.
      expect(alertReaches(alert(lga: 'MANGU', ward: 'GINDIRI  I'), gindiri), isTrue);
    });
  });
}
