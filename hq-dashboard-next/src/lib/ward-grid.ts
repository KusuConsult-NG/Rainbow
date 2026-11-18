/**
 * The statewide ward grid: open incidents per ward, for all 207 wards of
 * Plateau State.
 *
 * Phase 1 of the intelligence layer. It replaces a grid of 0.04-degree squares
 * drawn only over Jos (9.78 to 10.06 N, 8.78 to 9.06 E): an incident in Wase or
 * Bokkos fell outside every square and simply did not appear on it, and a
 * square cut across ward lines, so it answered no question a commander asks.
 *
 * A cell is a WARD, drawn as its centroid's circle (lib/ward_centroids.ts, the
 * same source the app resolves an incident's ward from), so a cell means the
 * same thing as the `geo_ward` on the incident.
 *
 * It counts OPEN incidents — the cards the console shows, after clustering —
 * and carries their corroboration, so a ward with three unconfirmed single
 * reports reads differently from a ward with one strongly corroborated attack.
 * It is a picture of now, not a forecast: forecasting is phase 4.
 */

import type { Alert } from '@/app/dashboard/types';
import { isLiveIncident } from './alert-display';
import type { CorroborationLevel } from './corroboration';
import { geoKey } from './geo-key';
import { wardCentroids, type WardCentroid } from './ward_centroids';

export type WardHeat = 'MODERATE' | 'ELEVATED' | 'CRITICAL';

/** Open incidents at which a ward reads ELEVATED, and CRITICAL. */
export const ELEVATED_AT = 2;
export const CRITICAL_AT = 4;

export interface WardCell {
  ward: WardCentroid;
  /** Open incidents (cards) in the ward. */
  open: number;
  heat: WardHeat;
  /** The best-corroborated open incident here. */
  strongest: CorroborationLevel;
  /** How many of the open incidents are corroborated or strong. */
  corroborated: number;
  /** Distinct incident types, for the popup. */
  types: string[];
}

export interface WardGrid {
  cells: WardCell[];
  /**
   * Open incidents whose ward is missing or not one of the 207: shown on the
   * board, but in no cell. Said out loud, so an empty grid is never read as an
   * empty state.
   */
  unplaced: number;
}

const RANK: Record<CorroborationLevel, number> = { UNCONFIRMED: 0, CORROBORATED: 1, STRONG: 2 };

// Compared by geoKey (lib/geo-key.ts), the same key the database's row-level
// security and the app use: the ward file writes "GINDIRI  II" with two spaces
// and a Roman numeral, a USSD menu ward reads "GINDIRI  11", and both are one
// ward. A plain trim matched neither variant.
const key = (lga: string, ward: string) => `${geoKey(lga)}|${geoKey(ward)}`;

const INDEX = new Map(wardCentroids.map((w) => [key(w.lga, w.ward), w]));

export function heatOf(open: number): WardHeat {
  if (open >= CRITICAL_AT) return 'CRITICAL';
  if (open >= ELEVATED_AT) return 'ELEVATED';
  return 'MODERATE';
}

/** The grid for these cards (clustered, corroborated alerts). */
export function wardGrid(cards: Alert[]): WardGrid {
  const byWard = new Map<string, Alert[]>();
  let unplaced = 0;

  for (const a of cards) {
    if (!isLiveIncident(a)) continue;
    const k = key(a.geo_lga ?? '', a.geo_ward ?? '');
    if (!INDEX.has(k)) {
      unplaced++;
      continue;
    }
    const list = byWard.get(k) ?? [];
    list.push(a);
    byWard.set(k, list);
  }

  const cells: WardCell[] = [];
  byWard.forEach((list, k) => {
    const levels = list.map((a) => a.corroboration?.level ?? 'UNCONFIRMED');
    const strongest = levels.reduce<CorroborationLevel>(
      (best, l) => (RANK[l] > RANK[best] ? l : best),
      'UNCONFIRMED',
    );
    cells.push({
      ward: INDEX.get(k)!,
      open: list.length,
      heat: heatOf(list.length),
      strongest,
      corroborated: levels.filter((l) => l !== 'UNCONFIRMED').length,
      types: [...new Set(list.map((a) => a.type || 'Distress'))],
    });
  });

  // Hottest first, so the busiest ward is drawn on top.
  cells.sort((a, b) => a.open - b.open);
  return { cells, unplaced };
}
