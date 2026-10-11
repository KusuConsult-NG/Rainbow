#!/usr/bin/env python3
"""A console must not scope anything by a role it has not confirmed.

    python3 scripts/check_identity_resolved_before_scoping.py

## What went wrong

`SystemAlertListener` was given targeting — who a mass advisory is for — and the
dashboard hands it the viewer's identity so it can decide. The dashboard gets
that identity from `userRole`, which is declared:

    const [userRole, setUserRole] = useState('HQ_OFFICER');

HQ_OFFICER is a COMMAND role, and command means "sees everything, because they
sent it". So from the first render until the `profiles.role` read lands over the
network, every console user is command as far as any filter can tell — and an
agency liaison was shown advisories addressed to other agencies and to
citizens. That is the exact leak the targeting was added to close, reopened by
a default value, and it is invisible in a test that sets the role up front.

The first fix was incomplete, which is the second half of this check. A second
code path sets the role from `user_metadata`:

    setUserRole(u.user_metadata?.role || 'HQ_COMMAND');

`user_metadata` is writable BY THE USER in Supabase — that is finding H-7,
"role source user-writable". A value an account can set for itself must never
be what decides that account is command, so that path may set the role for
presentation but may not mark it resolved. Only `profiles.role` resolves it:
it is what `requireRole` reads with admin privileges and what the RLS policies
key on.

## The asymmetry is deliberate

Unknown PLACE fails open and unknown IDENTITY fails closed. They look
inconsistent and get tidied into agreement, so this check holds both ends:

  * withholding a warning from somebody inside the affected area costs more
    than showing it to somebody outside, so a viewer with no LGA/ward/PU
    recorded is delivered to (`placeMatches` returns true on an empty value);
  * showing one agency's advisory to another agency's liaison is the leak
    itself, so a viewer whose agency is not yet known is delivered nothing
    that was addressed to an agency.

The app learned the identity half once already, in the responder tier filter:
"you cannot be assigned something when we do not know who you are".

## What this checks

1. `roleResolved` starts false.
2. It is set in exactly one place.
3. That place is the `profiles.role` read, and nothing in it touches
   `user_metadata`.
4. Every `viewer={{ ... }}` the dashboard builds carries exactly the fields
   this filter knows about — a new one fails here until somebody decides which
   half of the asymmetry it belongs to.
5. The identity fields in it are gated on `roleResolved`.
6. The place fields are not, because that guard would be a no-op dressed as
   consistency and the next reader would read the asymmetry as an oversight.
7. `advisoryReaches` still treats an unknown agency as "not this agency".
   Gating identity hands it `null`; if that ever fails open the way place does,
   the gate above withholds nothing and this whole fix is theatre.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DASHBOARD = REPO / 'hq-dashboard-next' / 'src' / 'app' / 'dashboard' / 'page.tsx'
FILTER = REPO / 'hq-dashboard-next' / 'src' / 'lib' / 'advisory-targeting.ts'

# The fields a console viewer is made of, split by which way they fail.
IDENTITY = ('agency', 'isCommand')
PLACE = ('geoLga', 'geoWard', 'geoPu')

# How far after the authoritative read `setRoleResolved(true)` may sit, and how
# far back from it we look for the read. The two calls are adjacent today; this
# is slack for a comment or a sibling setter between them, not for a different
# code path.
WINDOW = 14

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def strip_comments(text: str) -> str:
    """Comments out, so prose about a hazard is not read as the hazard.

    This check's own failure messages name `user_metadata`, and so does the
    comment in the dashboard that explains why that path may not resolve the
    role — the first run of this check failed on its own explanation.
    """
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


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
    body = literal.strip()
    body = body[1:-1] if body.startswith('{') and body.endswith('}') else body
    body = strip_comments(body)

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


if not DASHBOARD.exists():
    sys.exit(f'{DASHBOARD.relative_to(REPO)} is missing')
if not FILTER.exists():
    sys.exit(f'{FILTER.relative_to(REPO)} is missing')

source = DASHBOARD.read_text()
lines = source.splitlines()

# 1. The flag starts false. A flag that starts true is the original defect with
#    an extra step.
if not re.search(r'\[\s*roleResolved\s*,\s*setRoleResolved\s*\]\s*=\s*useState\(\s*false\s*\)', source):
    fail('`roleResolved` must be declared `useState(false)` in the dashboard — '
         'a flag that starts true says the role is confirmed before it is read.')

# 2 and 3. Exactly one place resolves it, and it is the authoritative read.
resolutions = [i for i, line in enumerate(lines) if 'setRoleResolved(true)' in line]
if not resolutions:
    fail('nothing sets `setRoleResolved(true)`, so the console never admits it '
         'knows the role and the advisory banner is permanently empty.')
elif len(resolutions) > 1:
    at = ', '.join(f'line {i + 1}' for i in resolutions)
    fail(f'`setRoleResolved(true)` is set in {len(resolutions)} places ({at}). '
         'Only the `profiles.role` read may resolve it; every other source of a '
         'role is a guess or is user-writable (H-7).')
else:
    index = resolutions[0]
    before = '\n'.join(lines[max(0, index - WINDOW):index + 1])
    around = '\n'.join(lines[max(0, index - WINDOW):index + WINDOW])
    if not re.search(r'setUserRole\(\s*profile(?:Row)?[.?]', before):
        fail(f'`setRoleResolved(true)` at line {index + 1} does not follow a '
             '`setUserRole(profile.role)`. The role is only resolved by the '
             '`profiles` read — that is what `requireRole` reads with admin '
             'privileges and what the RLS policies key on.')
    if 'user_metadata' in strip_comments(around):
        fail(f'`setRoleResolved(true)` at line {index + 1} sits in a block that '
             'reads `user_metadata`, which the user can write (H-7). A role an '
             'account sets for itself must not be what makes it command.')

# 4, 5 and 6. Every viewer the dashboard builds.
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

    for field in IDENTITY:
        value = fields.get(field)
        if value is None:
            continue
        if 'roleResolved' not in value:
            fail(f'`{field}` at line {line_no} is `{value}` — not gated on '
                 '`roleResolved`. `userRole` defaults to a command role, so '
                 'until the profile read lands this tells the filter that '
                 'whoever is looking sees everything.')

    for field in PLACE:
        value = fields.get(field)
        if value is None:
            continue
        if 'roleResolved' in value:
            fail(f'`{field}` at line {line_no} is gated on `roleResolved`. Place '
                 'fails OPEN — an unknown place is delivered to — so the guard '
                 'changes nothing and makes the deliberate asymmetry with '
                 'identity read as an oversight.')

# 7. The filter still fails closed on an agency it does not know.
filter_source = FILTER.read_text()
if not re.search(r'if\s*\(\s*!\s*viewer\.agency\s*\)\s*return false\s*;', filter_source):
    fail('`advisoryReaches` no longer returns false for a viewer with no '
         'agency. Gating identity hands it `null`; if an unknown agency fails '
         'open the way an unknown place does, that gate withholds nothing.')

if failures:
    print('The console scopes by an identity it has not confirmed:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_identity_resolved_before_scoping.py for why this matters.')
    sys.exit(1)

print('Identity is resolved before it is scoped by:')
print('  * roleResolved starts false and is set only by the profiles.role read')
print(f'  * {len(literals)} viewer literal(s): identity gated, place deliberately not')
print('  * advisoryReaches still fails closed on an unknown agency')
