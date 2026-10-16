#!/usr/bin/env python3
"""A console must not act on a role it has not been told.

    python3 scripts/check_identity_resolved_before_scoping.py

## What went wrong

`src/lib/console-access.ts` answers "what may this account reach", and its own
doc comment says what it is for:

    An unknown role gets the smallest possible console rather than the largest:
    while the profile is still loading, `userRole` is '', and a default of
    "show everything" would flash the whole command console at an agency
    liaison on every page load before settling.

`userRole` was never ''. The dashboard declared it:

    const [userRole, setUserRole] = useState('HQ_OFFICER');

HQ_OFFICER is a COMMAND role, and a second path then set the role from
`u.user_metadata?.role || 'HQ_COMMAND'` — user-writable metadata (finding H-7)
falling back to the top of the command chain. So `consoleAccess` was never once
handed an unknown role, its "Unknown, or still loading" branch was unreachable,
and the RESOLVING ACCESS subtitle it returns had never been rendered despite
being under test. The flash it exists to prevent happened on every page load.

What that cost, past the chrome:

  * **T-34.** The advisory banner reads command as "sees everything, because
    they sent it". For the window before the profile read returned, every
    console user was command, so an agency liaison was shown advisories
    addressed to other agencies and to citizens — the leak the targeting was
    added to close, reopened by a default value.
  * **T-35.** `AgencyPortal` seeded its selected agency from
    `useState(isHq ? AGENCIES[0].code : (userAgency || 'POLICE'))`. A
    `useState` initialiser runs once, and the HQ-only agency switcher was the
    one control that could have corrected it, so a liaison who reached that tab
    in the window was frozen on the Police desk for the life of the mount. RLS
    correctly returned nothing, and the portal reported the Police as having no
    incidents, no personnel and no deployments — on the only screen that role
    has.

Both were fixed at their own surfaces first. Both fixes were patches: the role
is read in a dozen places and each would have needed its own guard. The default
is the defect, and `null` fixes every consumer at once.

## The asymmetry is deliberate

Unknown PLACE fails open and unknown IDENTITY fails closed. They look
inconsistent and get tidied into agreement, so this check holds both ends:

  * withholding a warning from somebody inside the affected area costs more
    than showing it to somebody outside, so a viewer with no LGA/ward/PU
    recorded is delivered to (`placeMatches` returns true on an empty value);
  * showing one agency's advisory to another agency's liaison is the leak
    itself, so a viewer whose agency is not yet known is delivered nothing that
    was addressed to an agency.

The app learned the identity half once already, in the responder tier filter:
"you cannot be assigned something when we do not know who you are".

## What this checks

At the source, where it protects every consumer:

1. The dashboard's role state starts `null` — not a role, and above all not a
   command role.
2. Exactly one thing sets it.
3. That one setter is the `profiles.role` read.
4. Nothing in the dashboard reads a role out of `user_metadata` (H-7).
5. `consoleAccess` is handed the role itself, with no `||` or `??` putting a
   role back when there is none.

At the surfaces that were caught by it:

6. The advisory `viewer` carries exactly the fields the filter knows about, its
   identity fields come from the role, and its place fields are left ungated.
7. `advisoryReaches` still treats an unknown agency as "not this agency".
8. `AgencyPortal` does not freeze the desk in a `useState` initialiser, and
   does not fall back to a real agency's code when it has none.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONSOLE = REPO / 'hq-dashboard-next' / 'src'
DASHBOARD = CONSOLE / 'app' / 'dashboard' / 'page.tsx'
FILTER = CONSOLE / 'lib' / 'advisory-targeting.ts'
PORTAL = CONSOLE / 'components' / 'AgencyPortal.tsx'

# The fields a console viewer is made of, split by which way they fail.
IDENTITY = {'agency': 'access.agency', 'isCommand': 'isHqUser'}
PLACE = ('geoLga', 'geoWard', 'geoPu')
# Names that mean "who is this" — a place field must not be conditional on one.
IDENTITY_NAMES = ('isHqUser', 'isCommand', 'access.agency', 'roleResolved', 'userRole')

# How far after the authoritative read the single setter may sit. The two are
# adjacent today; this is slack for a comment or a sibling setter between them,
# not for a different code path.
WINDOW = 14

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


# One pattern for both comment shapes, so a block comment is matched as a whole
# rather than line by line. The checks below are line-indexed, so the comment is
# BLANKED rather than removed: every newline survives and the line numbers in a
# failure message still point at the file.
COMMENT = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)


def strip_comments(text: str) -> str:
    """Comments blanked, so prose about a hazard is not read as the hazard.

    This check's failure messages name `user_metadata`, and so do the comments
    in the dashboard and the portal recording what was deleted and why. Two
    versions of this check have now failed on their own explanation: the first
    did not strip comments at all, and the second stripped them a line at a
    time, which cannot see that a line belongs to a `/** ... */` block.
    """
    return COMMENT.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)


def object_literal_at(text: str, start: int) -> str:
    """The object literal beginning at `start`, braces balanced."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return ''


