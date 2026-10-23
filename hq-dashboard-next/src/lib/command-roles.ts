/**
 * Who holds which rung, in one place, in both vocabularies.
 *
 * ## What went wrong
 *
 * The production project's 22 staff accounts carry `STATE_COMMANDER` (×4),
 * `LGA_COMMANDER` (×4), `WARD_COMMANDER` (×4) and `POLLING_UNIT_OFFICER` (×6).
 * This repository was written against `HQ_COMMAND` / `LGA_COMMAND` /
 * `WARD_COMMAND` / `UNIT_COMMAND`, and the two vocabularies met in **ten**
 * separate exact-match lists in this console alone:
 *
 *     supabase-server.ts        COMMAND_ROLES            gates /api/ai/analyze,
 *                                                        /api/admin/provision
 *     console-access.ts         HQ_ROLES,
 *                               SECTOR_COMMAND_ROLES     console scoping
 *     notification-recipients.ts rolesForTier()          WHO GETS TOLD
 *     assignable-responders.ts  commandsWholeState()     who may be assigned
 *     broadcast-logic.ts        categorizeUser()         advisory targeting
 *     admin/provision/route.ts  ELEVATED,
 *                               MAY_CREATE_ELEVATED      who may create staff
 *     dashboard/page.tsx        commandRoles, hqRoles,
 *                               isHqUser                 what the screen shows
 *
 * None of them knew the second spelling. T-85 taught the app's tier map both,
 * T-90 taught `is_command()` and `commands_whole_state()` both, and nobody
 * touched the console or `escalation_push_targets()`.
 *
 * The worst of them is `rolesForTier`, because it decides who a notification is
 * addressed to:
 *
 *     WARD -> ['WARD_COMMAND', 'WARD_OFFICER']   production has WARD_COMMANDER
 *     LGA  -> ['LGA_COMMAND', 'LGA_OFFICER']     production has LGA_COMMANDER
 *     HQ   -> ['HQ_COMMAND', 'HQ_OFFICER', 'ADMIN']  production has STATE_COMMANDER
 *
 * So on that deployment a ward escalation is addressed to NOBODY, an LGA
 * escalation to nobody, and an HQ escalation to the one `HQ_COMMAND` account.
 * `deliverTierEscalation` throws "no reachable officer at that tier" when the
 * recipient list is empty — deliberately, so the notice is retried rather than
 * marked delivered — so those escalations could never be delivered at all. The
 * UNIT tier works, and only because somebody hit this for that one rung and
 * added `POLLING_UNIT_OFFICER` to that one list.
 *
 * ## Why a map and not four lists
 *
 * Adding three names to four lists fixes today and leaves the shape that
 * produced it. Here the ROLE-TO-RUNG map is the only place a name is written
 * and every list is DERIVED from it, so `rolesForTier` cannot disagree with
 * `tierForRole`, and a name added for one question is answered for all of them.
 *
 * This mirrors `staffRoleTiers` in `lib/providers/auth_provider.dart` and
 * `public.roles_for_tier()` in SQL. Three languages, and
 * `scripts/check_one_command_vocabulary.py` asserts all three agree — it used
 * to read two of them.
 *
 * See E2E_AUDIT_REPORT.md T-97.
 */

/** A rung of the command chain. `null` means staff outside the chain. */
export type Tier = 'HQ' | 'LGA' | 'WARD' | 'UNIT';

/**
 * Every staff role this product knows, and the rung it acts at.
 *
 * Mirrors `staffRoleTiers` in the Dart, and additionally carries the
 * `_OFFICER` and `ADMIN` names the database knows and the app does not.
 */
export const STAFF_ROLE_TIERS: Readonly<Record<string, Tier | null>> = {
  // The vocabulary this repository is written against.
  HQ_COMMAND: 'HQ',
  LGA_COMMAND: 'LGA',
  WARD_COMMAND: 'WARD',
  UNIT_COMMAND: 'UNIT',

  // The vocabulary the production project's accounts actually carry.
  STATE_COMMANDER: 'HQ',
  LGA_COMMANDER: 'LGA',
  WARD_COMMANDER: 'WARD',
  POLLING_UNIT_OFFICER: 'UNIT',

  // Desk names the database carries. An escalation is addressed to a desk, not
  // to a person: at two in the morning the commander is not necessarily the
  // one awake.
  HQ_OFFICER: 'HQ',
  ADMIN: 'HQ',
  LGA_OFFICER: 'LGA',
  WARD_OFFICER: 'WARD',
  POLLING_OFFICER: 'UNIT',

  // Staff deliberately outside the chain. `null` is "no rung", which is what
  // these are — not "unrecognised".
  RESPONDER: null,
  POLICE_LIAISON: null,
  ARMY_LIAISON: null,
};

function norm(role: string | null | undefined): string {
  return (role ?? '').trim().toUpperCase();
}

/** The rung this role acts at, or null for staff outside the chain. */
export function tierForRole(role: string | null | undefined): Tier | null {
  return STAFF_ROLE_TIERS[norm(role)] ?? null;
}

/** Whether this product has heard of the role at all. */
export function isKnownStaffRole(role: string | null | undefined): boolean {
  return norm(role) in STAFF_ROLE_TIERS;
}

/**
 * Every role that holds `tier`. Derived, so it cannot drift from the map.
 *
 * Both spellings of the rung and both desk names, because this is what a
 * notification is addressed to.
 */
export function rolesForTier(tier: string | null | undefined): string[] {
  const want = norm(tier);
  if (want !== 'HQ' && want !== 'LGA' && want !== 'WARD' && want !== 'UNIT') {
    // A tier nobody holds addresses nobody. Failing open here would send every
    // escalation to every officer in the state.
    return [];
  }
  return Object.entries(STAFF_ROLE_TIERS)
    .filter(([, t]) => t === want)
    .map(([role]) => role)
    .sort();
}

/** HQ and administrators: command of the whole state. */
export function commandsWholeState(role: string | null | undefined): boolean {
  return tierForRole(role) === 'HQ';
}

/**
 * Command of anything — a rung of the chain.
 *
 * The SQL counterpart `is_command()` is narrower: it covers HQ and LGA only,
 * because a ward or polling-unit officer is not command. Kept identical here so
 * one answer is given in both languages.
 */
export function isCommand(role: string | null | undefined): boolean {
  const tier = tierForRole(role);
  return tier === 'HQ' || tier === 'LGA';
}

/** Roles that command the whole state. Derived. */
export const HQ_ROLES: readonly string[] = rolesForTier('HQ');

/** Roles that command a slice of it. Derived. */
export const SECTOR_COMMAND_ROLES: readonly string[] = [
  ...rolesForTier('LGA'),
  ...rolesForTier('WARD'),
  ...rolesForTier('UNIT'),
];

/**
 * Roles allowed through a command-only API route. Derived.
 *
 * Matches `is_command()` in SQL, so a route and the row-level security behind
 * it refuse the same people. They did not: this list was
 * `['HQ_COMMAND','HQ_OFFICER','ADMIN','LGA_COMMAND']`, which is the exact
 * pre-T-90 `is_command()` body, so 20 of 22 production staff accounts were
 * refused by every route gated on it.
 */
export const COMMAND_ROLES: readonly string[] = [
  ...rolesForTier('HQ'),
  ...rolesForTier('LGA'),
];
