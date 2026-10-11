#!/usr/bin/env python3
"""A screen may not name a place that was never recorded.

    python3 scripts/check_no_invented_places.py

## What went wrong

`AlertService` refuses to guess where an incident happened. Its own comment:

    The reporter's profile is deliberately NOT a fallback here. Filing an
    incident against the address someone registered at is how a report from
    Mangu is routed to a unit in Jos, and it would be indistinguishable
    afterwards from a measured position.

When the coordinates do not resolve to a Plateau LGA it logs "submitting
without jurisdiction rather than guessing one" and writes NULL. The responder
feed filter agrees, treating an alert with no `geo_lga` as reaching everybody,
because an unknown place must fail open.

Five screens then named one anyway, and in four of the five the honest wording
was already on the same line or three lines away:

  * the responder's incident card:
    `'${alert['geo_lga'] ?? 'PLATEAU'} · ${alert['geo_ward'] ?? 'HQ'} · '
     '${alert['geo_pu'] ?? 'UNIT'}'` — so **PLATEAU · HQ · UNIT** for an
    unresolved incident, and `· UNIT` on nearly every card, since there is no
    polling unit from coordinates and there cannot be;
  * the dispatch roster: `${r['geo_lga'] ?? 'JOS'}`. `JOS` is not one of
    Plateau's seventeen LGAs — they are JOS NORTH, JOS SOUTH, JOS EAST and
    fourteen others — and a statewide commander reaches officers regardless of
    posting, so the account dispatching across all seventeen was the one shown
    a place that exists in none of them;
  * the console's incident dossier: `{selectedReport.geo_lga || 'STATE HQ'}`,
    three lines above `{selectedReport.geo_ward && (...)}`, which DROPS an
    absent ward;
  * the console's map card: `PU: {a.geo_pu || 'SECTOR HQ'}`;
  * the AI triage prompt: `- LGA: ${a.geo_lga || 'STATE HQ'}`, where the Type,
    Ward and Description lines around it say `N/A` and "No description
    provided". A model's priority and unit recommendation were conditioned on
    a location nobody measured.

Three layers, and only the display guessed: the writer and the filter were both
right, which is why nothing downstream of them was going to catch it. T-16 is
the finding about invented geography in the seed data; this is the same thing a
layer later, at runtime, on the screens somebody acts on.

## What this checks, and what it deliberately does not

A literal fallback on a place field, **where the fallback is being rendered** —
inside a `${...}` interpolation or a JSX expression. That is the distinction
that matters, because the same `||` in a non-rendering position is often
correct:

  * `alert-display.ts` builds a grouping key from `alert.geo_lga || 'STATE'`.
    A sentinel that is never displayed, and it groups unlocated reports of one
    type together, which is what it is for.
  * `escalateAlert(id, selectedReport.geo_lga || 'ALL')` escalates an unlocated
    incident to everybody. That is the documented fail-open on place.

Neither is flagged, and neither needs an exemption, because neither is inside a
string being shown to anybody. A wording that says the value is absent is
allowed anywhere.

`lib/services/place_label.dart` and `hq-dashboard-next/src/lib/place-label.ts`
own the answer, one per codebase, and are skipped so the honest wordings are
declared in one place each.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOTS = (
    (REPO / 'lib', ('*.dart',)),
    (REPO / 'hq-dashboard-next' / 'src', ('*.ts', '*.tsx')),
)

# The two owners of the honest wording.
EXEMPT = {
    REPO / 'lib' / 'services' / 'place_label.dart',
    REPO / 'hq-dashboard-next' / 'src' / 'lib' / 'place-label.ts',
}

# Where something is. A wrong one of these sends a person to the wrong place.
FIELDS = ('geo_lga', 'geo_ward', 'geo_pu', 'geoLga', 'geoWard', 'geoPu')

# Named, with the reason, rather than left to a rule that cannot tell a title
# from a value. Matched EXACTLY and case-sensitively.
#
#   'Sector' — the panel heading, where an LGA name would otherwise go:
#       `${userProfile?.geo_lga || 'Sector'} Monitoring`
#   reads "SECTOR MONITORING", a possessive in a title rather than a claim
#   about where anything is. 'SECTOR HQ' is a different thing and is still
#   flagged: it names a headquarters.
#
# Anything added here needs that second sentence — what it reads as, and why
# that is not an assertion about a place. If it cannot be written, the literal
# is a defect.
ALLOWED_EXACTLY = {'Sector'}

# A fallback that says "not recorded" is the point of this check, not a breach
# of it. Matched case-insensitively as a substring of the literal.
HONEST = (
    'unknown', 'not recorded', 'not resolved', 'not set', 'none', 'n/a',
    'no lga', 'no ward', 'no pu', 'unlocated', 'unscoped', 'unassigned',
    'missing', 'not provided', 'nowhere', '—', '--', '?', '-',
)

FALLBACK = re.compile(
    r"""(?P<field>%s)
        (?:['"\]]|\s|as\s+String\?|\?)*
        (?P<op>\?\?|\|\|)
        \s*
        (?P<quote>['"])(?P<literal>[^'"\n]*)(?P=quote)
    """ % '|'.join(FIELDS),
    re.X,
)

# Comments blanked rather than removed, so line numbers survive — including a
# multi-line /** ... */, which a line-at-a-time strip cannot see.
COMMENT = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)


def strip_comments(text: str) -> str:
    """This check's own prose quotes every defect it looks for."""
    return COMMENT.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)


def being_rendered(line: str, index: int) -> bool:
    """Is the fallback at `index` inside a `${...}` or a JSX `{...}`?

    Scanning the same line is enough for every shape these two codebases use,
    and keeping it to one line is what stops a whole `insert({ ... })` or
    `return ( ... )` from reading as a render. A `{` with no `}` after it, to
    the left of the fallback, means the value is inside braces that something
    is going to print.
    """
    left = line[:index]
    opened = max(left.rfind('${'), left.rfind('{'))
    if opened == -1:
        return False
    return left.rfind('}') < opened


failures: list[str] = []
scanned = 0

for root, patterns in ROOTS:
    if not root.exists():
        sys.exit(f'{root.relative_to(REPO)} is missing')
    for pattern in patterns:
        for path in sorted(root.rglob(pattern)):
            if path in EXEMPT:
                continue
            if '.test.' in path.name or path.name.endswith('_test.dart'):
                continue
            scanned += 1
            text = strip_comments(path.read_text())
            lines = text.splitlines()
            for match in FALLBACK.finditer(text):
                literal = match.group('literal').strip()
                if literal == '':
                    continue  # An empty fallback names nothing.
                if literal in ALLOWED_EXACTLY:
                    continue
                if any(word in literal.lower() for word in HONEST):
                    continue
                line_no = text[:match.start()].count('\n') + 1
                line = lines[line_no - 1]
                column = match.start() - (text.rfind('\n', 0, match.start()) + 1)
                if not being_rendered(line, column):
                    continue  # A sentinel or an argument, not a label.
                failures.append(
                    f'{path.relative_to(REPO)}:{line_no} — '
                    f'`{match.group("field")} {match.group("op")} '
                    f'\'{literal}\'` is rendered. That tells whoever is reading '
                    f'the screen that the {match.group("field")} is '
                    f'\'{literal}\', when the row does not have one. Say it is '
                    'not recorded, or drop the segment: `place_label.dart` and '
                    '`place-label.ts` already do both.')

if failures:
    print('A screen names a place that was never recorded:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_no_invented_places.py for why this matters.')
    sys.exit(1)

print(f'No invented places on any screen ({scanned} files):')
print('  * every rendered fallback on a place field says the value is absent,')
print(f'    or is one of {len(ALLOWED_EXACTLY)} named title word(s) with its reason recorded')
print('  * the two place-label modules own the wording, one per codebase')
