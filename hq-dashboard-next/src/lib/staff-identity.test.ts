import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  DEFAULT_STAFF_EMAIL_DOMAIN,
  emailForBadge,
  staffEmailDomain,
} from './staff-identity';

const ORIGINAL = process.env.NEXT_PUBLIC_STAFF_EMAIL_DOMAIN;

afterEach(() => {
  if (ORIGINAL === undefined) delete process.env.NEXT_PUBLIC_STAFF_EMAIL_DOMAIN;
  else process.env.NEXT_PUBLIC_STAFF_EMAIL_DOMAIN = ORIGINAL;
  vi.restoreAllMocks();
});

describe('emailForBadge', () => {
  it('turns a badge into an address on the deployed domain', () => {
    expect(emailForBadge('HQ-001'))
      .toBe(`hq-001@${DEFAULT_STAFF_EMAIL_DOMAIN}`);
  });

  // Case and whitespace: the same badge typed three ways has to reach ONE
  // account, because every way it does not is a duplicate.
  it.each(['HQ-001', 'hq-001', '  Hq-001  '])('normalises %o', (typed) => {
    expect(emailForBadge(typed)).toBe(`hq-001@${DEFAULT_STAFF_EMAIL_DOMAIN}`);
  });

  // A badge with slashes in it is how the police number their officers.
  it('leaves a badge with slashes alone apart from the case', () => {
    expect(emailForBadge('NP/JOS/001'))
      .toBe(`np/jos/001@${DEFAULT_STAFF_EMAIL_DOMAIN}`);
  });

  // This is how an account on any OTHER domain signs in at all, including the
  // duplicates that already exist. Removing it would lock those officers out.
  it('passes an address through when one is typed', () => {
    expect(emailForBadge('a.musa@gmail.com')).toBe('a.musa@gmail.com');
    expect(emailForBadge('  A.Musa@Gmail.com ')).toBe('a.musa@gmail.com');
  });

  it('returns nothing for nothing, rather than a bare domain', () => {
    expect(emailForBadge('')).toBe('');
    expect(emailForBadge('   ')).toBe('');
  });
});

describe('staffEmailDomain', () => {
  it('is the deployed domain when nothing is configured', () => {
    delete process.env.NEXT_PUBLIC_STAFF_EMAIL_DOMAIN;
    expect(staffEmailDomain()).toBe(DEFAULT_STAFF_EMAIL_DOMAIN);
  });

  it('takes a configured domain', () => {
    process.env.NEXT_PUBLIC_STAFF_EMAIL_DOMAIN = 'Plateau.Example.NG';
    expect(staffEmailDomain()).toBe('plateau.example.ng');
    expect(emailForBadge('HQ-001')).toBe('hq-001@plateau.example.ng');
  });

  // A malformed domain makes every staff sign-in fail in a way that is
  // indistinguishable from a wrong password, which is the worst way for a
  // configuration mistake to present.
  it.each(['no-dots', 'two@ats.ng', 'has space.ng', '  '])(
    'refuses %o and says so', (bad) => {
      process.env.NEXT_PUBLIC_STAFF_EMAIL_DOMAIN = bad;
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      expect(staffEmailDomain()).toBe(DEFAULT_STAFF_EMAIL_DOMAIN);
      // Blank is "not configured", not "misconfigured" — no warning for it.
      if (bad.trim()) expect(warn).toHaveBeenCalled();
    },
  );
});
