import type { Alert } from '@/app/dashboard/types';
import { matchesCategory } from './alert-category';
import { geoMatchesKeyed } from './geo-key';

/**
 * What HQ actually sees.
 *
 * These two functions decide which incidents reach the operator's screen and
 * which are folded away, so they are the highest-consequence logic in the
 * console. They lived inside a 3,000-line page component and had no tests;
 * they are pure, so there was no reason for that beyond where they happened to
 * be written.
 *
 * Extracted verbatim — same behaviour, now testable. See alert-display.test.ts.
 */

/** The filter selections the operator has made. */
export interface AlertFilters {
  status: string;
  tier: string;
  lga: string;
  ward: string;
  pu: string;
  /** Reporting category, or 'ALL'. See alert-category.ts. */
  category: string;
}

export const NO_FILTERS: AlertFilters = {
  status: 'ALL',
  tier: 'ALL',
  lga: 'ALL',
  ward: 'ALL',
  pu: 'ALL',
  category: 'ALL',
};

/**
 * Reports of the same event that arrive further apart than this are NOT the
 * same event. Witnesses to one riot phone in within minutes of each other; two
 * fires in the same polling unit a day apart are two fires.
 */
export const CLUSTER_WINDOW_MS = 60 * 60 * 1000;

/**
 * Collapses duplicate reports of the same event into one card.
 *
 * Many people phoning in one riot should not read as many riots, so active
 * alerts sharing LGA + ward + polling unit + type — AND filed within
 * CLUSTER_WINDOW_MS of the first report — are merged. Resolved alerts are
 * never merged; each keeps its own history.
 *
 * The merged card inherits the FIRST report's identity for display, is
 * promoted to the most severe status seen in the group, and — this is the part
 * that used to be missing — carries `member_ids` for every report in it. The
 * write paths act on all of them, so acting on the card can no longer close
 * one report while the others stay open and invisible.
 *
 * The time window is the other half of that fix: the previous key had no
 * temporal component at all despite the code calling itself
 * "spatial-temporal", so two genuinely separate incidents in the same place
 * on different days collapsed into one.
 */
export function clusterAlerts(
  rawAlerts: Alert[],
  enabled: boolean,
  windowMs: number = CLUSTER_WINDOW_MS,
): Alert[] {
  if (!enabled) return rawAlerts;

  type Cluster = { master: Alert; ids: string[]; anchor: number | null };
  // Each place+type key can hold several clusters, one per time window.
  const clusters = new Map<string, Cluster[]>();
  const order: Cluster[] = [];

  const stamp = (a: Alert): number | null => {
    const t = a.created_at ? Date.parse(a.created_at) : NaN;
    return Number.isNaN(t) ? null : t;
  };

  rawAlerts.forEach(alert => {
    if (alert.status === 'RESOLVED') {
      const c: Cluster = { master: { ...alert }, ids: [alert.id], anchor: null };
      order.push(c);
      return;
    }

    const lga = alert.geo_lga || 'STATE';
    const ward = alert.geo_ward || 'SECTOR';
    const pu = alert.geo_pu || 'AREA';
    const key = `${lga}_${ward}_${pu}_${alert.type}`;
    const at = stamp(alert);

    const existing = clusters.get(key) ?? [];
    // Join the newest cluster at this place if this report falls inside its
    // window. Reports with no usable timestamp join regardless — they cannot
    // be shown to be a different event, and hiding them is worse.
    const target = existing.find(c =>
      at === null || c.anchor === null || Math.abs(at - c.anchor) <= windowMs,
    );

    if (!target) {
      const c: Cluster = { master: { ...alert }, ids: [alert.id], anchor: at };
      existing.unshift(c);
      clusters.set(key, existing);
      order.push(c);
    } else {
      target.ids.push(alert.id);
      if (isCriticalAlert(alert)) {
        target.master.status = alert.status;
        // Promote BOTH: `severity` is what this module and the database agree
        // on, `priority` is what the page renders on the incident card. Setting
        // only one leaves a card that reads CRITICAL in the list and something
        // milder when opened.
        target.master.severity = 'CRITICAL';
        target.master.priority = 'CRITICAL';
      }
    }
  });

  return order.map(({ master, ids }) => {
    master.member_ids = ids;
    master.witness_count = ids.length;
    return master;
  });
}

