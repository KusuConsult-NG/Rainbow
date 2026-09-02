import type { Alert } from '@/app/dashboard/types';

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
}

export const NO_FILTERS: AlertFilters = {
  status: 'ALL',
  tier: 'ALL',
  lga: 'ALL',
  ward: 'ALL',
  pu: 'ALL',
};

/**
 * Collapses duplicate reports of the same event into one card.
 *
 * Many people phoning in one riot should not read as many riots, so active
 * alerts sharing LGA + ward + polling unit + type are merged and the survivor
 * carries `witness_count`. Resolved alerts are never merged — each keeps its
 * own history.
 *
 * The merged card inherits the FIRST alert's identity (its id, location and
 * timestamp) and is promoted to the most severe status seen in the group.
 */
export function clusterAlerts(rawAlerts: Alert[], enabled: boolean): Alert[] {
  if (!enabled) return rawAlerts;

  const clusterMap = new Map<string, { master: Alert; count: number }>();

  rawAlerts.forEach(alert => {
    if (alert.status === 'RESOLVED') {
      clusterMap.set(`resolved-${alert.id}`, { master: { ...alert }, count: 1 });
      return;
    }

    // Group active threats by LGA + Ward + PU + Type
    const lga = alert.geo_lga || 'STATE';
    const ward = alert.geo_ward || 'SECTOR';
    const pu = alert.geo_pu || 'AREA';
    const key = `${lga}_${ward}_${pu}_${alert.type}`;

    if (!clusterMap.has(key)) {
      clusterMap.set(key, { master: { ...alert }, count: 1 });
    } else {
      const item = clusterMap.get(key)!;
      item.count += 1;
      if (alert.status === 'DURESS' || alert.priority === 'CRITICAL') {
        item.master.status = alert.status;
        item.master.priority = 'CRITICAL';
      }
    }
  });

  const result: Alert[] = [];
  clusterMap.forEach(({ master, count }) => {
    (master as unknown as { witness_count: number }).witness_count = count;
    result.push(master);
  });

  return result;
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
 */
function geoMatches(alertValue: string | undefined, target: string): boolean {
  const a = (alertValue || '').trim().toLowerCase();
  const t = target.trim().toLowerCase();
  return a === t || a.includes(t) || t.includes(a);
}

export function filterAlerts(alerts: Alert[], filters: AlertFilters): Alert[] {
  return alerts.filter(a => {
    if (filters.status === 'CRITICAL') {
      if (a.status !== 'DURESS' && a.priority !== 'CRITICAL') return false;
    } else if (filters.status === 'SMS_FALLBACK') {
      if (!isSmsFallback(a)) return false;
    } else if (filters.status !== 'ALL' && a.status !== filters.status) return false;

    if (filters.tier !== 'ALL' && a.assigned_to !== filters.tier) return false;
    if (filters.lga !== 'ALL' && !geoMatches(a.geo_lga, filters.lga)) return false;
    if (filters.ward !== 'ALL' && !geoMatches(a.geo_ward, filters.ward)) return false;
    if (filters.pu !== 'ALL' && !geoMatches(a.geo_pu, filters.pu)) return false;

    return true;
  });
}
