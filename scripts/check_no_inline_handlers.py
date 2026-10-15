#!/usr/bin/env python3
"""No inline event handler, because this console's CSP refuses to run one.

    python3 scripts/check_no_inline_handlers.py

## What went wrong

The Intelligence Map is the console's landing screen, and a marker's popup is
how a dispatcher acts on a pin: DOSSIER, DISPATCH, RESOLVE, CALL. The popup is
built as an HTML string, so its buttons carried

    <button onclick="window._hqDossier('<id>')">DOSSIER</button>

and `LiveMap` installed four `window._hq*` functions for them to reach.

`lib/csp.ts` sets `script-src 'self' 'nonce-…' 'strict-dynamic'` with **no**
`'unsafe-inline'` — deliberately, and that file writes out at length why. A
nonce can authorise a `<script>` element. It cannot authorise an inline event
handler ATTRIBUTE: per the CSP spec those need `'unsafe-inline'` (or CSP3's
`'unsafe-hashes'`), so the browser refuses them outright:

    Refused to execute inline event handler because it violates the following
    Content Security Policy directive: "script-src …"

So every scripted action in every map popup was dead from the day that policy
shipped, on the screen the console opens on. Three ways it stayed hidden:

  * the browser sweep pressed them and recorded "nothing" — which is a line in
    a log, not a failing check, and it reported the same labels as working on a
    second popup because state from earlier presses leaked between them;
  * `csp.test.ts` asserts the HEADER, not what the header does to the page;
  * `LiveMap.test.tsx` and `incident-dossier.test.ts` asserted the two halves
    separately — that the button carried the `onclick`, and that calling the
    global did the work — with a comment explaining that jsdom evaluates an
    inline handler in its own scope so the JOIN could not be tested there. The
    join never worked, and the suite was defending it.

The fix is delegation: the buttons carry `data-hq-action` and `data-hq-id`, and
the map listens once on its container with `addEventListener`. CSP-safe, no
globals, and clickable in a test.

## What this checks

Any `on<event>="…"` or `on<event>='…'` written into a string in the console's
source. That is the shape that reaches the browser as an attribute — a React
`onClick={…}` prop is a function reference and is not affected, which is why
this looks for the quoted-attribute form rather than the word "onclick".

## What it does not check

The app (`lib/`): Flutter has no HTML and no CSP. And a handler attached with
`addEventListener`, which is the thing this check wants people to use.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONSOLE = REPO / 'hq-dashboard-next' / 'src'

# `on` + an event name + `=` + a quote, which is how an attribute is written
# into an HTML string. Every HTML event handler attribute starts with `on`, and
# the CSP refuses all of them, so the rule does not need a list of event names.
#
# Requires the `=` and the quote: this must not fire on the word "onclick" in
# prose, on a React `onClick={handler}` prop (a function reference, unaffected
# by CSP), or on `onclick` read back with `getAttribute('onclick')` — which is
# how a test proves the attribute is ABSENT.
# Both cases, because HTML attribute names are case-insensitive and
# `ONCLICK="…"` is refused by the CSP exactly as `onclick="…"` is. Written as
# two uniform-case alternatives rather than with `re.I`, which would also match
# a camelCase React prop whose name happens to start with those letters —
# `onlyWhen="x"` is `on` + `ly` + `=` + a quote, and is not a handler.
INLINE = re.compile(r'\s(?:on[a-z]{2,}|ON[A-Z]{2,})\s*=\s*[\'"]')

# Comments blanked rather than removed, so line numbers survive. This check's
# own subject appears in the prose of the files it reads: `incident-dossier.ts`
# and `LiveMap.tsx` both quote the markup they used to emit, in comments that
# explain the defect.
BLOCK = re.compile(r'/\*.*?\*/', re.S)
LINE = re.compile(r'//[^\n]*')


def blank(text: str) -> str:
    out = BLOCK.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)
    return LINE.sub(lambda m: ' ' * len(m.group(0)), out)


failures: list[str] = []
scanned = 0

exempt = 0

for path in sorted(CONSOLE.rglob('*.ts')) + sorted(CONSOLE.rglob('*.tsx')):
    # A test proving the attribute is ABSENT compares against the shape of one:
    # `not.toMatch(/\son[a-z]+\s*=/)` and `getAttribute('onclick')` are how
    # `incident-dossier.test.ts` and `LiveMap.test.tsx` assert that this defect
    # has not come back. Scanning them would fail the check for defending it.
    if '.test.' in path.name:
        exempt += 1
        continue
    scanned += 1
    text = blank(path.read_text())
    lines = text.splitlines()
    for match in INLINE.finditer(text):
        line_no = text[:match.start()].count('\n') + 1
        line = lines[line_no - 1].strip()
        failures.append(
            f'{path.relative_to(REPO)}:{line_no} — an inline event handler: '
            f'`{match.group(0).strip()}…` in `{line[:90]}`. The console\'s CSP '
            "is `script-src 'self' 'nonce-…' 'strict-dynamic'` with no "
            "`'unsafe-inline'`, and a nonce CANNOT authorise an event handler "
            'attribute, so the browser refuses it: the control is dead the '
            'moment it ships. Carry the intent in a data attribute and listen '
            'once with addEventListener — see the popup buttons in '
            'lib/incident-dossier.ts and the delegated listener in '
            'components/LiveMap.tsx.')

if failures:
    print('An inline event handler the Content Security Policy will refuse:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_no_inline_handlers.py for why this matters.')
    sys.exit(1)

print('No inline event handlers in the console:')
print(f'  * {scanned} files scanned for the `on<event>="…"` attribute form, '
      f'{exempt} test files exempt (a test asserts the ABSENCE of one by '
      'naming\n    its shape)')
print('  * React onClick props and addEventListener are unaffected, and are '
      'the way to\n    do this')
