// The two apps must name the same places the same way.
//
// They did not. The console's map named Plateau's 17 LGAs correctly; the
// mobile app's named two of them wrongly:
//
//   'BARIKIN LADI'  — the real LGA is Barkin Ladi (BARKIN, not BARIKIN)
//   'BWALL'         — not an LGA at all. Bwall is a district INSIDE Qua'an
//                     Pan, and Qua'an Pan was missing entirely
//
// The console matches an alert to an LGA with `geoMatches`, which lowercases
// both sides and accepts a substring either way. That absorbs 'JOS NORTH' vs
// 'Jos North' — but 'barikin ladi' and 'barkin ladi' are not substrings of one
// another, and 'bwall' and "qua'an pan" share nothing. So incidents in two of
// Plateau's seventeen LGAs could not be matched to those LGAs at all: not by
// the console's filter, and not by an LGA commander's dashboard scope.
//
// A citizen in Qua'an Pan also could not select their own LGA, because the
// mobile app did not list it.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/constants/tactical_mapping.dart';

void main() {
  // Plateau State's 17 LGAs, as the federal/INEC record spells them. This list
  // is also what geoBoundaries' NGA ADM2 release calls them, which is what
  // public/plateau_boundaries.json is now built from.
  const official = <String>{
    'BARKIN LADI', 'BASSA', 'BOKKOS', 'JOS EAST', 'JOS NORTH', 'JOS SOUTH',
    'KANAM', 'KANKE', 'LANGTANG NORTH', 'LANGTANG SOUTH', 'MANGU', 'MIKANG',
    'PANKSHIN', "QUA'AN PAN", 'RIYOM', 'SHENDAM', 'WASE',
  };

  test('the app knows exactly the 17 real LGAs of Plateau State', () {
    final actual = plateauTacticalMap.map((l) => l.name.toUpperCase()).toSet();

    expect(
      actual.difference(official),
      isEmpty,
      reason: 'the app names an LGA that does not exist — an alert tagged with '
          'it can never be matched to a real jurisdiction',
    );
    expect(
      official.difference(actual),
      isEmpty,
      reason: 'a real LGA is missing — nobody living there can select it',
    );
    expect(actual.length, 17);
  });

  test('BWALL is gone: it is a district, not a local government area', () {
    expect(
      plateauTacticalMap.any((l) => l.name.toUpperCase() == 'BWALL'),
      isFalse,
    );
  });

  test('Barkin Ladi is spelt the way the console and the boundaries spell it',
      () {
    expect(
      plateauTacticalMap.any((l) => l.name.toUpperCase() == 'BARKIN LADI'),
      isTrue,
      reason: "'BARIKIN LADI' does not substring-match 'Barkin Ladi', which is "
          'the only reason the console tolerates a case difference.',
    );
  });

  // The console lowercases and substring-matches both ways. That is generous,
  // but it cannot rescue a name that is simply different — which is exactly
  // what the two failures above were.
  test('every LGA name survives the console-side match against itself', () {
    bool geoMatches(String a, String b) {
      final x = a.trim().toLowerCase();
      final y = b.trim().toLowerCase();
      return x == y || x.contains(y) || y.contains(x);
    }

    for (final lga in plateauTacticalMap) {
      final consoleSpelling = lga.name
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
          .join(' ');
      expect(
        geoMatches(lga.name, consoleSpelling),
        isTrue,
        reason: '${lga.name} would not match the console spelling',
      );
    }
  });
}
