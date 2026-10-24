#!/usr/bin/env python3
"""A badge becomes an email in one place, not two.

    python3 scripts/check_one_staff_identity.py

## What went wrong

Staff do not sign in with an email. They type a badge — `HQ-001`, `NP/JOS/001`
— and the app turns it into one. It did that twice, with its own copy of the
domain each time:

    lib/services/auth_service.dart
      '$trimmed@operationrainbow.plateau.gov.ng'

    hq-dashboard-next/src/app/login/page.tsx
      ? '' : '@operationrainbow.plateau.gov.ng'

The domain is the second half of the primary key of a person. Provision an
account under a different one, or change it in one place, and the SAME badge
resolves to a DIFFERENT `auth.users` row — a second account for one officer. The
production project has exactly that: duplicate staff accounts across two email
domains.

And it is not cosmetic. The posting (`geo_lga`, `geo_ward`) is on one of the two
accounts; the officer signs in and lands on the other, where it is blank, so
`alert_in_my_area()` matches nothing and their board is empty with the incidents
right there. That symptom has now had three separate causes — T-90's role
spelling, T-95's ward suffix, and this — which is why it kept coming back after
each one was fixed.

`profiles.badge_number` would have caught it and does not: a plain index, no
uniqueness. The one identity column that HAD a constraint, `phone`, is the one
that was never the problem.

## What this checks

1. The two defaults are the same string. Two literals that must agree, in two
   languages, is the shape that produced the duplicates — the same shape as
   `staffRoleTiers` versus `STAFF_ROLE_TIERS`, which has its own gate for the
   same reason.
2. Neither sign-in path builds an address itself. Both call `emailForBadge`.
3. No other code names the domain. A placeholder in the account-creation form
   that drifts tells whoever is creating an account to type an email nobody can
   sign in under, which is the OTHER way an officer ends up with two accounts.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DART_CONFIG = REPO / 'lib/core/config/staff_identity.dart'
TS_CONFIG = REPO / 'hq-dashboard-next/src/lib/staff-identity.ts'
APP_SIGNIN = REPO / 'lib/services/auth_service.dart'
CONSOLE_SIGNIN = REPO / 'hq-dashboard-next/src/app/login/page.tsx'

# A test's fixture address is the point of the test, and the account-creation
# form's placeholder now reads the domain from the one helper.
SKIP = re.compile(r'\.(test|spec)\.(ts|tsx|dart)$|/__fixtures__/|/__tests__/')

faults: list[str] = []
proved: list[str] = []


def live(path: Path) -> str:
    """Comments blanked, newlines kept so line numbers stay true."""
    src = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)),
                 path.read_text(encoding='utf-8', errors='replace'), flags=re.S)
    opener = ('--',) if path.suffix == '.sql' else ('//', '///', '*')
    return '\n'.join(
        '' if line.lstrip().startswith(opener) else line
        for line in src.split('\n'))


for path in (DART_CONFIG, TS_CONFIG, APP_SIGNIN, CONSOLE_SIGNIN):
    if not path.is_file():
        faults.append(f'{path.relative_to(REPO)} is missing')
if faults:
    print('FAIL: a badge may become two different emails.\n')
    for f in faults:
        print(f'  - {f}\n')
    sys.exit(1)

# ── 1. the two defaults are one string ─────────────────────────────────────
dart = re.search(r"defaultStaffEmailDomain\s*=\s*'([^']+)'",
                 DART_CONFIG.read_text(encoding='utf-8'))
ts = re.search(r"DEFAULT_STAFF_EMAIL_DOMAIN\s*=\s*'([^']+)'",
               TS_CONFIG.read_text(encoding='utf-8'))
if dart is None:
    faults.append('lib/core/config/staff_identity.dart no longer declares '
                  '`defaultStaffEmailDomain`.')
if ts is None:
    faults.append('hq-dashboard-next/src/lib/staff-identity.ts no longer '
                  'declares `DEFAULT_STAFF_EMAIL_DOMAIN`.')
domain = None
if dart and ts:
    if dart.group(1) != ts.group(1):
        faults.append(
            f'the app signs staff in under {dart.group(1)!r} and the console '
            f'under {ts.group(1)!r}. The same badge then resolves to two '
            f'different accounts, and whichever one holds the posting is the '
            f'one that officer is not signed into.')
    else:
        domain = dart.group(1)
        proved.append(f'both sign-in paths derive {domain!r}')

# ── 2. neither path builds an address itself ───────────────────────────────
for path, helper in ((APP_SIGNIN, 'emailForBadge'),
                     (CONSOLE_SIGNIN, 'emailForBadge')):
    code = live(path)
    if helper not in code:
        faults.append(
            f'{path.relative_to(REPO)} does not call `{helper}`, so it is '
            f'deriving an address itself — which is how there came to be two '
            f'answers to "what is this officer\'s email".')
    # An inline `'@' + something` or a template with a bare @domain.
    for m in re.finditer(r"""['"]@[A-Za-z0-9.-]+\.[A-Za-z]{2,}['"]""", code):
        line = code.count('\n', 0, m.start()) + 1
        faults.append(
            f'{path.relative_to(REPO)}:{line} builds an address from '
            f'{m.group(0)}. The domain belongs in the config module, which is '
            f'the only place that can be changed by whoever deploys this.')
if not faults:
    proved.append('both sign-in paths ask the config module')

# ── 3. nothing else names the domain ───────────────────────────────────────
if domain:
    needle = re.compile(re.escape(domain))
    trees = [(REPO / 'lib', ('*.dart',)),
             (REPO / 'hq-dashboard-next/src', ('*.ts', '*.tsx'))]
    for root, patterns in trees:
        for pattern in patterns:
            for path in sorted(root.rglob(pattern)):
                rel = str(path.relative_to(REPO))
                if path in (DART_CONFIG, TS_CONFIG) or SKIP.search(rel):
                    continue
                if '/node_modules/' in rel or '/.next/' in rel:
                    continue
                code = live(path)
                for m in needle.finditer(code):
                    line = code.count('\n', 0, m.start()) + 1
                    faults.append(
                        f'{rel}:{line} names the staff email domain. One copy '
                        f'that drifts from the others creates a second '
                        f'account per officer; ask the config module instead.')
    if not any('names the staff email domain' in f for f in faults):
        files = sum(len(list(root.rglob(p))) for root, ps in trees for p in ps)
        proved.append(f'no other file among {files} names the domain')

if faults:
    print('FAIL: a badge may become two different emails.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-99.')
    sys.exit(1)

print('OK: a badge becomes one email, from one place per language.')
for item in proved:
    print(f'  * {item}')
