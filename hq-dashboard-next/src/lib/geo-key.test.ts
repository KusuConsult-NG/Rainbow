// Two files spell four Mangu wards differently, so the console's ward filter
// selected nothing in them and row-level security refused the officer posted
// there. These assertions mirror geo_key_behaviour_test.sql, which proves the
// same rule inside PostgreSQL — the two have to agree, or the board would list
// incidents whose actions all fail.
import { describe, expect, it } from 'vitest';
import { geoKey, geoMatchesKeyed } from './geo-key';

describe('the key', () => {
  it('makes the two spellings of Gindiri the same ward', () => {
    expect(geoKey('GINDIRI  I')).toBe(geoKey('GINDIRI  1'));
    expect(geoKey('GINDIRI  II')).toBe(geoKey('GINDIRI  11'));
    expect(geoKey('MANGU  I')).toBe(geoKey('MANGU  1'));
    expect(geoKey('MANGU  II')).toBe(geoKey('MANGU  11'));
  });

  it('rewrites III as 111, not as 1 followed by 11', () => {
    expect(geoKey('SOMEWHERE III')).toBe('SOMEWHERE 111');
  });

  it('folds case and collapses runs of whitespace', () => {
    expect(geoKey('  jos   north ')).toBe('JOS NORTH');
  });

  it('is empty for a name that is missing or blank', () => {
    expect(geoKey(undefined)).toBe('');
    expect(geoKey(null)).toBe('');
    expect(geoKey('   ')).toBe('');
  });

  it('leaves an I that is not a trailing numeral alone', () => {
    expect(geoKey('IKOT IDEM')).toBe('IKOT IDEM');
    expect(geoKey("GYEL 'A'")).toBe("GYEL 'A'");
    expect(geoKey('RIYOM')).toBe('RIYOM');
  });

  it('keeps genuinely different wards apart', () => {
    // The failure direction that matters. A key too aggressive would give a
    // ward commander the ward next door, which is the authority leak the
    // scoping migration exists to close.
    expect(geoKey('GINDIRI  I')).not.toBe(geoKey('GINDIRI  II'));
    expect(geoKey('MANGU  1')).not.toBe(geoKey('MANGU  11'));
    // KADUN / KADUNU are one letter apart, which is a question about Plateau's
    // geography rather than a notation difference. Not folded, on purpose.
    expect(geoKey('KADUN')).not.toBe(geoKey('KADUNU'));
    expect(geoKey('DAMWAI')).not.toBe(geoKey('KAMWAI'));
  });

  it('agrees with the SQL key on the shape of the output', () => {
    // public.geo_key() upper-cases and single-spaces; a divergence here means
    // the console and RLS disagree about which ward an officer commands.
    for (const name of ['gindiri  i', 'Mangu  II', ' barakin  ladi ', "gyel 'a'"]) {
      const key = geoKey(name);
      expect(key).toBe(key.toUpperCase());
      expect(key).not.toMatch(/\s{2,}/);
      expect(key).toBe(key.trim());
    }
  });
});

describe('matching a filter selection', () => {
  it('matches an incident filed in Roman against a ward selected in Arabic', () => {
    // The defect: this was false, so the filter emptied the board.
    expect(geoMatchesKeyed('GINDIRI  I', 'GINDIRI  1')).toBe(true);
  });

  it('does not match the ward next door', () => {
    expect(geoMatchesKeyed('GINDIRI  I', 'GINDIRI  11')).toBe(false);
    expect(geoMatchesKeyed('NARAGUTA', 'GANGARE')).toBe(false);
  });

  it('does not let a numbered ward swallow its sibling', () => {
    // 'MANGU 11' CONTAINS 'MANGU 1', so plain containment showed MANGU 11's
    // incidents under a MANGU 1 filter and inflated its duress counter.
    expect(geoMatchesKeyed('MANGU  11', 'MANGU  1')).toBe(false);
    expect(geoMatchesKeyed('MANGU  II', 'MANGU  1')).toBe(false);
    expect(geoMatchesKeyed('GINDIRI  11', 'GINDIRI  I')).toBe(false);
    // Same number, different notation, is still the same ward.
    expect(geoMatchesKeyed('MANGU  11', 'MANGU  II')).toBe(true);
  });

  it('still matches a numbered ward against an unnumbered selection', () => {
    // An LGA-level selection must not be defeated by the ward's number.
    expect(geoMatchesKeyed('MANGU  1', 'MANGU')).toBe(true);
    expect(geoMatchesKeyed('MANGU', 'MANGU  1')).toBe(true);
  });

  it('still matches loosely on inconsistent field entry', () => {
    // Deliberate: under-matching hides live incidents from the officer
    // responsible for them.
    expect(geoMatchesKeyed('Jos North', 'JOS NORTH LGA')).toBe(true);
    expect(geoMatchesKeyed('JOS NORTH', 'jos north')).toBe(true);
  });

  it('lets an unlocated incident through any geographic filter', () => {
    // Fail-open, matching alert_in_my_area() and asserted in
    // alert-display.test.ts. An unlocated emergency must not vanish because
    // the operator narrowed the view.
    expect(geoMatchesKeyed(undefined, 'JOS NORTH')).toBe(true);
    expect(geoMatchesKeyed('', 'GINDIRI  1')).toBe(true);
  });
});
