// Two files spell four Mangu wards differently.
//
// This app resolves a ward from assets/geo/plateau_wards.json and writes Roman
// numerals; officers are posted from tactical_mapping.dart, which uses Arabic.
// Every place comparison in the app, the console and row-level security has to
// fold that difference the same way, or an officer is shown work the database
// will refuse them — or, worse, not shown the work in their own ward.
//
// Mirrors hq-dashboard-next/src/lib/geo-key.test.ts and
// scripts/geo_key_behaviour_test.sql.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/geo/geo_key.dart';

void main() {
  group('geoKey', () {
    test('makes the two spellings of the numbered Mangu wards agree', () {
      expect(geoKey('GINDIRI  I'), geoKey('GINDIRI  1'));
      expect(geoKey('GINDIRI  II'), geoKey('GINDIRI  11'));
      expect(geoKey('MANGU  I'), geoKey('MANGU  1'));
      expect(geoKey('MANGU  II'), geoKey('MANGU  11'));
    });

    test('rewrites a trailing III as 111, not as 1 then 11', () {
      expect(geoKey('SOMEWHERE III'), 'SOMEWHERE 111');
    });

    test('folds case and collapses runs of whitespace', () {
      expect(geoKey('  jos   north '), 'JOS NORTH');
    });

    test('is null for a name that is missing, blank or not a string', () {
      expect(geoKey(null), isNull);
      expect(geoKey(''), isNull);
      expect(geoKey('   '), isNull);
      // Rows arrive from PostgREST as Map<String, dynamic>, so a place column
      // can hold anything. A number must not become the string '9'.
      expect(geoKey(9), isNull);
    });

    test('leaves an I that is not a trailing numeral alone', () {
      expect(geoKey('IKOT IDEM'), 'IKOT IDEM');
      expect(geoKey("GYEL 'A'"), "GYEL 'A'");
      expect(geoKey('RIYOM'), 'RIYOM');
    });

    test('keeps genuinely different places apart', () {
      // The direction that matters: a key too aggressive hands a ward
      // commander the ward next door.
      expect(geoKey('GINDIRI  I'), isNot(geoKey('GINDIRI  II')));
      expect(geoKey('MANGU  1'), isNot(geoKey('MANGU  11')));
      // One letter apart is a question about Plateau's geography, not a
      // notation difference. Not folded, on purpose.
      expect(geoKey('KADUN'), isNot(geoKey('KADUNU')));
      expect(geoKey('DAMWAI'), isNot(geoKey('KAMWAI')));
    });

    test('produces the same shape the SQL and TypeScript keys do', () {
      for (final name in ['gindiri  i', 'Mangu  II', ' barakin  ladi ']) {
        final key = geoKey(name)!;
        expect(key, key.toUpperCase());
        expect(key.contains('  '), isFalse);
        expect(key, key.trim());
      }
    });
  });

  group('sameGeo', () {
    test('matches an incident filed in Roman against a posting in Arabic', () {
      // The defect. Before this, a ward commander posted to GINDIRI  1 saw the
      // incident in their own ward only through the LGA fallback beneath the
      // ward test, and a polling-unit responder did not see it at all.
      expect(sameGeo('GINDIRI  I', 'GINDIRI  1'), isTrue);
      expect(sameGeo('KASUWA ALI  I', 'KASUWA ALI  1'), isTrue);
    });

    test('does not match the ward next door', () {
      expect(sameGeo('GINDIRI  I', 'GINDIRI  11'), isFalse);
      expect(sameGeo('NARAGUTA', 'GANGARE'), isFalse);
    });

    test('is false when either side has no place at all', () {
      // Deliberate: what a missing name means is the caller's decision. The
      // mission feed treats a null on the ALERT as "show it", which is why
      // that check stays at the call site and not in here.
      expect(sameGeo(null, 'JOS NORTH'), isFalse);
      expect(sameGeo('JOS NORTH', null), isFalse);
      expect(sameGeo(null, null), isFalse);
      expect(sameGeo('', 'JOS NORTH'), isFalse);
    });

    test('is case- and whitespace-insensitive, as the old comparison was', () {
      expect(sameGeo('jos north', 'JOS NORTH'), isTrue);
      expect(sameGeo('  BOKKOS ', 'BOKKOS'), isTrue);
    });
  });
}
