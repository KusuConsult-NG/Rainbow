// What a screen may say about where something is.
//
// `AlertService` writes NULL rather than guess a jurisdiction, and the
// responder feed filter treats a null LGA as reaching everybody. The screen
// between them printed `PLATEAU · HQ · UNIT` — and the dispatch roster printed
// `JOS`, which is not one of Plateau's seventeen LGAs.
//
// Every expectation here fails against those two inline strings.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/place_label.dart';

void main() {
  group('an incident place', () {
    test('reads all three when all three are recorded', () {
      expect(
        incidentPlace({'geo_lga': 'JOS NORTH', 'geo_ward': 'NARAGUTA', 'geo_pu': 'PU 014'}),
        'JOS NORTH · NARAGUTA · PU 014',
      );
    });

    test('drops the polling unit rather than inventing one', () {
      // The ordinary case for a GPS incident: there is no polling unit from
      // coordinates and there cannot be. This used to end in `· UNIT`.
      expect(
        incidentPlace({'geo_lga': 'JOS NORTH', 'geo_ward': 'NARAGUTA', 'geo_pu': null}),
        'JOS NORTH · NARAGUTA',
      );
    });

    test('drops the ward too', () {
      expect(incidentPlace({'geo_lga': 'BOKKOS'}), 'BOKKOS');
    });

    test('says the jurisdiction is unresolved rather than naming the state', () {
      // What the service writes when the coordinates do not resolve to a
      // Plateau LGA. This used to read `PLATEAU · HQ · UNIT`: three place
      // names, none measured, on the line a responder uses to decide where to
      // go.
      expect(incidentPlace({}), 'JURISDICTION NOT RESOLVED');
      expect(
        incidentPlace({'geo_lga': null, 'geo_ward': null, 'geo_pu': null}),
        'JURISDICTION NOT RESOLVED',
      );
    });

    test('treats a blank column as not recorded, because a reader cannot tell', () {
      expect(incidentPlace({'geo_lga': '', 'geo_ward': '   '}), 'JURISDICTION NOT RESOLVED');
      expect(incidentPlace({'geo_lga': '  MANGU  ', 'geo_ward': ''}), 'MANGU');
    });

    test('never names a real place that was not recorded', () {
      // The inline version's three fallbacks, as a property: whatever is
      // missing, nothing appears that is not in the row.
      const invented = ['PLATEAU', 'HQ', 'UNIT', 'JOS'];
      for (final row in <Map<String, dynamic>>[
        {},
        {'geo_lga': 'JOS NORTH'},
        {'geo_ward': 'NARAGUTA'},
        {'geo_pu': 'PU 014'},
        {'geo_lga': 'JOS NORTH', 'geo_pu': 'PU 014'},
      ]) {
        final label = incidentPlace(row);
        for (final word in invented) {
          if (row.values.any((v) => v is String && v.contains(word))) continue;
          expect(label.contains(word), isFalse, reason: '$row produced "$label"');
        }
      }
    });
  });

  group('a responder posting', () {
    test('reads the role and the LGA when both are recorded', () {
      expect(
        responderPosting({'role': 'LGA_COMMAND', 'geo_lga': 'JOS SOUTH'}),
        'Role: LGA_COMMAND · JOS SOUTH',
      );
    });

    test('says no LGA is recorded rather than JOS', () {
      // Reachable for statewide command, which reaches officers regardless of
      // posting — the one account that dispatches across all seventeen LGAs.
      // `JOS` is not one of them.
      expect(
        responderPosting({'role': 'RESPONDER', 'geo_lga': null}),
        'Role: RESPONDER · NO LGA RECORDED',
      );
    });

    test('does not promote an officer with no role to RESPONDER', () {
      // `assignableResponders` drops a row with no role, so this should not
      // arrive — and if it does, the list must not assign it a tier.
      expect(
        responderPosting({'role': null, 'geo_lga': 'MANGU'}),
        'Role: ROLE NOT SET · MANGU',
      );
    });

    test('reports the two independently', () {
      expect(
        responderPosting({}),
        'Role: ROLE NOT SET · NO LGA RECORDED',
      );
    });
  });
}
