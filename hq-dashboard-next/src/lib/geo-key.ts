/**
 * The form two Plateau place names are compared in.
 *
 * ## Why a name needs a key at all
 *
 * The app resolves an incident's ward from `assets/geo/plateau_wards.json` by
 * nearest centroid and writes that name into `alerts.geo_ward`. Officers are
 * posted from `tactical_mapping.dart`, which this console's map is generated
 * from. Those two files spell four Mangu wards differently:
 *
 *     the app WRITES        an officer is POSTED to
 *     ─────────────────     ───────────────────────
 *     GINDIRI  I            GINDIRI  1
 *     GINDIRI  II           GINDIRI  11
 *     MANGU  I              MANGU  1
 *     MANGU  II             MANGU  11
 *
 * Roman numerals in one file, Arabic in the other. Nothing errors. The ward
 * filter simply selects nothing, and the ward has no supervision.
 *
 * This mirrors `public.geo_key()` — added in
 * 20261009000000_ward_names_compared_by_key.sql — which is what row-level
 * security compares on. The two must agree: if the console showed an officer a
 * ward the database would refuse them, the board would list incidents whose
 * actions all fail.
 */

/**
 * Upper-cased, runs of whitespace collapsed, and a trailing Roman numeral
 * written in the Arabic form the tactical map uses. Empty becomes ''.
 *
 * Only a TRAILING numeral is rewritten, and only when it stands as its own
 * word: "IKOT IDEM" keeps its I, and "GYEL 'A'" is untouched. Longest first,
 * so III does not become "1" followed by "I".
 */
export function geoKey(name: string | null | undefined): string {
  return (name || '')
    .trim()
    .toUpperCase()
    .replace(/\s+/g, ' ')
    .replace(/\sIII$/, ' 111')
    .replace(/\sII$/, ' 11')
    .replace(/\sI$/, ' 1');
}

/**
 * Whether an alert's place name and a filter selection mean the same place.
 *
 * Containment, not equality, and deliberately so: field-entered place names are
 * inconsistent ("Jos North" vs "JOS NORTH LGA"), and under-matching here hides
 * live incidents from the officer responsible for them. The keying above runs
 * first, so the two Gindiris are compared as the map spells them.
 *
 * `geoKey` is applied to BOTH sides. Applying it to one — the alert but not the
 * selection, say — would leave exactly the mismatch this exists to close.
 *
 * An alert with NO geography matches every selection, because '' is contained
 * in everything. That is deliberate fail-open and is asserted in
 * alert-display.test.ts: an unlocated emergency must not vanish because the
 * operator narrowed the view. It matches the same decision in
 * `alert_in_my_area()`, where a NULL `geo_lga` on the incident returns true.
 */
export function geoMatchesKeyed(alertValue: string | undefined | null, target: string): boolean {
  const a = geoKey(alertValue);
  const t = geoKey(target);
  if (a === t) return true;
  // Numbered siblings are DIFFERENT places, and containment cannot tell them
  // apart: 'MANGU 11' contains 'MANGU 1', so a filter on MANGU 1 used to show
  // MANGU 11's incidents as well. Over-showing is the safe direction, but the
  // counters beside the filter are read as per-ward figures.
  const na = a.match(/\s(\d+)$/);
  const nt = t.match(/\s(\d+)$/);
  if (na && nt && na[1] !== nt[1]) return false;
  return a.includes(t) || t.includes(a);
}