def top_level_fields(literal: str) -> dict[str, str]:
    """`{ a: 1, b: f({x, y}) }` -> {'a': '1', 'b': 'f({x, y})'}, comments gone."""
    body = strip_comments(literal).strip()
    body = body[1:-1] if body.startswith('{') and body.endswith('}') else body

    parts: list[str] = []
    depth = 0
    current = ''
    for ch in body:
        if ch in '{[(':
            depth += 1
        elif ch in '}])':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(current)
            current = ''
            continue
        current += ch
    parts.append(current)

    fields: dict[str, str] = {}
    for part in parts:
        part = part.strip()
        if not part:
            continue
        name, _, value = part.partition(':')
        fields[name.strip()] = value.strip()
    return fields


for path in (DASHBOARD, FILTER, PORTAL):
    if not path.exists():
        sys.exit(f'{path.relative_to(REPO)} is missing')

source = DASHBOARD.read_text()
code = strip_comments(source)

# ── 1. No role until there is a role. ──
declaration = re.search(r'\[\s*userRole\s*,\s*setUserRole\s*\]\s*=\s*useState([^;]*);', code)
if not declaration:
    fail('the dashboard no longer declares `[userRole, setUserRole] = useState(...)`, '
         'so this check cannot see what it starts as.')
elif not re.fullmatch(r'\s*(<[^>]*>)?\(\s*null\s*\)\s*', declaration.group(1)):
    fail(f'`userRole` is declared `useState{declaration.group(1).strip()}`. It must '
         'start `null`: any role here is claimed before it is known, and '
         '`consoleAccess` gives a known command role the whole command console. '
         'That is the flash its own doc comment says it prevents.')

# ── 2 and 3. One writer, and it is the authoritative read. ──
code_lines = code.splitlines()
setters = [i for i, line in enumerate(code_lines) if 'setUserRole(' in line]
if not setters:
    fail('nothing calls `setUserRole`, so the role never resolves and every '
         'account is left with the smallest console.')
elif len(setters) > 1:
    at = ', '.join(f'line {i + 1}' for i in setters)
    fail(f'`setUserRole` is called in {len(setters)} places ({at}). Only the '
         '`profiles.role` read may set the role; every other source of one is a '
         'guess, or is writable by the account it describes (H-7).')
else:
    index = setters[0]
    before = '\n'.join(code_lines[max(0, index - WINDOW):index + 1])
    if not re.search(r'profile(?:Row)?\s*[.?]\s*role', before):
        fail(f'the `setUserRole` at line {index + 1} does not read '
             '`profile.role`. The role comes from the `profiles` table — what '
             '`requireRole` reads with admin privileges and what the RLS '
             'policies key on — and from nowhere else.')

# ── 4. H-7 has no reader here. ──
for i, line in enumerate(code_lines):
    if 'user_metadata' in line:
        fail(f'line {i + 1} reads `user_metadata`. In Supabase that is writable '
             'by the user it belongs to (H-7), so nothing in this console may '
             'take a role, an agency or a posting from it.')

# ── 5. The role reaches consoleAccess as it is. ──
# `userRole` itself, or the `profiles` row the one setter reads — the effect
# that resolves the role also asks where that role lands. Anything else, and
# above all anything with a `||` or `??` in it, puts a role back when there is
# none.
ROLE_ARGUMENT = re.compile(r'^(userRole|profile(?:Row)?\s*[.?]\s*\.?\s*role(\s+as\s+string)?)$')
for call in re.finditer(r'consoleAccess\(\s*([^,)]*)', code):
    argument = ' '.join(call.group(1).split())
    if not ROLE_ARGUMENT.match(argument):
        line_no = code[:call.start()].count('\n') + 1
        fail(f'`consoleAccess({argument}...)` at line {line_no} (approx): pass '
             '`userRole`, or the `profile.role` the one setter reads. A `||` or '
             '`??` here puts a role back when there is none, which is the defect '
             'with an extra step.')

