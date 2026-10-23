/**
 * Who an automatic escalation has to reach.
 *
 * The timeout job moves an incident one rung up the chain and queues a notice
 * in `notification_outbox`. This decides whose phone that notice is for.
 *
 * ## Why it is a function and not a query written inline in the route
 *
 * Getting this wrong is silent in both directions and neither is discoverable
 * from the outside:
 *
 *   * Too narrow, and an incident climbs to a tier where nobody is told. That
 *     is the state the outbox was built to end, so a worker that reproduces it
 *     one layer up would be worse than no worker — the row would be marked
 *     delivered.
 *   * Too wide, and every escalation in Plateau wakes every commander in the
 *     state. People turn off notifications they do not need, and then miss the
 *     one they do.
 *
 * The rule matches `alert_in_my_area()` in the database: the tier that now owns
 * the incident, in the place the incident is. An officer who would be refused
 * the row by row-level security must not be sent a push about it.
 */

import { rolesForTier as canonicalRolesForTier } from './command-roles';

/** The tiers an incident can be assigned to, bottom to top. */
export const TIERS = ['UNIT', 'WARD', 'LGA', 'HQ'] as const;
export type Tier = (typeof TIERS)[number];

/** A queued notice, as the outbox stores it. */
export interface OutboxRow {
  id: number;
  alert_id: string | null;
  kind: string;
  payload: {
    alert_id?: string;
    from_tier?: string;
    to_tier?: string;
    geo_lga?: string | null;
    geo_ward?: string | null;
    geo_pu?: string | null;
    severity?: string | null;
    reason?: string;
    /** The reporting category, on a NEW_INCIDENT notice. */
    type?: string | null;
  };
}

/** A timeout moved an incident up the chain. */
export const TIER_ESCALATION = 'TIER_ESCALATION';

/**
 * An incident was just reported.
 *
 * Queued by `queue_new_incident_notice()` on INSERT. Nothing queued anything
 * on insert before: the only paths to a phone were a human pressing DISPATCH
 * and the timeout two minutes later, so the system announced that it had given
 * up waiting for you and not that the emergency had arrived.
 */
export const NEW_INCIDENT = 'NEW_INCIDENT';

/** The profile fields this rule reads. */
export interface OfficerRow {
  id: string;
  role?: string | null;
  geo_lga?: string | null;
  geo_ward?: string | null;
  geo_pu?: string | null;
  onesignal_player_id?: string | null;
}

function norm(v: string | null | undefined): string | null {
  const s = (v ?? '').trim().toUpperCase();
  return s.length ? s : null;
}

/**
 * The roles that hold a given tier.
 *
 * Both the `_COMMAND` and `_OFFICER` forms: an escalation is not addressed to
 * one person, it is addressed to a desk, and at two in the morning the
 * commander is not necessarily the one awake.
 */
export function rolesForTier(tier: string | null | undefined): string[] {
  // WAS FOUR LISTS WRITTEN OUT HERE, AND THIS IS WHO GETS TOLD.
  //
  // WARD returned ['WARD_COMMAND','WARD_OFFICER'] and the production project's
  // ward officers are spelled WARD_COMMANDER; LGA the same; HQ returned
  // ['HQ_COMMAND','HQ_OFFICER','ADMIN'] against four STATE_COMMANDER accounts.
  // So a ward escalation was addressed to nobody, an LGA escalation to nobody,
  // and an HQ escalation to the single HQ_COMMAND account —
  // `deliverTierEscalation` throws "no reachable officer at that tier" on an
  // empty list, so those notices could never be delivered at all. UNIT worked,
  // because somebody hit this for that one rung and added
  // POLLING_UNIT_OFFICER to that one list.
  //
  // Derived from the role-to-rung map now, so it cannot disagree with the rung
  // the app shows that same officer. T-97.
  return canonicalRolesForTier(tier);
}

