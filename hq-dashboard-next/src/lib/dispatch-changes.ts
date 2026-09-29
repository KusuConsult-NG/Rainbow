/**
 * What changed when an incident was reassigned.
 *
 * ## The gap this closes
 *
 * `dispatchAlert` writes `assigned_responders` by REPLACING it, and notified
 * only the uids it was given. So reassigning an incident removed officers from
 * it silently: the incident simply vanished from their list — the responder app
 * matches on `assigned_responders` — and nothing told them to stand down.
 *
 * For a kidnapping with units already moving, an officer who is still driving
 * to a scene they have been taken off is a safety problem, not an untidiness
 * one. And the commander gets no record that anyone was stood down, because the
 * only thing written was the new team.
 *
 * These are pure set operations, which is exactly why they are worth having
 * separately: the interesting cases are the empty ones, and they are easy to
 * get wrong in the middle of an update that also writes six other fields.
 */

/** Everyone on the incident before and after a reassignment. */
export interface TeamChange {
  /** Officers newly put on the incident. They get a dispatch. */
  added: string[];
  /** Officers taken off it. They get a stand-down. */
  removed: string[];
  /** Officers on it before and after. They are not notified again. */
  unchanged: string[];
}

function clean(uids: readonly (string | null | undefined)[] | null | undefined): string[] {
  if (!uids) return [];
  const seen = new Set<string>();
  for (const u of uids) {
    const v = (u ?? '').trim();
    if (v) seen.add(v);
  }
  return [...seen];
}

/**
 * Who joined, who left, who stayed.
 *
 * Duplicates and blanks are dropped on both sides: `assigned_responders` is a
 * free TEXT[] and an empty string in it must not become a notification to
 * nobody, or worse, an officer counted as removed on every dispatch.
 */
export function teamChange(
  previous: readonly (string | null | undefined)[] | null | undefined,
  next: readonly (string | null | undefined)[] | null | undefined,
): TeamChange {
  const before = clean(previous);
  const after = clean(next);
  const afterSet = new Set(after);
  const beforeSet = new Set(before);

  return {
    added: after.filter(u => !beforeSet.has(u)),
    removed: before.filter(u => !afterSet.has(u)),
    unchanged: after.filter(u => beforeSet.has(u)),
  };
}

/**
 * The officers who must be told they are off this incident.
 *
 * Kept as its own name because this is the list that was missing entirely, and
 * a caller reading `teamChange(...).removed` inline is easy to drop in a later
 * edit.
 */
export function standDownList(
  previous: readonly (string | null | undefined)[] | null | undefined,
  next: readonly (string | null | undefined)[] | null | undefined,
): string[] {
  return teamChange(previous, next).removed;
}

/**
 * The line recorded on the incident when a team changes.
 *
 * Dispatch already writes a note; a reassignment wrote nothing at all, so the
 * only trace that officers had been pulled off was their absence from a column.
 * Returns null when nobody was removed, so the caller appends nothing rather
 * than an empty entry.
 */
export function describeStandDown(
  removedNames: readonly string[],
  by: string,
): string | null {
  const names = removedNames.map(n => n.trim()).filter(Boolean);
  if (names.length === 0) return null;
  const who = names.length === 1 ? names[0] : `${names.length} officers: ${names.join(', ')}`;
  return `[STOOD DOWN] ${who} removed from this incident by ${by}`;
}
