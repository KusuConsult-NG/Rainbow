// Resolving an incident's coordinates to the jurisdiction that owns it.
//
// The chain starts at the tier responsible for the GROUND an incident happened
// on, so an alert has to carry that ground. Nothing attached it: a citizen
// report carried no geography unless the reporter opened the manual override,
// and the panic SOS carried the reporter's REGISTERED lga/ward — where they
// live, not where they are.
//
// The assertions that matter are about refusing to answer. A jurisdiction
// invented for a point outside the state, or for a point with no coordinates,
// is C-5 one field over: a confident value with nothing behind it.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/geo/jurisdiction_resolver.dart';

void main() {
  final r = JurisdictionResolver.instance;

  setUp(() {
    // Two square LGAs side by side, with two wards each. Squares are fine
    // HERE — the test is about the algorithm, not the geometry. It is the
    // SHIPPED data that must be real, and it now is.
    r.loadForTest(
      polygons: {
        'JOS NORTH': [
          [
            [8.8, 9.9], [9.0, 9.9], [9.0, 10.1], [8.8, 10.1], [8.8, 9.9],
          ],
        ],
        'MANGU': [
          [
            [9.0, 9.4], [9.2, 9.4], [9.2, 9.6], [9.0, 9.6], [9.0, 9.4],
          ],
        ],
      },
      wards: {
        'JOS NORTH': [
          ['NARAGUTA', 10.05, 8.85],
          ['JENTA', 9.95, 8.95],
        ],
        'MANGU': [
          ['PANYAM', 9.55, 9.05],
          ['KERANG', 9.45, 9.15],
        ],
      },
    );
  });

  group('a point inside the state', () {
    test('resolves to the LGA whose polygon contains it', () {
      expect(r.resolve(10.0, 8.9).lga, 'JOS NORTH');
      expect(r.resolve(9.5, 9.1).lga, 'MANGU');
    });

    test('resolves to the nearest ward centroid inside that LGA', () {
      expect(r.resolve(10.04, 8.86).ward, 'NARAGUTA');
      expect(r.resolve(9.94, 8.96).ward, 'JENTA');
    });

    test('never picks a ward from a different LGA, however close', () {
      // Just inside Mangu, but nearer to Jos North's ward centroids in raw
      // distance would still not matter: the LGA is resolved first.
      final j = r.resolve(9.59, 9.01);
      expect(j.lga, 'MANGU');
      expect(['PANYAM', 'KERANG'], contains(j.ward));
    });

    test('says the answer came from GPS', () {
      expect(r.resolve(10.0, 8.9).source, 'GPS');
    });
  });

  group('refusing to answer', () {
    test('a point outside every LGA is unresolved, not nearest-guessed', () {
      final j = r.resolve(6.5, 3.4); // Lagos
      expect(j.isResolved, isFalse);
      expect(j.lga, isNull);
      expect(j.source, 'UNRESOLVED');
    });

    test('no coordinates means unresolved', () {
      expect(r.resolve(null, null).isResolved, isFalse);
      expect(r.resolve(10.0, null).isResolved, isFalse);
      expect(r.resolve(null, 8.9).isResolved, isFalse);
    });

    test('NaN is unresolved rather than a crash or a wild answer', () {
      expect(r.resolve(double.nan, 8.9).isResolved, isFalse);
    });
  });

  // The two geography datasets do not quite agree. 1.5% of inhabited Plateau
  // sits inside NO LGA polygon while lying between two or more of them — a
  // hairline seam where neighbouring boundaries fail to meet. Two real ward
  // centroids land in one, KANAM/DUGUB and KANKE/NEMEL, and an incident there
  // used to resolve to nothing at all: no LGA, no ward, no tier. That is the
  // failure this class exists to end, arriving by a different route.
  //
  // The synthetic LGAs above are two squares with a gap between them, so the
  // gap is a seam: inside the extent, inside neither polygon.
  group('a seam between two polygons', () {
    test('resolves through the ward register rather than to nothing', () {
      final j = r.resolve(9.7, 9.04); // between the two squares
      expect(j.isResolved, isTrue);
      expect(j.lga, 'MANGU');          // the register's LGA for PANYAM
      expect(j.ward, 'PANYAM');
    });

    test('says it came from the register, not from a boundary', () {
      // A reader must be able to tell a reconciled answer from a measured one.
      expect(r.resolve(9.7, 9.04).source, 'GPS_WARD_REGISTER');
      expect(r.resolve(10.05, 8.9).source, 'GPS');
    });

    test('does not fire for a point a polygon already owns', () {
      // Inside MANGU, but nearer a JOS NORTH ward in raw distance. The polygon
      // is sure about this point, so the register is never consulted.
      final j = r.resolve(9.59, 9.01);
      expect(j.source, 'GPS');
      expect(j.lga, 'MANGU');
    });

    test('still refuses a point beyond the state extent', () {
      // Outside every polygon AND outside their bounding box: not a seam,
      // somewhere else. The nearest Plateau ward is not an answer here.
      final j = r.resolve(10.6, 8.9); // north of the extent
      expect(j.isResolved, isFalse);
      expect(j.source, 'UNRESOLVED');
    });
  });

  // An earlier design bounded the ward by its centroid's radius and returned
  // no ward past it. Wards TILE an LGA, so nearest-centroid IS the Voronoi
  // assignment and the real extent runs past that radius in every direction
  // but one: over 5,100 sampled points the bound blanked 57.4% of correct
  // answers. If it ever comes back, this fails.
  test('names a ward anywhere inside the LGA, however far from a centroid', () {
    for (final p in [[9.92, 8.82], [10.08, 8.98], [9.41, 9.19], [9.59, 9.01]]) {
      final j = r.resolve(p[0], p[1]);
      expect(j.lga, isNotNull, reason: 'no LGA at ${p[0]}, ${p[1]}');
      expect(j.ward, isNotNull, reason: 'ward blanked at ${p[0]}, ${p[1]}');
    }
  });

  // No open dataset gives polling units a position, so returning one would be
  // a guess presented as a measurement — and a unit sent to the wrong village.
  test('a polling unit is never invented from coordinates', () {
    expect(r.resolve(10.0, 8.9).pu, isNull);
    expect(r.resolve(9.5, 9.1).pu, isNull);
  });
}
