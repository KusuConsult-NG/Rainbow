/**
 * Whether a mass advisory is for the person looking at this console.
 *
 * ## The defect this closes
 *
 * `SystemAlertListener` docked the newest live advisory under the console
 * header and applied **no targeting at all** — only `is_active` and expiry. The
 * composer offers five targeting controls (audience, agency, LGA, ward, polling
 * unit) and the console honoured none of them, so:
 *
 *   * an advisory addressed to **CITIZENS** docked under an HQ operator's
 *     header, which is the same class of fault the file's own comment warns
 *     about — "an advisory that is no longer true is worse than none, because
 *     operators calibrate against it". One that was never theirs is the same
 *     problem with a different cause;
 *   * an advisory addressed to **one agency** appeared on every other agency's
 *     liaison screen. `console-access.ts` exists to stop a liaison from an
 *     outside agency seeing what is not theirs, and this was the one surface
 *     that ignored it;
 *   * an advisory scoped to one LGA or ward went to every console user in the
 *     state.
 *
 * This is also where `system_alerts.target_agency` finally gets a reader. It
 * had none — written by the composer and read by nothing, recorded as open
 * under T-29 — and the reason is that agency liaisons have console accounts and
 * not handsets, so the mobile side has no surface for an agency-addressed
 * advisory to reach. The console is that surface.
 *
 * ## Deliberately the same shape as `broadcastReaches` in the app
 *
 * `lib/services/broadcast_targeting.dart` decides the same question for a
 * handset. The two have to agree about what a row MEANS or the composer is
 * lying to somebody, so the rules below mirror it: the canonical audience with
 * a fallback to the legacy `target_type`, place scoping that fails OPEN on a
 * viewer whose own place is unknown, and an unrecognised audience treated as
 * ALL rather than dropped. Two differences, both because the readers are
 * different kinds of surface:
 *
 *   * `CITIZENS` reaches nobody here. A console has no citizen users.
 *   * agency scoping exists here and nowhere else, for the reason above.
 */

/** Everything this decision needs to know about the person at the console. */
export interface AdvisoryViewer {
  /**
   * The agency this account belongs to, or null for Plateau Eye staff.
   * Comes from `consoleAccess(role).agency`, which derives it from the role —
   * not from `profiles.agency`, which is a decorative badge (T-28).
   */
  agency: string | null;
  /**
   * HQ, ADMIN and the other statewide commands. They compose advisories and
   * withdraw them, so they see every one regardless of who it was addressed to
   * — the same pass-through the app gives `HQ_OFFICER`.
   */
  isCommand: boolean;
  /** The viewer's own posting, when the console knows it. Any may be absent. */
  geoLga?: string | null;
  geoWard?: string | null;
  geoPu?: string | null;
}

/** A scope value that means "no restriction". */
function unscoped(value: unknown): boolean {
  const v = String(value ?? '').trim();
  return v === '' || v.toUpperCase() === 'ALL';
}

/**
 * Place names are entered by hand and are not consistent — "Jos North",
 * "JOS NORTH", "Jos North LGA" are one place. Matched loosely in both
 * directions, the same rule the incident board and the app already use.
 *
 * Under-matching is the expensive direction: it withholds a warning from
 * somebody inside the affected area.
 */
function placeMatches(scope: string, viewerValue?: string | null): boolean {
  const r = String(viewerValue ?? '').trim().toLowerCase();
  // The viewer has no place recorded. Deliver anyway — see the header.
  if (r === '') return true;
  const s = scope.trim().toLowerCase();
  return r === s || r.includes(s) || s.includes(r);
}

/**
 * The audience a row is addressed to, canonical column first.
 *
 * `target_type` is the original schema's name and is still present on rows the
 * old mobile broadcast screen wrote, so it is read as a fallback — exactly as
 * `broadcastAudience()` does in the app. There is no fallback for the legacy
 * `target_value`, and deliberately so: nothing has ever written it (see that
 * function's doc comment).
 */
export function advisoryAudience(row: Record<string, unknown>): string {
  const canonical = String(row.target_audience ?? '').trim();
  if (canonical) return canonical.toUpperCase();
  const legacy = String(row.target_type ?? '').trim();
  if (legacy) return legacy.toUpperCase();
  return 'ALL';
}

/** Whether `row` should be docked on this console, at `now`. */
export function advisoryReaches(
  row: Record<string, unknown>,
  viewer: AdvisoryViewer,
  now: Date = new Date(),
): boolean {
  // Withdrawn by HQ.
  if (row.is_active === false) return false;

  // Expired. A row with no expiry stands until it is deactivated, and a row
  // written before the column existed has it NULL — which is why this is a
  // client-side check and not a `.lt()`.
  const rawExpiry = row.expires_at;
  if (typeof rawExpiry === 'string' && rawExpiry.trim() !== '') {
    const expiresAt = Date.parse(rawExpiry);
    if (!Number.isNaN(expiresAt) && expiresAt <= now.getTime()) return false;
  }

  // Command sees everything: they sent it, and they are who withdraws it.
  if (viewer.isCommand) return true;

  // A console has no citizen users, so an advisory addressed to citizens has
  // nobody here to reach. Every other audience — AGENTS, RESPONDERS, ALL, or
  // something unrecognised — stands: an advisory that reaches too many people
  // is recoverable, one lost to a typo in a dropdown is not.
  if (advisoryAudience(row) === 'CITIZENS') return false;

  // Addressed to one agency. Only that agency's liaison sees it; Operation
  // Rainbow staff below command do not, because it was not addressed to them.
  const agency = row.target_agency;
  if (!unscoped(agency)) {
    if (!viewer.agency) return false;
    if (String(agency).trim().toUpperCase() !== viewer.agency.toUpperCase()) {
      return false;
    }
  }

  const lga = row.target_lga;
  if (!unscoped(lga) && !placeMatches(String(lga), viewer.geoLga)) return false;

  const ward = row.target_ward;
  if (!unscoped(ward) && !placeMatches(String(ward), viewer.geoWard)) return false;

  const pu = row.target_pu;
  if (!unscoped(pu) && !placeMatches(String(pu), viewer.geoPu)) return false;

  return true;
}
