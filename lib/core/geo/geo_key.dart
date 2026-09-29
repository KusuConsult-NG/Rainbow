/// The form two Plateau place names are compared in.
///
/// ## Why a name needs a key at all
///
/// This app resolves an incident's ward from `assets/geo/plateau_wards.json` by
/// nearest centroid and writes that name into `alerts.geo_ward`. Officers are
/// posted from `tactical_mapping.dart`, which the HQ console's map is generated
/// from. Those two files spell four Mangu wards differently:
///
///     this app WRITES       an officer is POSTED to
///     ─────────────────     ───────────────────────
///     GINDIRI  I            GINDIRI  1
///     GINDIRI  II           GINDIRI  11
///     MANGU  I              MANGU  1
///     MANGU  II             MANGU  11
///
/// Roman numerals in one file, Arabic in the other. Nothing errors. A ward
/// commander's mission feed simply does not contain the incidents in their own
/// ward — on this screen it was masked by the LGA fallback beneath the ward
/// test, so they saw the incident for the wrong reason and a polling-unit
/// responder saw nothing at all.
///
/// This mirrors `public.geo_key()` (migration
/// 20261009000000_ward_names_compared_by_key.sql), which row-level security
/// compares on, and `geoKey` in the console's `src/lib/geo-key.ts`. All three
/// must agree: a feed that showed an officer an incident the database refuses
/// them is a row of buttons that all fail.
library;

/// Upper-cased, runs of whitespace collapsed, and a trailing Roman numeral
/// written in the Arabic form the tactical map uses.
///
/// Returns null for a name that is missing or blank, so "no posting" stays
/// distinguishable from "some posting" — `alert_in_my_area()` turns on exactly
/// that distinction, and a blank posting must be the weakest, never the widest.
///
/// Only a TRAILING numeral standing as its own word is rewritten: `IKOT IDEM`
/// keeps its I and `GYEL 'A'` is untouched. Longest numeral first, so III does
/// not become 1 followed by 11.
String? geoKey(Object? name) {
  if (name is! String) return null;
  final squashed = name.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  if (squashed.isEmpty) return null;
  return squashed
      .replaceFirst(RegExp(r'\sIII$'), ' 111')
      .replaceFirst(RegExp(r'\sII$'), ' 11')
      .replaceFirst(RegExp(r'\sI$'), ' 1');
}

/// Whether two place names mean the same place.
///
/// Null on either side is NOT a match: callers decide what a missing name
/// means, and on this screen a missing one usually means "show it" — an
/// unlocated emergency must not vanish because an officer has a posting. That
/// decision belongs at the call site, not buried in here.
bool sameGeo(Object? a, Object? b) {
  final ka = geoKey(a);
  final kb = geoKey(b);
  return ka != null && kb != null && ka == kb;
}
