/**
 * Places as they read on a screen somebody acts on.
 *
 * The console twin of `lib/services/place_label.dart`, and the two must agree
 * about what a missing jurisdiction means or the same incident reads one way on
 * a handset and another at HQ.
 *
 * ## The defect this closes
 *
 * `AlertService` refuses to guess where an incident happened — "submitting
 * without jurisdiction rather than guessing one" — and writes NULL. The
 * console's incident dossier then rendered:
 *
 *     LGA / Sector: {selectedReport.geo_lga || 'STATE HQ'}
 *     {selectedReport.geo_ward && ( ... )}
 *
 * Three lines apart: an absent ward is DROPPED and an absent LGA is given the
 * name of a place. An operator reading "LGA / Sector: STATE HQ" has no way to
 * tell that from an incident measured at the state headquarters.
 *
 * The same pattern, in three more places, each with the honest wording already
 * beside it:
 *
 *   * the map card's `PU: {a.geo_pu || 'SECTOR HQ'}` — and `geo_pu` is null on
 *     essentially every GPS-originated incident, because there is no polling
 *     unit from coordinates and there cannot be, so nearly every card in the
 *     feed asserted a polling unit;
 *   * the AI triage prompt's `- LGA: ${a.geo_lga || 'STATE HQ'}`, where the
 *     Type, Ward and Description lines immediately around it all say `N/A` or
 *     "No description provided". The model's priority and unit recommendation
 *     were conditioned on a location nobody measured;
 *   * the staff directory's `Sector: {s.geo_lga || 'STATEWIDE HQ'}`, beside
 *     `District: {s.geo_ward || 'N/A'}` on the same line — asserting statewide
 *     authority for an officer whose posting is simply blank.
 *
 * Two uses of the same `||` are NOT this defect and are deliberately left
 * alone: `alert-display.ts` builds a grouping key from
 * `geo_lga || 'STATE'`, which is a sentinel that is never displayed, and
 * `escalateAlert(id, geo_lga || 'ALL')` escalates an unlocated incident to
 * everybody, which is the documented fail-open on place. The rule is about what
 * a screen SAYS, not about every fallback.
 */

/** A value counts as recorded only if it is a non-blank string. */
function recorded(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text === '' ? null : text;
}

/**
 * The segments that are actually recorded, joined; `whenNone` when none is.
 *
 * `null`, `''` and whitespace all mean "not recorded" — a column can hold any
 * of the three and a reader cannot tell them apart.
 */
export function knownSegments(
  segments: readonly unknown[],
  whenNone: string,
  separator = ' · ',
): string {
  const known = segments.map(recorded).filter((s): s is string => s !== null);
  return known.length === 0 ? whenNone : known.join(separator);
}

/** What a place field says when it is blank. Never the name of a place. */
export const NOT_RECORDED = {
  jurisdiction: 'JURISDICTION NOT RESOLVED',
  lga: 'LGA NOT RECORDED',
  ward: 'WARD NOT RECORDED',
  pu: 'PU NOT RECORDED',
  /** For a prompt or a log line, where the surrounding lines say N/A. */
  field: 'N/A',
} as const;

/** One place field on its own, for a labelled row. */
export function placeField(
  value: unknown,
  kind: keyof typeof NOT_RECORDED = 'field',
): string {
  return recorded(value) ?? NOT_RECORDED[kind];
}

/**
 * Where an incident is, as one line.
 *
 * A missing segment is dropped rather than filled, so `JOS NORTH · NARAGUTA`
 * rather than `JOS NORTH · NARAGUTA · SECTOR HQ`. When none of the three is
 * recorded it says so — the position is not lost by this, because the
 * coordinates are what the map plots and they are measured. It is the
 * jurisdiction that is unknown.
 */
export function incidentPlace(alert: {
  geo_lga?: unknown;
  geo_ward?: unknown;
  geo_pu?: unknown;
}): string {
  return knownSegments(
    [alert.geo_lga, alert.geo_ward, alert.geo_pu],
    NOT_RECORDED.jurisdiction,
  );
}
