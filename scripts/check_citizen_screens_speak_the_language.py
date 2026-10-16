#!/usr/bin/env python3
"""A screen a citizen reads must not hardcode the words on it.

    python3 scripts/check_citizen_screens_speak_the_language.py

## What went wrong

The language picker worked. It persisted to the one SharedPreferences key, it
was reachable from Settings and from the home app bar, both controls wrote
through the one provider, `check_translation_keys.py` confirmed every key asked
for was defined in all three languages — and a citizen who chose HAUSA got a
Hausa home screen and an English emergency.

Five files in the whole app asked the translation table for anything: the
picker, the home screen, the voice dialog, the category list and the dispatcher
chat. Everything else — the situation chooser, the subtype list, the live SOS
screen, the confirmation, the safe-zone map, the lock screen — was written with
the English string in the widget.

Nothing could have caught it. `check_translation_keys.py` asks whether the keys
that ARE requested are defined; a screen that requests none passes it
perfectly. The table being complete and the screen being translated are two
different claims, and only the first one had a gate.

## What this checks

Every screen on the citizen's path, for user-visible string literals: a quoted
string that starts with a capital and either contains a space, is ALL CAPS, or
carries a newline. That is a label, not an identifier.

A screen listed in `NOT_YET` is allowed the count recorded beside it and **no
more**, so the remaining work can land screen by screen while nothing new is
added. Drop a screen's count to zero and remove its line. A screen that is not
listed at all must have none.

## What it does not check

Whether the translation is GOOD. `test/citizen_emergency_path_speaks_hausa_test.dart`
pumps the screens and asserts the Hausa string is on screen, which is the part
a table check cannot see; whether it is good Hausa is for a person who speaks
it.

Nor does it look at staff screens (`features/agent/`). A commander works in
English by protocol and those screens carry call signs and tier names; the
citizen path is where an untranslated word costs somebody something.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# The citizen's path. Converted screens are absent from NOT_YET and must stay
# at zero.
CITIZEN = [
    'lib/features/report/report_initial_screen.dart',
    'lib/features/report/report_subtype_screen.dart',
    'lib/features/report/report_success_screen.dart',
    'lib/features/emergency/emergency_active_screen.dart',
    'lib/features/report/report_details_screen.dart',
    'lib/features/citizen/safe_zone_screen.dart',
    'lib/features/auth/lock_screen.dart',
    'lib/features/tracking/live_tracking_screen.dart',
]

# Screen -> how many hardcoded strings it still has. A RATCHET: the number may
# fall, never rise. These are the next ones to do.
NOT_YET = {
    'lib/features/report/report_details_screen.dart': 45,
    'lib/features/citizen/safe_zone_screen.dart': 25,
    'lib/features/tracking/live_tracking_screen.dart': 14,
    'lib/features/auth/lock_screen.dart': 14,
}

# Values that are DATA, not labels: `alerts.status` is compared by string, so
# translating one would stop the comparison matching and leave a citizen's
# screen reading LOCATION BROADCASTING with a squad beside them.
DATA = {
    'PENDING', 'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE', 'RESOLVED',
    'CANCELLED', 'ESCALATED', 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'SOS',
    'DURESS', 'ERR',
}

LITERAL = re.compile(r"'((?:[^'\\\n]|\\.){3,90})'")
COMMENT = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)
NOT_PROSE = re.compile(
    r'^(assets/|/|[a-z_]+(_[a-z]+)*$|#[0-9A-Fa-f]{3,8}$|\d|https?:)')


def hardcoded(rel: str) -> list[str]:
    text = COMMENT.sub('', (REPO / rel).read_text(encoding='utf-8'))
    out = []
    for match in LITERAL.finditer(text):
        value = match.group(1)
        if NOT_PROSE.match(value) or not re.match(r'^[A-Z0-9]', value):
            continue
        if not (' ' in value or value.isupper() or '\\n' in value):
            continue
        if value in DATA:
            continue
        out.append(value)
    return list(dict.fromkeys(out))


failures: list[str] = []
done = 0
for rel in CITIZEN:
    if not (REPO / rel).is_file():
        failures.append(f'{rel} is listed on the citizen path and does not '
                        'exist — renamed? Update CITIZEN.')
        continue
    found = hardcoded(rel)
    allowed = NOT_YET.get(rel, 0)
    if len(found) > allowed:
        extra = found[:6]
        failures.append(
            f'{rel} has {len(found)} hardcoded user-visible string(s), and '
            f'{allowed} are allowed. A citizen who chose Hausa reads these in '
            f'English: {", ".join(repr(e) for e in extra)}'
            f'{" …" if len(found) > len(extra) else ""}. Put each one in '
            'lib/shared/localization/translations.dart with all three '
            'languages and read it with Translations.get(key, lang).')
    elif rel in NOT_YET and len(found) < allowed:
        failures.append(
            f'{rel} is down to {len(found)} from {allowed} — good. Lower its '
            f'number in NOT_YET to {len(found)} (or remove the line if it is '
            'zero) so the ratchet holds.')
    elif rel not in NOT_YET:
        done += 1

if failures:
    print('A citizen-facing screen that speaks English whatever they chose:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_citizen_screens_speak_the_language.py for why '
          'this matters.')
    sys.exit(1)

left = sum(NOT_YET.values())
print(f'The citizen path reads the language they chose:')
print(f'  * {done} of {len(CITIZEN)} screens carry no hardcoded label')
print(f'  * {len(NOT_YET)} still to do, {left} strings between them, each '
      'capped at its\n    current count so the number can only fall')
