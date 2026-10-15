/**
 * What HQ sees when it clicks an incident on the map.
 *
 * ## Why this file exists
 *
 * The map marker's popup was the thinnest surface in the console: incident
 * type, status, description, and two buttons. Everything a dispatcher actually
 * needs in order to act — who reported it, how to ring them back, how long it
 * has been waiting, whether anybody has acknowledged it, which tier owns it,
 * and whether the report reached us over SMS because the reporter had no data
 * connection — existed in the row and was not shown. The operator had to leave
 * the map, find the same incident in the list, and open the dossier.
 *
 * Three defects made it worse than thin.
 *
 * **It read Firebase field names.** LiveMap declared `reportedBy?: string` and
 * `reportedAt?: { seconds: number }`. PostgREST returns `reported_by` and
 * `created_at` and never returns a camelCase key, so both were permanently
 * `undefined` — the same class of bug as `alert['assignedToUid']`. Nothing
 * errored; the fields were simply never rendered.
 *
 * **The DISPATCH button was unreachable.** It rendered only when
 * `status === 'OPEN' || status === 'ACTIVE'`. Neither is a status this database
 * produces: the column defaults to `'PENDING'` and the schema's values are
 * PENDING / DISPATCHED / ACKNOWLEDGED / ON_ROUTE / ON_SITE / RESOLVED /
 * DURESS / CANCELLED. So every newly reported incident — every single one —
 * offered RESOLVE and no way to dispatch.
 *
 * **It interpolated a citizen's text into HTML.** `${alert.description}` went
 * straight into a popup string. A report whose description contained
 * `<img src=x onerror=...>` executed in the operator's authenticated session.
 * That is why [escapeHtml] exists and why every value below goes through it.
 *
 * ## The rule this module follows
 *
 * **Absence is rendered as absence.** Nothing here invents a value. A report
 * with no reporter says so; a report the reporter chose to file anonymously
 * says *that*, distinctly, because "unidentified" would send an operator
 * looking for a name that was deliberately withheld. This is the same
 * discipline as C-5 (no fabricated coordinates) and the `severity || 'HIGH'`
 * fix one field over: a dispatcher who can see what is missing makes a better
 * decision than one shown a confident default.
 */

import type { Alert } from '@/app/dashboard/types';

// ── Escaping ────────────────────────────────────────────────────────────────

/**
 * Makes a value safe to interpolate into the popup's HTML.
 *
 * Leaflet's `bindPopup` takes an HTML string, so the popup is built by
 * concatenation and every value in it is attacker-controlled: descriptions and
 * types come from citizen reports, names and phone numbers from profiles, and
 * an alert can now be raised over SMS by anyone holding a device key.
 *
 * Escapes the five characters that matter in both element content and quoted
 * attribute values, so one function serves both positions. `'` and `"` are
 * escaped for the attribute case even though only `<` and `&` matter in text.
 */
