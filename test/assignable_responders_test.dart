// Which officers a commander may send.
//
// The picker offered every profile in the state with a role that was not
// CITIZEN, so a ward commander in Jos North could dispatch an officer posted in
// Mangu. These are the same cases the console's assignable-responders.test.ts
// asserts, deliberately: two pickers implementing one rule have to be checkable
// against each other.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/assignable_responders.dart';

void main() {
  const hq = <String, dynamic>{'id': 'hq', 'role': 'HQ_COMMAND'};
  const lgaJos = <String, dynamic>{
    'id': 'lga-jos',
    'role': 'LGA_COMMAND',
    'geo_lga': 'JOS NORTH',
  };
  const wardNaraguta = <String, dynamic>{
    'id': 'ward-nar',
    'role': 'WARD_COMMAND',
    'geo_lga': 'JOS NORTH',
    'geo_ward': 'NARAGUTA',
  };

  const officerNaraguta = <String, dynamic>{
    'id': 'o1',
    'role': 'RESPONDER',
    'geo_lga': 'JOS NORTH',
    'geo_ward': 'NARAGUTA',
    'geo_pu': 'PU-01',
  };
  const officerGangare = <String, dynamic>{
    'id': 'o2',
    'role': 'RESPONDER',
    'geo_lga': 'JOS NORTH',
    'geo_ward': 'GANGARE',
    'geo_pu': 'PU-09',
  };
  const officerMangu = <String, dynamic>{
    'id': 'o3',
    'role': 'RESPONDER',
    'geo_lga': 'MANGU',
    'geo_ward': 'PANYAM',
    'geo_pu': 'PU-11',
  };
  const citizen = <String, dynamic>{
    'id': 'c1',
    'role': 'CITIZEN',
    'geo_lga': 'JOS NORTH',
    'geo_ward': 'NARAGUTA',
  };

  final everyone = <Map<String, dynamic>>[
    officerNaraguta,
    officerGangare,
    officerMangu,
    citizen,
  ];

  List<String> idsOf(List<Map<String, dynamic>> rows) =>
      rows.map((r) => r['id'] as String).toList();

  group('who commands the whole state', () {
    test('is HQ and administrators, and nobody else', () {
      expect(commandsWholeState('HQ_COMMAND'), isTrue);
      expect(commandsWholeState('ADMIN'), isTrue);
      expect(commandsWholeState('LGA_COMMAND'), isFalse);
      expect(commandsWholeState(null), isFalse);
    });
  });

  group('a ward commander', () {
    test('may send officers in their own ward', () {
      expect(isUnderCommand(officerNaraguta, wardNaraguta), isTrue);
    });

    test('may not send an officer in another ward of their own LGA', () {
      expect(isUnderCommand(officerGangare, wardNaraguta), isFalse);
    });

    test('may not send an officer in another LGA', () {
      // What the picker allowed. The officer would be dispatched to an incident
      // their own commander knows nothing about.
      expect(isUnderCommand(officerMangu, wardNaraguta), isFalse);
    });

    test('is offered exactly their ward', () {
      expect(idsOf(assignableResponders(everyone, wardNaraguta)), ['o1']);
    });
  });

  group('an LGA commander', () {
    test('may send anyone in their LGA, across wards', () {
      expect(idsOf(assignableResponders(everyone, lgaJos)), ['o1', 'o2']);
    });

    test('stops at the LGA boundary', () {
      expect(isUnderCommand(officerMangu, lgaJos), isFalse);
    });
  });

  group('HQ', () {
    test('may send anyone, anywhere', () {
      expect(idsOf(assignableResponders(everyone, hq)), ['o1', 'o2', 'o3']);
    });
  });

  group('a polling-unit officer', () {
    test('commands nobody, because they are the field unit', () {
      const unit = <String, dynamic>{
        'role': 'UNIT_COMMAND',
        'geo_lga': 'JOS NORTH',
        'geo_ward': 'NARAGUTA',
        'geo_pu': 'PU-01',
      };
      expect(assignableResponders(everyone, unit), isEmpty);
    });
  });

  group('an account with no posting', () {
    test('commands nobody rather than everybody', () {
      // geo_lga is self-writable, so an empty posting must be the weakest and
      // never a way to reach the state.
      const unposted = <String, dynamic>{'role': 'WARD_COMMAND'};
      expect(assignableResponders(everyone, unposted), isEmpty);
    });
  });

  group('who is never offered', () {
    test('citizens', () {
      expect(assignableResponders(<Map<String, dynamic>>[citizen], hq), isEmpty);
    });

    test('the dispatcher themselves', () {
      // Self-dispatch is what ENGAGE is for. Offering it here produced an
      // incident assigned to the person who assigned it.
      const self = <String, dynamic>{
        'id': 'lga-jos',
        'role': 'LGA_COMMAND',
        'geo_lga': 'JOS NORTH',
      };
      expect(
        idsOf(assignableResponders(
          <Map<String, dynamic>>[self, officerNaraguta],
          lgaJos,
        )),
        ['o1'],
      );
    });
  });

  group('comparing postings', () {
    test('ignores case and stray spacing, as the database does', () {
      expect(
        isUnderCommand(
          const <String, dynamic>{
            'role': 'RESPONDER',
            'geo_lga': ' jos north ',
            'geo_ward': 'naraguta',
          },
          wardNaraguta,
        ),
        isTrue,
      );
    });
  });

  group('when the list comes back empty', () {
    test('an unposted account is told why, not just that it is empty', () {
      expect(
        emptyRosterReason(const <String, dynamic>{'role': 'WARD_COMMAND'}),
        contains('no posting'),
      );
    });

    test('a posted commander is told where nobody is', () {
      expect(emptyRosterReason(wardNaraguta), contains('NARAGUTA'));
      expect(emptyRosterReason(lgaJos), contains('JOS NORTH'));
    });
  });
}
