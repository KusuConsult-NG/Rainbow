/**
 * How a badge becomes an email, and why that is one decision and not two.
 *
 * Staff do not sign in with an email. They type a badge — `HQ-001`,
 * `NP/JOS/001` — and this turns it into one. The handset does the same thing in
 * `lib/services/auth_service.dart`, and each had its own copy of the domain:
 *
 *     const emailDomain = badgeId.toLowerCase().includes('@')
 *       ? '' : '@operationrainbow.plateau.gov.ng';
 *
 * The domain is the second half of the primary key of a person. Change it, or
 * provision an account under a different one, and the SAME badge resolves to a
 * DIFFERENT `auth.users` row — a second account for one officer. The production
 * project has exactly that: duplicate accounts across two email domains.
 *
 * It is not a cosmetic duplicate. The posting (`geo_lga`, `geo_ward`) is on one
 * of the two accounts and the officer signs into the other, where it is blank —
 * so `alert_in_my_area()` matches nothing and their board is empty with the
 * incidents right there. The OneSignal player id is on one of them too, so an
 * escalation either misses them or tells them twice.
 *
 * `profiles.badge_number` would have caught it and does not: a plain index, no
 * uniqueness, so two accounts may hold one badge.
 *
 * `NEXT_PUBLIC_STAFF_EMAIL_DOMAIN` overrides it. Public on purpose — it is the
 * second half of a USERNAME, not a secret, and the one in the bundle is the one
 * sign-in must use. `scripts/check_one_staff_identity.py` asserts this default
 * and the handset's are the same string, because two literals that must agree,
 * in two languages, is the shape that produced the duplicates.
 *
 * See E2E_AUDIT_REPORT.md T-99.
 */

/** The domain every staff account on this deployment was created under. */
export const DEFAULT_STAFF_EMAIL_DOMAIN = 'operationrainbow.plateau.gov.ng';

/** The domain this build turns a badge into an email with. */
export function staffEmailDomain(): string {
  const configured = (process.env.NEXT_PUBLIC_STAFF_EMAIL_DOMAIN ?? '')
    .trim()
    .toLowerCase();
  if (!configured) return DEFAULT_STAFF_EMAIL_DOMAIN;
  // A domain with an @ or a space in it produces an address no account can have,
  // and a sign-in that can never succeed looks exactly like a wrong password.
  if (configured.includes('@') || /\s/.test(configured) || !configured.includes('.')) {
    console.warn(
      `[STAFF_IDENTITY] NEXT_PUBLIC_STAFF_EMAIL_DOMAIN is "${configured}", ` +
        `which is not a domain. Using ${DEFAULT_STAFF_EMAIL_DOMAIN}.`,
    );
    return DEFAULT_STAFF_EMAIL_DOMAIN;
  }
  return configured;
}

/**
 * The email for what somebody typed into the badge field.
 *
 * An input already containing `@` is taken as an email, which is how an account
 * under any other domain signs in at all — including the duplicates that
 * already exist.
 */
export function emailForBadge(badgeOrEmail: string): string {
  const trimmed = (badgeOrEmail ?? '').trim().toLowerCase();
  if (!trimmed) return trimmed;
  if (trimmed.includes('@')) return trimmed;
  return `${trimmed}@${staffEmailDomain()}`;
}