/**
 * Whether this officer should be told about this escalation.
 *
 * HQ is statewide and is not filtered by geography — it is the rung whose job
 * is everything. Every other tier is filtered to the place the incident is, the
 * same way `alert_in_my_area()` filters what they can read.
 *
 * An incident with NO location goes to the tier regardless of posting: those
 * are the SOS reports that arrived without a GPS fix, and they are exactly the
 * ones that must not fall silently between desks.
 */
export function officerShouldHear(officer: OfficerRow, row: OutboxRow): boolean {
  const roles = rolesToNotify(row);
  if (roles.length === 0) return false;
  if (!roles.includes(norm(officer.role) ?? '')) return false;

  if (norm(row.payload.to_tier) === 'HQ') return true;

  const incidentLga = norm(row.payload.geo_lga);
  if (!incidentLga) return true;
  if (norm(officer.geo_lga) !== incidentLga) return false;

  if (norm(row.payload.to_tier) === 'WARD') {
    const ward = norm(row.payload.geo_ward);
    return !ward || norm(officer.geo_ward) === ward;
  }

  if (norm(row.payload.to_tier) === 'UNIT') {
    const pu = norm(row.payload.geo_pu);
    return !pu || norm(officer.geo_pu) === pu;
  }

  return true;
}

/**
 * The roles a notice is addressed to.
 *
 * For an escalation it is the desk that now owns the incident — that is what
 * `rolesForTier` answers and what the chain means.
 *
 * For a NEW incident at the unit it is also the FIELD RESPONDERS, because they
 * are who go. They hold no tier, so `rolesForTier` does not name them, and a
 * new emergency that only reaches the unit commander's phone is waiting on one
 * person to be awake.
 *
 * Widened only for this kind and only at the UNIT: an escalation reaching the
 * LGA is a message to a desk, and copying every responder in the LGA on it is
 * how people turn off the notifications they do need. And nobody is sent a push
 * about a row RLS would refuse them: `alert_in_my_area()` gives a field
 * responder their whole LGA, so their own polling unit is well inside it.
 */
export function rolesToNotify(row: OutboxRow): string[] {
  const tier = rolesForTier(row.payload.to_tier);
  if (tier.length === 0) return tier;
  if (norm(row.kind) === NEW_INCIDENT && norm(row.payload.to_tier) === 'UNIT') {
    return [...tier, 'RESPONDER', 'AGENT'];
  }
  return tier;
}

/** The officers to notify, from everyone loaded. */
export function recipientsFor(officers: OfficerRow[], row: OutboxRow): OfficerRow[] {
  return officers.filter(o => o && officerShouldHear(o, row));
}

/**
 * What the notification says.
 *
 * Short, because it arrives on a lock screen. It names the tier it has landed
 * on and why it moved, since "escalated" without a reason reads as somebody
 * having made a decision — and nobody did. A timeout is the absence of one.
 */
export function escalationMessage(row: OutboxRow): { heading: string; body: string } {
  const to = norm(row.payload.to_tier) ?? 'COMMAND';
  const where = row.payload.geo_lga || 'an unlocated incident';
  const severity = norm(row.payload.severity);
  const ref = (row.payload.alert_id || row.alert_id || '').slice(0, 8);

  // A FIRST REPORT IS NOT AN ESCALATION.
  //
  // "was not acknowledged in time and has come up to" is a true sentence about
  // a timeout and a false one about an emergency that has just been filed. An
  // officer who reads the escalation wording on a new SOS learns that somebody
  // already had it and did nothing, which nobody did.
  if (norm(row.kind) === NEW_INCIDENT) {
    const what = norm(row.payload.type) ?? 'INCIDENT';
    return {
      heading: severity === 'CRITICAL'
        ? `⚠️ CRITICAL — ${what} REPORTED`
        : `${what} REPORTED`,
      body: `Incident #${ref} has just been reported in ${where}. Open it to accept and respond.`,
    };
  }

  return {
    heading: severity === 'CRITICAL'
      ? `⚠️ CRITICAL INCIDENT NOW AT ${to}`
      : `INCIDENT NOW AT ${to}`,
    body: `Incident #${ref} in ${where} was not acknowledged in time and has come up to ${to}. Open the console to take it.`,
  };
}