/**
 * Whether HQ should treat this as a critical incident.
 *
 * Checks BOTH fields, and that is deliberate.
 *
 * `severity` is the column: both apps write it, and nothing writes `priority`
 * to the database — the mobile maps its own priority enum onto `severity`
 * (`'severity': priority.name.toUpperCase()`), and the console's writes set
 * `severity` too. `priority` reaches this module only because the dashboard
 * page copies it across as it loads rows (`priority: d.severity || 'HIGH'`),
 * some 200 lines from here. That mapping is why the filter works today, and it
 * is invisible from this file — these functions are exported and tested on
 * their own, so a caller passing rows straight from the database would get a
 * CRITICAL filter that quietly matched only DURESS.
 *
 * Reading only `severity` was the first attempt and it was wrong: it let a
 * MEDIUM severity mask a CRITICAL priority, which is how `clusterAlerts`
 * promotes a card. On a filter whose job is to surface the worst incidents,
 * either field saying CRITICAL has to be enough — showing one incident too
 * many costs an operator a glance, and dropping one costs more than that.
 *
 * A duress alert is critical whatever its severity says; that is the point of
 * a duress code.
 */
export function isCriticalAlert(a: Alert): boolean {
  const critical = (v?: string) => (v || '').toUpperCase() === 'CRITICAL';
  return a.status === 'DURESS' || critical(a.severity) || critical(a.priority);
}

/** True when the alert appears to have arrived over the SMS fallback path. */
function isSmsFallback(a: Alert): boolean {
  const extra = a as unknown as { via?: string; source?: string; channel?: string };
  return (
    (a.description || '').includes('[OFFLINE_SMS]') ||
    (a.description || '').includes('[SMS]') ||
    extra.via === 'SMS_GATEWAY' ||
    extra.source === 'SMS' ||
    extra.channel === 'SMS'
  );
}

/**
 * Geography is matched loosely — exact, or either name containing the other.
 * Field-entered place names are inconsistent ("Jos North" vs "JOS NORTH LGA"),
 * and under-matching here hides live incidents from the officer responsible
 * for them.
 *
 * Both sides are keyed first, because loose matching was not loose enough for
 * the one difference that actually occurs in the data: the app files a ward as
 * "GINDIRI  I" and the map offers "GINDIRI  1", and neither string contains the
 * other. See geo-key.ts, and public.geo_key() which row-level security uses.
 */
const geoMatches = geoMatchesKeyed;

export function filterAlerts(alerts: Alert[], filters: AlertFilters): Alert[] {
  return alerts.filter(a => {
    if (filters.status === 'CRITICAL') {
      if (!isCriticalAlert(a)) return false;
    } else if (filters.status === 'SMS_FALLBACK') {
      if (!isSmsFallback(a)) return false;
    } else if (filters.status !== 'ALL' && a.status !== filters.status) return false;

    // Tier, not assignee. This compared `assigned_to` — a uuid column — against
    // 'WARD'/'LGA'/'HQ', so it could only ever have matched rows the database
    // refuses to accept: it has never selected anything. `assigned_to` is still
    // consulted as a fallback, for any row where a tier label did land in it.
    if (filters.tier !== 'ALL'
        && a.assigned_tier !== filters.tier
        && !(a.assigned_tier == null && a.assigned_to === filters.tier)) {
      return false;
    }
    if (filters.lga !== 'ALL' && !geoMatches(a.geo_lga, filters.lga)) return false;
    if (filters.ward !== 'ALL' && !geoMatches(a.geo_ward, filters.ward)) return false;
    if (filters.pu !== 'ALL' && !geoMatches(a.geo_pu, filters.pu)) return false;
    if (!matchesCategory(a, filters.category)) return false;

    return true;
  });
}
