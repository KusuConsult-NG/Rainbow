/**
 * What each kind of account may reach in this console.
 *
 * ## Why this is one function and not thirty conditionals
 *
 * Six agencies send liaison officers to this console — the Police, the Army,
 * the DSS, the NSCDC, the FRSC and Operation Safe Haven. They are not Operation
 * Rainbow staff. They are officers of other organisations, given an account so
 * that an incident handed to their agency reaches them.
 *
 * What they got was the command console. The navigation offered them the
 * statewide Intelligence Map, the full Incident Feed, every Mission History
 * record in the state, and Communications & Broadcast. The browser harness
 * confirms it: signed in as the Police liaison, five screens.
 *
 * Two of those were worse than untidy:
 *
 *   * **Broadcast is a dead control for them.** `system_alerts` INSERT
 *     requires `is_command()`, which a `_LIAISON` role is not. So a liaison
 *     could compose a statewide advisory, press transmit, and get a row-level
 *     security refusal — after writing it. A button that cannot work should
 *     not be on the screen.
 *
 *   * **The board was never theirs to see.** `alerts_select_own_or_staff` is
 *     `... OR is_staff()`, and `is_staff()` is "role is not CITIZEN". A liaison
 *     is therefore staff, so every incident in Plateau was readable — and
 *     `alerts_update_own_or_staff` means writable. An officer of another
 *     agency could resolve or reassign an incident in an LGA their agency was
 *     never called to. The migration beside this file scopes that properly;
 *     this file makes the console stop offering what the database is about to
 *     stop allowing.
 *
 * Hiding a control is not access control — the database decides — but showing
 * a control that will be refused is its own defect, and the two have to agree.
 * Keeping the answer in one tested place is what makes that possible.
 */

/** Every tab the console has. */
export type ConsoleTab =
  | 'map'
  | 'alerts'
  | 'history'
  | 'analytics'
  | 'broadcast'
  | 'admin'
  | 'settings'
  | 'audit'
  | 'uninstall'
  | 'agency'
  | 'sim';

/** The six agencies that send liaison officers. */
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
  // Operation Safe Haven: the military joint task force that covers Plateau,
  // Bauchi and Kaduna. NOT Amotekun, which is a South-West outfit with no
  // presence in this state.
  OPSH: 'Operation Safe Haven',
};

/** Roles that hold command of the whole state. */
const HQ_ROLES = ['HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'];

/** Roles that command a slice of it. */
const SECTOR_COMMAND_ROLES = [
  'LGA_COMMAND',
  'LGA_OFFICER',
  'WARD_COMMAND',
  'WARD_OFFICER',
  'UNIT_COMMAND',
  'POLLING_UNIT_OFFICER',
  'POLLING_OFFICER',
];

/** Whether a role is an agency liaison, and which agency. */
export function agencyOf(role: string | null | undefined): AgencyCode | null {
  if (!role) return null;
  if (!role.endsWith('_LIAISON')) return null;
  const code = role.slice(0, -'_LIAISON'.length);
  return (AGENCY_CODES as readonly string[]).includes(code)
    ? (code as AgencyCode)
    : null;
}

export interface ConsoleAccess {
  /** The tabs this role may open, in the order they should appear. */
  tabs: ConsoleTab[];
  /** Where this role lands when it signs in. */
  landing: ConsoleTab;
  /** The agency this account belongs to, or null for Operation Rainbow staff. */
  agency: AgencyCode | null;
  /** What the sidebar calls this console for them. */
  title: string;
  /** The line under the title. */
  subtitle: string;
  /** Whether the administration section is theirs. */
  administration: boolean;
}

/**
 * What this role may reach.
 *
 * An unknown role gets the smallest possible console rather than the largest:
 * while the profile is still loading, `userRole` is `''`, and a default of
 * "show everything" would flash the whole command console at an agency liaison
 * on every page load before settling.
 */
export function consoleAccess(
  role: string | null | undefined,
  options: { agencyName?: string; sector?: string } = {},
): ConsoleAccess {
  const agency = agencyOf(role);

  if (agency) {
    return {
      // Their own desk, and the incidents handed to their agency. No
      // statewide map, no statewide history, and no broadcast — that last one
      // the database refuses anyway.
      tabs: ['agency', 'alerts'],
      landing: 'agency',
      agency,
      title: AGENCY_NAMES[agency],
      subtitle: 'LIAISON DESK',
      administration: false,
    };
  }

  const normalised = (role || '').toUpperCase();

  if (HQ_ROLES.includes(normalised)) {
    return {
      tabs: [
        'map',
        'alerts',
        'history',
        'broadcast',
        'agency',
        'admin',
        'audit',
        'settings',
        'uninstall',
        'sim',
      ],
      landing: 'map',
      agency: null,
      title: 'Command HQ',
      subtitle: 'TACTICAL MONITOR',
      administration: true,
    };
  }

  // A field responder has the mobile app; the console is for awareness when
  // they are at a desk. Three screens, and the two that are missing are
  // missing because the DATABASE refuses them, not because we are being tidy:
  // `system_alerts` INSERT requires is_command(), which a RESPONDER is not, so
  // the broadcast composer could only ever end in a refusal; and the agency
  // rosters are scoped to liaisons and command, which the production
  // behaviour test asserts ("responders cannot read agency rosters"), so the
  // portal would open empty for them.
  if (normalised === 'RESPONDER' || normalised === 'AGENT') {
    return {
      tabs: ['map', 'alerts', 'history'],
      landing: 'map',
      agency: null,
      title: 'Field Unit',
      subtitle: (options.sector || 'RESPONDER').toUpperCase(),
      administration: false,
    };
  }

  if (SECTOR_COMMAND_ROLES.includes(normalised)) {
    return {
      tabs: ['map', 'alerts', 'history', 'broadcast', 'agency'],
      landing: 'map',
      agency: null,
      title: sectorTitle(normalised),
      subtitle: (options.sector || 'SECTOR').toUpperCase(),
      administration: false,
    };
  }

  // Unknown, or still loading.
  return {
    tabs: ['map', 'alerts'],
    landing: 'map',
    agency: null,
    title: 'Operation Rainbow',
    subtitle: 'RESOLVING ACCESS',
    administration: false,
  };
}

function sectorTitle(role: string): string {
  if (role.startsWith('LGA')) return 'LGA Command';
  if (role.startsWith('WARD')) return 'Ward Command';
  return 'PU Command';
}

/** Whether this role may open this tab. */
export function canOpen(role: string | null | undefined, tab: ConsoleTab): boolean {
  return consoleAccess(role).tabs.includes(tab);
}
