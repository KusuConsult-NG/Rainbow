import { describe, expect, it } from 'vitest';

import type { Alert } from '@/app/dashboard/types';
import {
  UNCATEGORISED,
  categoriesPresent,
  categoryCounts,
  categoryLabel,
  categoryOf,
  matchesCategory,
} from './alert-category';

function alert(over: Partial<Alert> & { category?: string | null } = {}): Alert {
  return {
    id: 'a1',
    type: 'Kidnap - Immediate Abduction',
    status: 'OPEN',
    created_at: '2026-09-28T12:00:00Z',
    ...over,
  } as Alert;
}

/**
 * The exact rule the generated column applies, so the fallback can be checked
 * against it rather than against my memory of it.
 *
 *   category TEXT GENERATED ALWAYS AS (split_part(type, ' - ', 1)) STORED
 */
function splitPart(value: string, sep: string, index: number): string {
  const parts = value.split(sep);
  return parts[index - 1] ?? '';
}

describe('the category of one incident', () => {
  it('uses the generated column when the database has it', () => {
    expect(categoryOf(alert({ category: 'Kidnap' }))).toBe('KIDNAP');
  });

  it('falls back to the prefix of type when it does not', () => {
    // The console has to keep working against a database the migration has not
    // reached yet. Showing every incident as uncategorised would be a worse
    // answer than deriving the same value the column will hold.
    expect(categoryOf(alert({ type: 'Community attack - Armed Invasion' })))
      .toBe('COMMUNITY ATTACK');
  });

  it('derives exactly what the generated column would store', () => {
    const types = [
      'Kidnap - Immediate Abduction',
      'Community attack - Armed Invasion',
      'Domestic violence - Ongoing Assault',
      'PANIC SOS',
      'Cattle rustling - Herd Taken',
    ];
    for (const type of types) {
      expect(categoryOf(alert({ type }))).toBe(
        splitPart(type, ' - ', 1).trim().toUpperCase(),
      );
    }
  });

  it('keeps a type with no subtype whole', () => {
    // split_part returns the whole string when the separator is absent, and a
    // panic press is stored as 'PANIC SOS'. That IS how a dispatcher thinks of
    // it, so it becomes its own category rather than being discarded.
    expect(categoryOf(alert({ type: 'PANIC SOS' }))).toBe('PANIC SOS');
  });

  it('does not invent a category for a row that has none', () => {
    // The same reasoning as the severity reported as UNKNOWN rather than
    // assumed to be HIGH: surface the absence instead of painting over it.
    expect(categoryOf(alert({ type: '' }))).toBe(UNCATEGORISED);
    expect(categoryOf(alert({ type: undefined as unknown as string }))).toBe(UNCATEGORISED);
  });

  it('prefers the column over the prefix when they disagree', () => {
    // They cannot disagree in the database — the column is generated from type
    // — but a caller could hand us a shape where they do, and the column is the
    // value the database will filter on.
    expect(categoryOf(alert({ type: 'Flood - Rising Water', category: 'Kidnap' })))
      .toBe('KIDNAP');
  });

  it('ignores a column that is blank rather than trusting it', () => {
    expect(categoryOf(alert({ type: 'Fire - Structure', category: '  ' })))
      .toBe('FIRE');
  });
});

describe('the categories on the board', () => {
  it('lists the most frequent first, because the control is read in a hurry', () => {
    const alerts = [
      alert({ id: '1', type: 'Fire - Structure' }),
      alert({ id: '2', type: 'Kidnap - Held Hostage' }),
      alert({ id: '3', type: 'Kidnap - Attempted Kidnap' }),
      alert({ id: '4', type: 'Kidnap - Immediate Abduction' }),
      alert({ id: '5', type: 'Flood - Rising Water' }),
      alert({ id: '6', type: 'Flood - Rising Water' }),
    ];
    expect(categoriesPresent(alerts)).toEqual(['KIDNAP', 'FLOOD', 'FIRE']);
  });

  it('breaks ties alphabetically so the order does not shuffle between renders', () => {
    const alerts = [
      alert({ id: '1', type: 'Flood - Rising Water' }),
      alert({ id: '2', type: 'Fire - Structure' }),
    ];
    expect(categoriesPresent(alerts)).toEqual(['FIRE', 'FLOOD']);
  });

  it('puts UNCATEGORISED last however many there are', () => {
    // It is not a kind of incident; it is the absence of one. It should not
    // head a list of real categories just because it is common.
    const alerts = [
      alert({ id: '1', type: '' }),
      alert({ id: '2', type: '' }),
      alert({ id: '3', type: '' }),
      alert({ id: '4', type: 'Kidnap - Held Hostage' }),
    ];
    expect(categoriesPresent(alerts)).toEqual(['KIDNAP', UNCATEGORISED]);
  });

  it('counts each category', () => {
    const alerts = [
      alert({ id: '1', type: 'Kidnap - Held Hostage' }),
      alert({ id: '2', type: 'Kidnap - Attempted Kidnap' }),
      alert({ id: '3', type: 'Fire - Structure' }),
    ];
    expect(categoryCounts(alerts)).toEqual({ KIDNAP: 2, FIRE: 1 });
  });

  it('is empty for an empty board rather than throwing', () => {
    expect(categoriesPresent([])).toEqual([]);
    expect(categoryCounts([])).toEqual({});
  });
});

describe('filtering by category', () => {
  it('an untouched filter selects everything', () => {
    expect(matchesCategory(alert(), 'ALL')).toBe(true);
    expect(matchesCategory(alert(), '')).toBe(true);
  });

  it('selects the chosen category and nothing else', () => {
    expect(matchesCategory(alert({ type: 'Kidnap - Held Hostage' }), 'KIDNAP')).toBe(true);
    expect(matchesCategory(alert({ type: 'Fire - Structure' }), 'KIDNAP')).toBe(false);
  });

  it('does not care how the caller cased it', () => {
    expect(matchesCategory(alert({ type: 'Kidnap - Held Hostage' }), 'kidnap')).toBe(true);
  });

  it('can select the uncategorised incidents deliberately', () => {
    // A dispatcher needs to be able to go and look at exactly these.
    expect(matchesCategory(alert({ type: '' }), UNCATEGORISED)).toBe(true);
    expect(matchesCategory(alert({ type: 'Fire - Structure' }), UNCATEGORISED)).toBe(false);
  });
});

describe('what the control says', () => {
  it('shows the category upper-cased, like the rest of the chrome', () => {
    expect(categoryLabel('KIDNAP')).toBe('KIDNAP');
    expect(categoryLabel('Community attack')).toBe('COMMUNITY ATTACK');
  });

  it('names the absence plainly', () => {
    expect(categoryLabel(UNCATEGORISED)).toBe('UNCATEGORISED');
  });
});
