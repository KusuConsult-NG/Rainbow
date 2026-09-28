/**
 * Which officers a commander may actually send to an incident.
 *
 * ## What was wrong
 *
 * Both pickers — the console's SELECT TACTICAL RESPONDER TEAM and the
 * responder app's `_loadResponders()` — built their list by taking every
 * profile and keeping `role !== 'CITIZEN'`. The app's query even selected
 * `geo_lga` and `geo_ward` and then never looked at them.
 *
 * So a ward commander in Jos North was offered, and could dispatch, an officer
 * posted in Mangu — 80km away and in nobody's chain of command. The officer
 * would get a push notification for an incident their commander knows nothing
 * about, and the commander who does own them would never learn they had been
 * sent.
 *
 * ## The rule
 *
 * An officer is assignable when they are inside the dispatcher's command:
 *
 *   HQ / ADMIN   anyone
 *   LGA          officers posted to their LGA
 *   WARD         officers posted to their ward
 *   UNIT         nobody — a polling-unit officer IS the field unit, and
 *                `canDispatchFrom` already refuses them the control
 *
 * This deliberately mirrors `alert_in_my_area()` in
 * 20261006000000_alerts_scoped_to_posting.sql, one axis over: that decides
 * which incidents a posting reaches, this decides which officers it reaches.
 * Keeping the two shaped the same is what makes them checkable against each
 * other — an officer you may send is an officer whose work you may see.
 *
 * Hiding a name is not access control; the database decides. But offering a
 * name that leads to a dispatch nobody downstream expects is its own defect.
 */

/** The parts of a profile this rule reads. */
export interface Posting {
  role?: string | null;
  geo_lga?: string | null;
  geo_ward?: string | null;
  geo_pu?: string | null;
}

/** Compare postings the way the database does: trimmed, case-insensitively. */
function norm(value: string | null | undefined): string | null {
  const v = (value ?? '').trim().toUpperCase();
  return v.length ? v : null;
}

/** Whether this account commands the whole state. */
export function commandsWholeState(role: string | null | undefined): boolean {
  const r = norm(role) ?? '';
  return r === 'HQ_COMMAND' || r === 'HQ_OFFICER' || r === 'ADMIN';
}

/**
 * Whether `officer` is inside `commander`'s command.
 *
 * A commander with no posting of their own reaches nobody. `geo_lga` is
 * self-writable — only `role` is guarded — so an empty posting must be the
 * weakest, never a way to reach the whole state. The same reasoning as the
 * database policy.
 */
export function isUnderCommand(officer: Posting, commander: Posting): boolean {
  if (commandsWholeState(commander.role)) return true;

  const myLga = norm(commander.geo_lga);
  if (!myLga) return false;
  if (norm(officer.geo_lga) !== myLga) return false;

  const role = norm(commander.role) ?? '';

  if (role.startsWith('WARD')) {
    const myWard = norm(commander.geo_ward);
    return myWard !== null && norm(officer.geo_ward) === myWard;
  }

  // A polling-unit officer is the field unit, not a dispatcher. canDispatchFrom
  // already refuses them the control; this makes the list agree with it rather
  // than offering names behind a button they do not have.
  if (role.startsWith('UNIT') || role.startsWith('POLLING')) return false;

  // LGA command, and anything else with a posting: their LGA.
  return true;
}

/**
 * The officers this commander may send, from every profile loaded.
 *
 * Citizens are never assignable, and neither is the dispatcher themselves —
 * self-dispatch is what ENGAGE is for, and offering it here produced an
 * incident assigned to the person who assigned it.
 */
export function assignableResponders<T extends Posting & { id?: string }>(
  officers: T[],
  commander: Posting & { id?: string },
): T[] {
  return officers.filter(o => {
    if (!o) return false;
    if (norm(o.role) === 'CITIZEN' || !norm(o.role)) return false;
    if (o.id && commander.id && o.id === commander.id) return false;
    return isUnderCommand(o, commander);
  });
}

/**
 * What to say when the list is empty.
 *
 * An empty picker with no explanation reads as "the system is broken" during
 * an emergency. It has two quite different causes and the dispatcher needs to
 * know which: nobody is posted to their command, or they have no posting of
 * their own and so command nobody.
 */
export function emptyRosterReason(commander: Posting): string {
  if (commandsWholeState(commander.role)) {
    return 'No officers are registered.';
  }
  if (!norm(commander.geo_lga)) {
    return 'Your account has no posting, so it commands no officers. Ask HQ to set your LGA.';
  }
  const where = norm(commander.role)?.startsWith('WARD')
    ? norm(commander.geo_ward) ?? norm(commander.geo_lga)
    : norm(commander.geo_lga);
  return `No officers are posted to ${where}. Escalate to have one sent.`;
}
