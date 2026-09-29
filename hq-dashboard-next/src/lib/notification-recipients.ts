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
  };
}

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
  switch (norm(tier)) {
    case 'UNIT':
      return ['UNIT_COMMAND', 'POLLING_UNIT_OFFICER', 'POLLING_OFFICER'];
    case 'WARD':
      return ['WARD_COMMAND', 'WARD_OFFICER'];
    case 'LGA':
      return ['LGA_COMMAND', 'LGA_OFFICER'];
    case 'HQ':
      return ['HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'];
    default:
      return [];
  }
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
  const roles = rolesForTier(row.payload.to_tier);
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

  return {
    heading: severity === 'CRITICAL'
      ? `⚠️ CRITICAL INCIDENT NOW AT ${to}`
      : `INCIDENT NOW AT ${to}`,
    body: `Incident #${ref} in ${where} was not acknowledged in time and has come up to ${to}. Open the console to take it.`,
  };
}