export function escapeHtml(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── Reporter identity ───────────────────────────────────────────────────────

export interface Reporter {
  /** Display name, or an honest statement that there is none. */
  name: string;
  /** Phone or email HQ can reach them on, or an honest statement that there is none. */
  contact: string;
  /** What kind of reporter: citizen, responder, HQ. */
  type: string;
  /** Badge number, when the reporter is staff. */
  badge: string | null;
  /** The profile role, verbatim, when one was found. */
  role: string | null;
  /** True when a profile was actually matched — not inferred from a uuid. */
  identified: boolean;
  /** True when the report was filed anonymously ON PURPOSE. */
  anonymous: boolean;
}

/** A contact string we could plausibly dial. */
const DIALLABLE = /^\+?[0-9][0-9 ()\-.]{6,}$/;

/** True when `contact` is a phone number rather than an email or a placeholder. */
export function isDiallable(contact: string): boolean {
  return DIALLABLE.test(contact.trim());
}

/**
 * Who raised this incident, and how HQ reaches them.
 *
 * `usersMap` is the profile map the dashboard loads. When the reporter is not
 * in it we say so rather than guessing: an operator told "Registered Citizen /
 * No Phone Registered" cannot tell a citizen with no phone on file from a
 * lookup that quietly failed, and for two months it was always the second one
 * (the profile query named three columns that do not exist, so the map was
 * empty and every reporter rendered with those two strings).
 *
 * An anonymous report is a separate case from an unknown one. The offline
 * ingest writes `reported_by: null` when the reporter asked for anonymity, and
 * the server discards the identity it could have recorded. Reporting that as
 * "unidentified" would be a lie by omission in the other direction — it
 * suggests the system lost something it deliberately never kept.
 */
export function resolveReporterDetails(
  alert: Alert,
  usersMap: Record<string, any>,
): Reporter {
  const extra = alert as unknown as Record<string, unknown>;
  const reporterId = String(alert.reported_by || '');
  const alertPhone = (extra.phone_number ||
    extra.reporter_phone ||
    extra.phone ||
    extra.contact) as string | undefined;

  const profile = reporterId ? usersMap?.[reporterId] : null;

  // No reporter at all. Either the reporter asked not to be named — the
  // offline channels honour that by writing NULL — or the column is empty for
  // a reason nobody recorded. Those are different facts and get different text.
  if (!reporterId && !alertPhone) {
    const viaOffline = !!alert.arrived_via;
    return viaOffline
      ? {
          name: 'ANONYMOUS REPORT',
          contact: 'Withheld at the reporter’s request',
          type: 'Anonymous — identity not recorded by design',
          badge: null,
          role: null,
          identified: false,
          anonymous: true,
        }
      : {
          name: 'NO REPORTER RECORDED',
          contact: 'No contact on this report',
          type: 'Unattributed report',
          badge: null,
          role: null,
          identified: false,
          anonymous: false,
        };
  }

  let name = 'UNIDENTIFIED REPORTER';
  let contact = 'No contact on file';
  let type = 'Citizen mobile app';

  // 1. Contact. The alert's own phone field wins: an SMS-borne report may carry
  //    a number for a handset that has no profile at all.
  if (alertPhone) {
    contact = alertPhone;
  } else if (profile?.phone || profile?.phone_number || profile?.mobile) {
    contact = profile.phone || profile.phone_number || profile.mobile;
  } else if (profile?.email) {
    contact = profile.email;
  } else if (isDiallable(reporterId)) {
    contact = reporterId;
  }

  // 2. Name.
  if (profile?.full_name || profile?.name || profile?.displayName) {
    name = profile.full_name || profile.name || profile.displayName;
  } else if (reporterId.includes('@')) {
    name = `Officer ${reporterId.split('@')[0].toUpperCase()}`;
    if (!alertPhone && !profile?.phone) contact = reporterId;
  } else if (reporterId && !/^[0-9a-fA-F-]{24,}$/.test(reporterId) && !isDiallable(reporterId)) {
    // Not a uuid and not a number, so it is already a human-readable label.
    name = reporterId;
  } else if (reporterId && !profile) {
    // A uuid with no matching profile. Say exactly that, and show the uuid, so
    // the operator can look it up rather than assume the report is anonymous.
    name = `UNIDENTIFIED — profile ${reporterId.slice(0, 8)} not loaded`;
  }

  // 3. Kind of reporter.
  if (profile?.role) {
    const role = String(profile.role).toUpperCase();
    type =
      role.startsWith('HQ') || role === 'ADMIN'
        ? 'HQ command staff'
        : role === 'RESPONDER' || role === 'AGENT'
          ? 'Field tactical responder'
          : 'Citizen mobile app';
  }

  return {
    name,
    contact,
    type,
    badge: profile?.badge_number || null,
    role: profile?.role ? String(profile.role) : null,
    identified: !!profile,
    anonymous: false,
  };
}

/** A short label for whoever the incident is assigned to. */
export function resolveAssignee(
  alert: Alert,
  usersMap: Record<string, any>,
): string {
  const id = alert.assigned_to;
  if (!id || id === 'UNASSIGNED') return 'NOBODY — unassigned';
  const profile = usersMap?.[id];
  if (!profile) return isDiallable(id) || id.includes('@') ? id : `Officer ${id.slice(0, 8)}`;
  const badge = profile.badge_number ? ` (${profile.badge_number})` : '';
  return `${profile.full_name || profile.email || id.slice(0, 8)}${badge}`;
}

// ── Status, severity, and what may be done about them ───────────────────────

/**
 * The marker colour for a status.
 *
 * `PENDING` and `CANCELLED` were both missing, and PENDING is the status every
 * report arrives with. It fell through to the same orange as OPEN, which
 * happened to be right, by luck.
 *
 * OPEN and ACTIVE are kept because rows written before the schema settled may
 * still carry them, not because anything produces them now.
 */
export function statusColour(status?: string): string {
  switch ((status || '').toUpperCase()) {
    case 'DURESS':
      return '#E31E24'; // AppColors.danger
    case 'PENDING':
    case 'OPEN':
    case 'ACTIVE':
      return '#FF9800'; // AppColors.warning
    case 'DISPATCHED':
      return '#0277BD'; // AppColors.info
    case 'ACKNOWLEDGED':
    case 'IN_PROGRESS':
      return '#00838F';
    case 'ESCALATED':
      return '#4527A0';
    case 'ON_ROUTE':
      return '#6A1B9A';
    case 'ON_SITE':
      return '#00695C';
    case 'RESOLVED':
      return '#1B5E20'; // AppColors.success
    case 'CANCELLED':
      return '#757575';
    default:
      return '#FF9800';
  }
}

/** Plain words for a status, for people who do not read enums. */
export function statusLabel(status?: string): string {
  switch ((status || '').toUpperCase()) {
    case 'PENDING':
      return 'AWAITING DISPATCH';
    case 'DURESS':
      return 'DURESS — SILENT ALARM';
    case 'DISPATCHED':
      return 'UNIT DISPATCHED';
    case 'ACKNOWLEDGED':
      return 'ACKNOWLEDGED';
    case 'IN_PROGRESS':
      return 'BEING WORKED';
    case 'ESCALATED':
      return 'ESCALATED TO COMMAND';
    case 'ON_ROUTE':
      return 'UNIT EN ROUTE';
    case 'ON_SITE':
      return 'UNIT ON SITE';
    case 'RESOLVED':
      return 'RESOLVED';
    case 'CANCELLED':
      return 'CANCELLED';
    case '':
      return 'STATUS NOT RECORDED';
    default:
      return String(status).toUpperCase();
  }
}

export function severityColour(severity?: string): string {
  switch ((severity || '').toUpperCase()) {
    case 'CRITICAL':
      return '#E31E24'; // AppColors.danger
    case 'HIGH':
      return '#EF6C00';
    case 'MEDIUM':
      return '#FF9800'; // AppColors.warning
    case 'LOW':
      return '#1B5E20'; // AppColors.success
    default:
      // UNKNOWN is what the page assigns to a row with no severity. It must not
      // borrow the colour of a grade nobody gave it.
      return '#757575';
  }
}

/** A closed incident takes no further action. */
const CLOSED = new Set(['RESOLVED', 'CANCELLED']);

/**
 * Whether DISPATCH should be offered.
 *
 * Anything not closed. Re-dispatch is legitimate — a unit that cannot reach the
 * scene is reassigned — so this is deliberately not restricted to PENDING.
 */
export function canDispatch(status?: string): boolean {
  return !CLOSED.has((status || 'PENDING').toUpperCase());
}

/** Whether RESOLVE should be offered. */
export function canResolve(status?: string): boolean {
  return !CLOSED.has((status || 'PENDING').toUpperCase());
}

/**
 * An open incident nobody has acknowledged.
 *
 * This is what the escalation cron watches (`acknowledged_at IS NULL`), and it
 * is why the marker pulses: an operator scanning the map should be able to see
 * which incidents are still nobody's, without opening anything.
 */
export function isUnacknowledged(alert: Alert): boolean {
  if (CLOSED.has((alert.status || 'PENDING').toUpperCase())) return false;
  return !alert.acknowledged_at;
}

// ── Time ────────────────────────────────────────────────────────────────────

/** An absolute timestamp, or '—'. Never "JUST NOW" for a missing value. */
export function formatStamp(iso?: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleString('en-GB', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

/**
 * How long ago, in the units a dispatcher thinks in.
 *
 * A future timestamp is reported as such rather than as a negative age: the
 * offline channels set `created_at` from the PHONE's clock, so a handset whose
 * clock is ahead produces one, and "in 4m" tells the operator the clock is
 * wrong where "0m ago" would hide it.
 */
export function formatAge(iso?: string | null, now: Date = new Date()): string {
  if (!iso) return 'time not recorded';
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return 'time not recorded';
  const seconds = Math.round((now.getTime() - then) / 1000);
  if (seconds < -60) return `${describeSpan(-seconds)} IN THE FUTURE (clock skew)`;
  if (seconds < 45) return 'just now';
  return `${describeSpan(seconds)} ago`;
}

function describeSpan(seconds: number): string {
  const mins = Math.round(seconds / 60);
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ${mins % 60}m`;
  const days = Math.floor(hours / 24);
  return `${days}d ${hours % 24}h`;
}

/** Minutes an incident has been open without acknowledgement, or null. */
export function minutesWaiting(alert: Alert, now: Date = new Date()): number | null {
  if (!alert.created_at) return null;
  const then = new Date(alert.created_at).getTime();
  if (Number.isNaN(then)) return null;
  return Math.max(0, Math.round((now.getTime() - then) / 60000));
}

// ── How the report reached us ───────────────────────────────────────────────

/**
 * The channel, and whether it is a warning sign.
 *
 * SMS and MESH both mean the reporter had no data connection. That is not a
 * technical footnote: it says something about where they are and what else they
 * can and cannot do, and the timestamp is the phone's, so the incident may be
 * considerably older than its arrival.
 */
export function arrivalLabel(alert: Alert): { value: string; warn: boolean } {
  switch ((alert.arrived_via || '').toUpperCase()) {
    case 'SMS':
      return {
        value: 'SMS FALLBACK — reporter had no data connection',
        warn: true,
      };
    case 'MESH':
      return {
        value: 'BLUETOOTH MESH — relayed via another handset, no network',
        warn: true,
      };
    case '':
      return { value: 'Data connection (no fallback recorded)', warn: false };
    default:
      return { value: String(alert.arrived_via).toUpperCase(), warn: false };
  }
}

// ── The rows ────────────────────────────────────────────────────────────────

export interface DetailRow {
  label: string;
  value: string;
  /** `warn` is rendered in the alert colour; `muted` for an absent value. */
  tone?: 'normal' | 'warn' | 'muted';
}

/** `#INC-` plus the first eight characters of the uuid, as the console does. */
export function incidentRef(id?: string): string {
  if (!id) return '#INC-0000';
  if (id.startsWith('#')) return id.toUpperCase();
  if (id.startsWith('INC-')) return `#${id.toUpperCase()}`;
  return `#INC-${id.slice(0, 8).toUpperCase()}`;
}

const absent = (label: string): DetailRow => ({ label, value: '—', tone: 'muted' });

/**
 * Everything the operator needs, in the order a dispatcher needs it.
 *
 * Returned as data rather than HTML so the decisions — what is shown, what is
 * flagged, what is admitted as missing — are testable without parsing markup.
 */
export function incidentDetailRows(
  alert: Alert,
  reporter: Reporter,
  usersMap: Record<string, any> = {},
  now: Date = new Date(),
): DetailRow[] {
  const rows: DetailRow[] = [];
  const waiting = minutesWaiting(alert, now);

  rows.push({
    label: 'RAISED',
    value: `${formatAge(alert.created_at, now)} · ${formatStamp(alert.created_at)}`,
    tone: alert.created_at ? 'normal' : 'muted',
  });

  // The single most consequential field on the popup. An unacknowledged
  // incident is one nobody has taken, and the tier timer is climbing.
  if (isUnacknowledged(alert)) {
    rows.push({
      label: 'ACKNOWLEDGED',
      value:
        waiting === null
          ? 'NO — nobody has taken this incident'
          : `NO — unclaimed for ${describeSpan(waiting * 60)}`,
      tone: 'warn',
    });
  } else if (alert.acknowledged_at) {
    rows.push({
      label: 'ACKNOWLEDGED',
      value: `${formatStamp(alert.acknowledged_at)} by ${
        alert.acknowledged_by ? resolveAssignee({ ...alert, assigned_to: alert.acknowledged_by }, usersMap) : 'unrecorded'
      }`,
    });
  }

  rows.push({
    label: 'SEVERITY',
    value: (alert.severity || alert.priority || 'NOT GRADED').toUpperCase(),
    tone: (alert.severity || alert.priority) ? 'normal' : 'muted',
  });

  rows.push({
    label: 'COMMAND TIER',
    value: alert.assigned_tier
      ? `${alert.assigned_tier.toUpperCase()}${
          alert.tier_assigned_at ? ` · since ${formatAge(alert.tier_assigned_at, now)}` : ''
        }`
      : 'UNIT (default)',
    tone: alert.assigned_tier ? 'normal' : 'muted',
  });

  rows.push({
    label: 'ASSIGNED TO',
    value: resolveAssignee(alert, usersMap),
    tone: alert.assigned_to && alert.assigned_to !== 'UNASSIGNED' ? 'normal' : 'warn',
  });

  if (alert.escalated_to_agency) {
    rows.push({ label: 'ESCALATED TO', value: alert.escalated_to_agency });
  }

  const arrival = arrivalLabel(alert);
  rows.push({
    label: 'CHANNEL',
    value: arrival.value,
    tone: arrival.warn ? 'warn' : 'normal',
  });

  rows.push({
    label: 'REPORTER',
    value: reporter.badge ? `${reporter.name} · ${reporter.badge}` : reporter.name,
    tone: reporter.identified ? 'normal' : 'warn',
  });
  rows.push({
    label: 'CONTACT',
    value: reporter.contact,
    tone: isDiallable(reporter.contact) ? 'normal' : 'muted',
  });
  rows.push({ label: 'REPORTER TYPE', value: reporter.type });

  const place = [alert.geo_lga, alert.geo_ward, alert.geo_pu].filter(Boolean).join(' › ');
  rows.push(place ? { label: 'LOCATION', value: place } : absent('LOCATION'));

  const lat = alert.latitude ?? alert.lat;
  const lng = alert.longitude ?? alert.lng;
  rows.push(
    Number.isFinite(lat) && Number.isFinite(lng)
      ? { label: 'COORDINATES', value: `${Number(lat).toFixed(5)}, ${Number(lng).toFixed(5)}` }
      : { label: 'COORDINATES', value: 'NO GPS FIX ON THIS REPORT', tone: 'warn' },
  );

  if ((alert.witness_count ?? 1) > 1) {
    rows.push({
      label: 'WITNESS REPORTS',
      value: `${alert.witness_count} reports folded into this marker`,
      tone: 'warn',
    });
  }

  const media = [...(alert.media_urls || []), ...(alert.attachments || [])];
  if (media.length > 0) {
    rows.push({ label: 'MEDIA', value: `${media.length} attached (open the dossier to view)` });
  }

  if (alert.local_id) {
    rows.push({ label: 'DEVICE REF', value: alert.local_id });
  }

  rows.push({ label: 'INCIDENT', value: incidentRef(alert.id) });

  return rows;
}

// ── The popup ───────────────────────────────────────────────────────────────

export interface PopupOptions {
  reporter: Reporter;
  usersMap?: Record<string, any>;
  now?: Date;
}

/**
 * The marker popup, as an HTML string, because that is what Leaflet takes.
 *
 * Every interpolated value passes through [escapeHtml]. The action buttons call
 * globals that LiveMap installs on `window`; the id is a uuid from the
 * database, and it is escaped anyway — an unescaped id in an `onclick` is a
 * script injection waiting for the day something other than the database
 * supplies one.
 */
export function incidentPopupHtml(alert: Alert, opts: PopupOptions): string {
  const { reporter, usersMap = {}, now = new Date() } = opts;

  // The card takes its surface colours from the SAME tokens as every other
  // panel in the console, which are the app's palette (see globals.css). It
  // used to carry its own light/dark hexes, which is how a product ends up
  // looking like two products: a card that is nearly the right grey is more
  // jarring than one that is obviously different.
  //
  // The popup is rendered inside the console's DOM, so the variables resolve,
  // and the theme switch needs no branch here at all — `.dark-theme` on
  // <body> redefines them. The status and severity colours below are the
  // exception: they are concatenated with alpha suffixes (`${colour}22`) and
  // used on a Leaflet div icon, and a `var()` cannot take either.
  const ink = 'var(--text-primary)';
  const dim = 'var(--text-dim)';
  const rule = 'var(--border)';
  const panel = 'var(--input-bg)';
  const warn = 'var(--duress)';

  const colour = statusColour(alert.status);
  const sevColour = severityColour(alert.severity || alert.priority);
  const rows = incidentDetailRows(alert, reporter, usersMap, now);
  const id = escapeHtml(alert.id);

  const rowHtml = rows
    .map((row) => {
      const valueColour = row.tone === 'warn' ? warn : row.tone === 'muted' ? dim : ink;
      const weight = row.tone === 'warn' ? 800 : 600;
      return `<div style="display:flex;gap:8px;align-items:baseline;padding:3px 0">
        <span style="flex:0 0 96px;font-size:9px;font-weight:800;letter-spacing:0.6px;color:${dim}">${escapeHtml(row.label)}</span>
        <span style="flex:1;font-size:11px;font-weight:${weight};color:${valueColour};word-break:break-word">${escapeHtml(row.value)}</span>
      </div>`;
    })
    .join('');

  const description = alert.description
    ? `<p style="font-size:11px;line-height:1.45;color:${ink};margin:8px 0 0;padding:8px;background:${panel};border-radius:8px">${escapeHtml(alert.description)}</p>`
    : `<p style="font-size:11px;color:${dim};margin:8px 0 0;font-style:italic">No description was given with this report.</p>`;

  const summary = alert.ai_summary
    ? `<p style="font-size:10px;line-height:1.45;color:${dim};margin:8px 0 0;padding:8px;border-left:2px solid ${colour};background:${panel}">
         <strong style="color:${colour};font-size:9px;letter-spacing:0.6px">TRIAGE SUMMARY</strong><br/>${escapeHtml(
           alert.ai_summary.length > 320 ? `${alert.ai_summary.slice(0, 320)}…` : alert.ai_summary,
         )}</p>`
    : '';

  /**
   * DATA ATTRIBUTES, NOT `onclick`.
   *
   * These buttons carried `onclick="window._hqDossier('…')"`, and the console's
   * own Content Security Policy is `script-src 'self' 'nonce-…'
   * 'strict-dynamic'` with no `'unsafe-inline'` — deliberately, for the reasons
   * written out at length in `lib/csp.ts`. A nonce cannot apply to an inline
   * EVENT HANDLER attribute, so the browser refuses every one of them:
   *
   *   Refused to execute inline event handler because it violates the
   *   following Content Security Policy directive: "script-src …"
   *
   * So every scripted action in a map popup — DOSSIER, DISPATCH, RESOLVE —
   * was dead on the console's landing screen, from the day that policy
   * shipped. The CSP is right; the popup was never revisited.
   *
   * `LiveMap` now listens once on the map container and reads these
   * attributes, which is CSP-safe and also removes the four `window._hq*`
   * globals the old arrangement needed. `scripts/check_no_inline_handlers.py`
   * fails on the next `onclick=` written into an HTML string.
   */
  const button = (label: string, bg: string, action: string) =>
    `<button type="button" data-hq-action="${action}" data-hq-id="${escapeHtml(id)}" style="flex:1 1 auto;min-width:74px;padding:7px 10px;background:${bg};color:#fff;border:none;border-radius:7px;font-size:10px;font-weight:800;letter-spacing:0.5px;cursor:pointer">${label}</button>`;

  const actions = [
    button('DOSSIER', '#4F46E5', 'dossier'),
    canDispatch(alert.status) ? button('DISPATCH', '#0277BD', 'dispatch') : '',
    canResolve(alert.status) ? button('RESOLVE', '#1B5E20', 'resolve') : '',
    isDiallable(reporter.contact)
      ? `<a href="tel:${escapeHtml(reporter.contact.replace(/[^\d+]/g, ''))}" style="flex:1 1 auto;min-width:74px;padding:7px 10px;background:#0F766E;color:#fff;border-radius:7px;font-size:10px;font-weight:800;letter-spacing:0.5px;text-align:center;text-decoration:none">CALL</a>`
      : '',
  ]
    .filter(Boolean)
    .join('');

  return `<div style="font-family:var(--font-outfit),var(--font-inter),sans-serif;min-width:272px;max-width:320px;color:${ink}">
      <div style="display:flex;align-items:center;justify-content:space-between;gap:8px">
        <strong style="color:${colour};font-size:13px;font-weight:900;text-transform:uppercase;letter-spacing:0.4px">${escapeHtml(
          alert.type || 'EMERGENCY',
        )}${alert.sub_type ? ` · ${escapeHtml(alert.sub_type)}` : ''}</strong>
        <span style="font-size:8px;font-weight:900;background:${sevColour}22;color:${sevColour};padding:2px 6px;border-radius:4px;border:1px solid ${sevColour}55;white-space:nowrap">${escapeHtml(
          (alert.severity || alert.priority || 'NOT GRADED').toUpperCase(),
        )}</span>
      </div>
      <div style="margin:6px 0 8px;font-size:9px;font-weight:900;letter-spacing:0.8px;color:${colour}">${escapeHtml(
        statusLabel(alert.status),
      )}</div>
      <div style="border-top:1px solid ${rule};border-bottom:1px solid ${rule};padding:6px 0;margin-bottom:2px">${rowHtml}</div>
      ${description}
      ${summary}
      <div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:10px">${actions}</div>
    </div>`;
}
