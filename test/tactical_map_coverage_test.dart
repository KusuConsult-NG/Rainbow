import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/constants/tactical_mapping.dart';

/// Coverage of the tactical map used to be asserted only in a source comment,
/// which was wrong: it claimed 17 LGAs while a name-matching sweep found 16,
/// because one LGA's name is written with double quotes for its apostrophe.
/// These tests make coverage a fact the suite checks rather than a claim.
void main() {
  group('tactical map coverage', () {
    test('every statutory LGA of Plateau State is mapped', () {
      expect(unmappedLgas, isEmpty,
          reason: 'unmapped LGAs: ${unmappedLgas.join(', ')}');
      expect(plateauStatutoryLgas.length, 17);
      expect(plateauTacticalMap.length, plateauStatutoryLgas.length);
    });

    test('every mapped LGA reaches polling-unit level', () {
      expect(unmappedPollingUnitLgas, isEmpty,
          reason: 'LGAs with no polling units: '
              '${unmappedPollingUnitLgas.join(', ')}');
      expect(isTacticalMapComplete, isTrue);
    });

    test('LGA and ward ids are unique', () {
      final lgaIds = plateauTacticalMap.map((j) => j.id).toList();
      expect(lgaIds.toSet().length, lgaIds.length,
          reason: 'duplicate LGA ids in the map');

      // Ward ids repeat across LGAs in the source data, so uniqueness is only
      // asserted within an LGA — that is the scope the dashboard resolves in.
      for (final lga in plateauTacticalMap) {
        final wardIds = lga.wards.map((w) => w.id).toList();
        expect(wardIds.toSet().length, wardIds.length,
            reason: 'duplicate ward ids inside ${lga.name}');
      }
    });

    test('no LGA is named with the old misspelling', () {
      // 'BARIKIN LADI' did not match the name the dashboard filtered on, so
      // alerts from that LGA could not be found by filtering for it.
      final names = plateauTacticalMap.map((j) => j.name.toUpperCase());
      expect(names, contains('BARKIN LADI'));
      expect(names, isNot(contains('BARIKIN LADI')));
    });

    test('every ward belongs to an LGA and has a name', () {
      for (final lga in plateauTacticalMap) {
        expect(lga.name.trim(), isNotEmpty);
        expect(lga.wards, isNotEmpty, reason: '${lga.name} has no wards');
        for (final ward in lga.wards) {
          expect(ward.name.trim(), isNotEmpty,
              reason: 'unnamed ward in ${lga.name}');
        }
      }
    });

    test('the coverage summary reports real totals', () {
      final summary = tacticalMapCoverageSummary();
      final wards =
          plateauTacticalMap.fold<int>(0, (n, j) => n + j.wards.length);
      expect(summary, contains('17/17 LGAs'));
      expect(summary, contains('$wards wards'));
      // A complete map has no gap clause appended.
      expect(summary, isNot(contains('unmapped')));
    });
  });
}
