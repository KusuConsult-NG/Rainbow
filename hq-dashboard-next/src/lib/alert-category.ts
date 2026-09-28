import type { Alert } from '@/app/dashboard/types';

/**
 * The reporting category of an incident, for sorting and filtering.
 *
 * ## Where a category comes from
 *
 * The app writes `alerts.type` as `'<label> - <subtype>'` —
 * `'Kidnap - Immediate Abduction'` — so the ten categories the reporting flow
 * offers have always been a prefix inside a free-text column rather than
 * something a dispatcher could sort by.
 *
 * The migration beside this file adds `alerts.category` as a STORED GENERATED
 * column over that same prefix, so the database can answer "every kidnapping
 * open right now" directly and every historical row is covered. This file is
 * the console's side of that: it prefers the generated column and falls back to
 * deriving the prefix itself, because the console has to keep working against a
 * database where the migration has not been applied yet.
 *
 * The fallback is not a second implementation of the rule — it is the same
 * `split_part(type, ' - ', 1)`, written once here and asserted against the
 * column's own output in the tests.
 */

/** Incidents with no category at all, grouped under one honest label. */
export const UNCATEGORISED = 'UNCATEGORISED';

/**
 * The category of one alert.
 *
 * Prefers the generated column. Falls back to the prefix of `type` so a console
 * running ahead of its database still sorts correctly rather than showing every
 * incident as uncategorised.
 *
 * Never invents one: a row with no `type` reads as [UNCATEGORISED] rather than
 * being quietly filed under the first category in the list. The same reasoning
 * as the severity that is reported as UNKNOWN instead of assumed to be HIGH.
 */
export function categoryOf(alert: Pick<Alert, 'type'> & { category?: string | null }): string {
  const generated = alert.category?.trim();
  if (generated) return generated.toUpperCase();

  const derived = (alert.type ?? '').split(' - ')[0]?.trim();
  return derived ? derived.toUpperCase() : UNCATEGORISED;
}

/**
 * Every category present in these alerts, most frequent first.
 *
 * Ordered by how many incidents carry it rather than alphabetically: a filter
 * control is read under pressure, and the categories actually happening should
 * be the ones nearest the top. Ties break alphabetically so the order is
 * stable between renders rather than depending on the order rows arrived in.
 *
 * UNCATEGORISED is always last when present, whatever its count — it is not a
 * kind of incident, it is the absence of one, and it should not head a list of
 * real categories.
 */
export function categoriesPresent(alerts: Alert[]): string[] {
  const counts = new Map<string, number>();
  for (const a of alerts) {
    const c = categoryOf(a);
    counts.set(c, (counts.get(c) ?? 0) + 1);
  }

  return [...counts.entries()]
    .sort((x, y) => {
      if (x[0] === UNCATEGORISED) return 1;
      if (y[0] === UNCATEGORISED) return -1;
      if (y[1] !== x[1]) return y[1] - x[1];
      return x[0].localeCompare(y[0]);
    })
    .map(([name]) => name);
}

/** How many incidents carry each category. */
export function categoryCounts(alerts: Alert[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const a of alerts) {
    const c = categoryOf(a);
    counts[c] = (counts[c] ?? 0) + 1;
  }
  return counts;
}

/**
 * Whether an alert belongs to the chosen category.
 *
 * 'ALL' selects everything, which is what an untouched filter means.
 */
export function matchesCategory(
  alert: Pick<Alert, 'type'> & { category?: string | null },
  chosen: string,
): boolean {
  if (!chosen || chosen === 'ALL') return true;
  return categoryOf(alert) === chosen.toUpperCase();
}

/**
 * What the filter control shows for a category.
 *
 * The stored value is the label the app used, in whatever case it was written
 * — 'Kidnap', 'Community attack', 'PANIC SOS'. The console's chrome is
 * upper-case throughout, and these are compared upper-cased, so this exists to
 * keep the displayed form in one place rather than spread across the markup.
 */
export function categoryLabel(category: string): string {
  if (category === UNCATEGORISED) return 'UNCATEGORISED';
  return category.toUpperCase();
}
