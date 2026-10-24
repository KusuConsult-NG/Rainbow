/// How a badge becomes an email, and why that is one decision and not two.
///
/// Staff do not sign in with an email. They type a badge — `HQ-001`,
/// `NP/JOS/001` — and the app turns it into one:
///
///     final email = trimmed.contains('@')
///         ? trimmed
///         : '$trimmed@operationrainbow.plateau.gov.ng';
///
/// The console does the same thing, in `src/app/login/page.tsx`, with its own
/// copy of that domain.
///
/// ## What that cost
///
/// The domain is the second half of the primary key of a person. Change it, or
/// provision an account under a different one, and the SAME badge resolves to a
/// DIFFERENT `auth.users` row — a second account for one officer. The
/// production project has exactly that: duplicate accounts across two email
/// domains.
///
/// And it is not a cosmetic duplicate. A posting (`geo_lga`, `geo_ward`) is set
/// on one of the two accounts; the officer signs in and lands on the other,
/// where it is blank. `alert_in_my_area()` then matches nothing and their board
/// is empty with the incidents right there — the same symptom as T-95's ward
/// suffix and T-90's role spelling, from a third cause. A OneSignal player id
/// sits on one of them too, so `escalation_push_targets()` either misses them
/// or, if both carry a posting, tells them twice.
///
/// `profiles.badge_number` would have caught it, and does not: it has a plain
/// index and no uniqueness, so two accounts may hold one badge. The badge is
/// what officers are called on the radio and what every board labels them
/// with; `formatOfficerBadge()` falls back to scanning every profile for a
/// match and takes whichever row comes first.
///
/// ## So the domain is configuration, in one place per language
///
/// `STAFF_EMAIL_DOMAIN` in `.env` overrides it, and
/// `scripts/check_one_staff_identity.py` asserts that this file and the
/// console's `src/lib/staff-identity.ts` carry the same default — because two
/// literals that must agree, in two languages, is exactly the shape that
/// produced the duplicates. It also refuses a literal of the domain anywhere
/// else.
///
/// Changing it does not migrate anybody. Every existing staff account keeps the
/// email it was created with, so a change creates a new account per officer on
/// their next sign-in. See `scripts/which_accounts_are_duplicates.sql` and
/// `merge_staff_account()` for the ones already made.
///
/// See E2E_AUDIT_REPORT.md T-99.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// The domain every staff account on this deployment was created under.
///
/// Named here rather than written into a sign-in path so that "which domain
/// are we" is a fact somebody can read, and so there is one place to change it.
const String defaultStaffEmailDomain = 'operationrainbow.plateau.gov.ng';

/// The domain this build turns a badge into an email with.
String get staffEmailDomain {
  if (!dotenv.isInitialized) return defaultStaffEmailDomain;
  final configured = dotenv.env['STAFF_EMAIL_DOMAIN']?.trim().toLowerCase();
  if (configured == null || configured.isEmpty) {
    return defaultStaffEmailDomain;
  }
  // A domain with an @ in it, or a space, produces an address no account can
  // ever have — and a sign-in that can never succeed looks exactly like a
  // wrong password. Refused in favour of the default, loudly.
  if (configured.contains('@') || configured.contains(RegExp(r'\s')) ||
      !configured.contains('.')) {
    debugPrint(
      '[STAFF_IDENTITY] STAFF_EMAIL_DOMAIN is "$configured", which is not a '
      'domain. Using $defaultStaffEmailDomain — a malformed domain would make '
      'every staff sign-in fail as though the password were wrong.',
    );
    return defaultStaffEmailDomain;
  }
  return configured;
}

/// Whether this build signs staff in under a domain other than the deployed
/// one.
///
/// A build pointed at a different domain creates a second account for every
/// officer who uses it, so this is worth saying out loud once.
bool get staffDomainIsOverridden => staffEmailDomain != defaultStaffEmailDomain;

/// The email for what somebody typed into the badge field.
///
/// An input already containing `@` is taken as an email, which is how an
/// account under any other domain signs in at all — including the duplicates
/// that already exist.
String emailForBadge(String badgeOrEmail) {
  final trimmed = badgeOrEmail.trim().toLowerCase();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.contains('@')) return trimmed;
  return '$trimmed@$staffEmailDomain';
}
