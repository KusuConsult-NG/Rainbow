/**
 * The six outside agencies, named once.
 *
 * ## The defect this file closes
 *
 * An agency code is a value in `alerts.escalated_to_agency`. Three separate
 * things key off it, and all three agreed:
 *
 *   * `agencyOf()` derives a liaison's agency from their role, so the account
 *     created as `POLICE_LIAISON` is the agency `POLICE`;
 *   * `AgencyPortal` loads a liaison's whole desk with
 *     `.eq('escalated_to_agency', agency)` — incidents, personnel, action
 *     reports, deployments;
 *   * `/api/notify-agency` looks the liaison's phone and webhook up by the same
 *     code, from `POLICE_LIAISON_PHONE` and `POLICE_WEBHOOK_URL`.
 *
 * The HQ escalation menu did not. It was built from
 * `STATE_SECURITY_AGENCIES` — a presentation list for badging Operation
 * Rainbow's own staff — and so offered `NPF`, `MILITARY`, `RAINBOW` and `VGN`.
 * Escalating an incident to "NIGERIA POLICE FORCE (NPF TACTICAL CELL)" wrote
 * `escalated_to_agency = 'NPF'`, and then:
 *
 *   * the Police liaison's portal, which asks for `'POLICE'`, never showed it;
 *   * `/api/notify-agency` answered `400 Unknown agency 'NPF'`, so no SMS and
 *     no webhook left the building;
 *   * the operator was told **"Escalation Sent — handed off to NPF Command"**.
 *
 * Four of the menu's six destinations behaved that way; only `DSS` and `NSCDC`
 * happened to spell the same. The two codes the deployment is actually
 * configured for — `FRSC` and `OPSH` — could not be chosen at all. Every unit
 * test and every browser assertion passed over it, because they were all
 * written in the vocabulary of the three sides that agreed.
 *
 * So the vocabulary lives here, once, and every menu, contact lookup and
 * legend is built from it. `scripts/check_one_agency_vocabulary.py` fails the
 * build if a second list appears.
 *
 * ## Not the same thing as `STATE_SECURITY_AGENCIES`
 *
 * That list (in `tactical_mapping.ts`) answers "which organisation does this
 * officer belong to", including Operation Rainbow itself and the vigilante
 * groups, and is worn as a badge in the staff directory. It is not a set of
 * handover destinations: `RAINBOW` is us, and no vigilante group has a liaison
 * account, a portal or a contact number. Escalating to one of them has nowhere
 * to land, which is why it is not offered here.
 */

/** The six agencies that send liaison officers, and the only values that may be written to `alerts.escalated_to_agency`. */
export const AGENCY_CODES = [
  'POLICE',
  'ARMY',
  'DSS',
  'NSCDC',
  'FRSC',
  'OPSH',
] as const;

export type AgencyCode = (typeof AGENCY_CODES)[number];

/** Full names, for chrome that should say who the person is. */
export const AGENCY_NAMES: Record<AgencyCode, string> = {
  POLICE: 'Nigeria Police Force',
  ARMY: 'Nigerian Army',
  DSS: 'Department of State Services',
  NSCDC: 'Nigeria Security & Civil Defence Corps',
  FRSC: 'Federal Road Safety Corps',
  // Operation Enduring Peace: the military joint task force that covers
  // Plateau, Bauchi and Kaduna — renamed from Operation Safe Haven, which is
  // what this said and what the deployment is not called. NOT Amotekun, which
  // is a South-West outfit with no presence in this state.
  //
  // The CODE stays `OPSH`. It is a stored identifier, not a display name: it
  // is in `alerts.escalated_to_agency`, in the `OPSH_LIAISON` role that
  // `liaison_agency()` parses, in every row of `agency_personnel`,
  // `agency_deployments` and `agency_action_reports`, and in the vocabulary
  // `check_one_agency_vocabulary.py` holds across five surfaces. Changing it
  // is a data migration and a role rename, not a rename. Changing the label is
  // what makes the screens say the right thing.
  OPSH: 'Operation Enduring Peace',
};

/**
 * How each agency is drawn. Kept beside the names so a colour cannot come to
 * mean one agency on the portal header and another in the escalation menu.
 */
export const AGENCY_CHROME: Record<AgencyCode, { color: string; icon: string }> = {
  POLICE: { color: '#3b82f6', icon: '🚔' },
  ARMY:   { color: '#22c55e', icon: '🪖' },
  DSS:    { color: '#8b5cf6', icon: '🕵️' },
  NSCDC:  { color: '#f59e0b', icon: '🛡️' },
  FRSC:   { color: '#ef4444', icon: '🚨' },
  OPSH:   { color: '#14b8a6', icon: '🛰️' },
};

export interface AgencyDescriptor {
  code: AgencyCode;
  label: string;
  color: string;
  icon: string;
}

/** Every agency, in one order, for every menu and legend that lists them. */
export const AGENCY_LIST: AgencyDescriptor[] = AGENCY_CODES.map(code => ({
  code,
  label: AGENCY_NAMES[code],
  ...AGENCY_CHROME[code],
}));

/**
 * Whether a stored value is an agency this system can reach.
 *
 * `alerts.escalated_to_agency` is free text — deliberately, because production
 * holds rows written before any of this was settled — so a read of it has to
 * be checked rather than cast.
 */
export function isAgencyCode(value: unknown): value is AgencyCode {
  return typeof value === 'string'
    && (AGENCY_CODES as readonly string[]).includes(value);
}

/**
 * What the escalation menu means by "no particular agency".
 *
 * `ALL` is a broad inter-agency escalation: it raises the incident to CRITICAL
 * and records the handover, and deliberately sends no agency notification,
 * because there is no single agency to notify.
 */
export const AGENCY_TARGET_ALL = 'ALL';