# ── 6. The advisory viewer. ──
literals = [m.start() + len('viewer={') for m in re.finditer(r'viewer=\{\{', source)]
if not literals:
    fail('the dashboard builds no `viewer={{ ... }}`, so either the advisory '
         'filter lost its input or this check lost its subject.')

for start in literals:
    line_no = source[:start].count('\n') + 1
    literal = object_literal_at(source, start)
    if not literal:
        fail(f'the `viewer` literal at line {line_no} has unbalanced braces.')
        continue
    fields = top_level_fields(literal)

    expected = set(IDENTITY) | set(PLACE)
    unknown = sorted(set(fields) - expected)
    missing = sorted(expected - set(fields))
    if unknown:
        fail(f'the `viewer` at line {line_no} carries {", ".join(unknown)}, which '
             'this check does not know about. Decide which way it fails — closed '
             'like identity, open like place — and add it here.')
    if missing:
        fail(f'the `viewer` at line {line_no} is missing {", ".join(missing)}.')

    for field, derived_from in IDENTITY.items():
        value = fields.get(field)
        if value is None:
            continue
        if derived_from not in value:
            fail(f'`{field}` at line {line_no} is `{value}`, not `{derived_from}`. '
                 'Both identity fields must come from the role, because the role '
                 'is what is `null` until it is known.')

    for field in PLACE:
        value = fields.get(field)
        if value is None:
            continue
        if 'userProfile' not in value:
            fail(f'`{field}` at line {line_no} is `{value}`, not read from '
                 '`userProfile`. The viewer\'s place is the posting on their '
                 'profile and nothing else.')
        gated_on = [name for name in IDENTITY_NAMES if name in value]
        if gated_on:
            fail(f'`{field}` at line {line_no} is conditional on '
                 f'{", ".join(gated_on)}. Place fails OPEN — an unknown place is '
                 'delivered to, because withholding a warning from somebody '
                 'inside the affected area costs more than showing it to '
                 'somebody outside. Gating it on identity changes nothing and '
                 'makes the deliberate asymmetry read as an oversight.')

# ── 7. The filter still fails closed on an agency it does not know. ──
if not re.search(r'if\s*\(\s*!\s*viewer\.agency\s*\)\s*return false\s*;',
                 FILTER.read_text()):
    fail('`advisoryReaches` no longer returns false for a viewer with no '
         'agency. The role being `null` hands it exactly that; if an unknown '
         'agency fails open the way an unknown place does, nothing is withheld.')

# ── 8. The portal's desk follows the account. ──
portal = strip_comments(PORTAL.read_text())
if re.search(r'useState[^;]*\buserAgency\b', portal):
    fail('`AgencyPortal` seeds state from `userAgency`. A `useState` '
         'initialiser runs once and the dashboard supplies that prop late, so '
         'the desk freezes on whatever the first render guessed — and the '
         'agency switcher that could correct it is HQ-only. Derive the selected '
         'agency from the props instead.')
if re.search(r"userAgency\s*\|\|\s*'", portal) or re.search(r"userAgency\s*\?\?\s*'", portal):
    fail("`AgencyPortal` falls back to a literal agency code when `userAgency` "
         "is absent. It used to be `userAgency || 'POLICE'`: an account with no "
         "agency is not the Police, and RLS then renders that desk empty rather "
         "than refusing, so the portal states as fact that an agency it cannot "
         "read has nothing.")

if failures:
    print('The console acts on a role it has not been told:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_identity_resolved_before_scoping.py for why this matters.')
    sys.exit(1)

print('Identity is resolved before it is acted on:')
print('  * userRole starts null; one setter, and it reads profiles.role')
print('  * no reader of user_metadata; consoleAccess gets the role as it is')
print(f'  * {len(literals)} viewer literal(s): identity from the role, place from the profile')
print('  * advisoryReaches fails closed on an unknown agency')
print('  * AgencyPortal derives its desk instead of freezing it')
