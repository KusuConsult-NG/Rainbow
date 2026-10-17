#!/usr/bin/env python3
"""The app has one name, and every string a person reads uses it.

    python3 scripts/check_one_brand_name.py

## What went wrong

The rebrand to Plateau Eye changed the launcher label, both iOS bundle names,
the pubspec description and the console's browser tab, and was reported as
"App Name — Now 'Plateau Eye' Everywhere". It was not everywhere. What a
person actually reads still said the old name:

  * the `'title'` key in `translations.dart`, in all three languages — the
    line at the top of the home screen, the most prominent text in the app;
  * three permission messages, in all three languages: *"This phone has not
    given Operation Rainbow access to the microphone… go to Settings"*. The
    phone's Settings list no longer contains that name, so the instruction
    could not be followed;
  * the background-tracking notification title, which sits in the shade for as
    long as a responder is being tracked;
  * **every outbound SMS.** The four canned statewide broadcast templates
    (`[OPERATION RAINBOW]: PUBLIC SAFETY ALERT …`), the inter-agency
    escalation sent to the Police and the Army, and the citizen SOS dispatch.
    One template told citizens to *"report any suspicious activity via the
    RainBow app"*;
  * the console's own login heading, under a browser tab that said Plateau Eye.

FOUR Flutter tests asserted the OLD name and passed, which is why 734 green
tests said nothing: `find.text('OPERATION RAINBOW')`, `find.text('AIKIN
RAINBOW')` and a `contains 'has not given Operation Rainbow access'` were all
pinning the defect in place. The first version of THIS check found three of
them and missed the fourth, because it looked for the name at the start of the
quoted string and that one has it in the middle.

## What this checks

`android:label` in AndroidManifest.xml is the one source of truth for the
app's name. No string literal in `lib/` or in the console's `src/` may contain
a known former name. Comments are exempt — the history of a rename is worth
writing down, and several files explain this one.

Identifiers are exempt too: `RainbowApp`, `RainbowMap`, `RainbowBottomNav`,
the `rainbow_app` package name and `package:rainbow_app/` imports are internal
and renaming them is a separate, mechanical job with no user-visible effect.
What this forbids is the name reaching a person.

## What it does not check

Whether the new name is spelled correctly, or the artwork. And not the audit
report or the runbooks: a document describing what the app used to be called
has to be able to say it.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / 'android' / 'app' / 'src' / 'main' / 'AndroidManifest.xml'

# Names this app has had. A new rename adds its predecessor here.
#
# 'Rainbow EWER' was missing until a tester received the real sign-in SMS and
# read it back: "Your Rainbow EWER verification code is: …". Two failures at
# once — this list did not carry the name, and the scan below did not read the
# file it was in. Either alone would have been enough to miss it.
FORMER_NAMES = [
    'Operation Rainbow', 'OPERATION RAINBOW', 'Operation RainBow',
    'RainBow app', 'Rainbow App', 'AIKIN RAINBOW',
    'Rainbow EWER', 'RAINBOW EWER', 'RainBow EWER',
]

# The bare word, standing alone. Not in FORMER_NAMES because it is not a name
# this app ever had in full — but "First time this number has ever contacted
# Rainbow." was on the console's incident card, read by an operator, and no
# entry in that list matches it. A hand-written list of full names can only
# catch the spellings somebody thought of.
#
# Capitalised and word-bounded on purpose: it must not fire inside
# `RainbowMap`, `rainbow_offline.db` or `com.operationrainbow.app/sim`, which
# are identifiers, nor on the `rainbow-97f1e` project slug in the README.
BARE_NAME = re.compile(r'(?<![\w-])Rainbow(?![\w-])')

# Internal identifiers, which are not read by anyone using the app.
EXEMPT = re.compile(
    r'rainbow_app|package:rainbow|RainbowApp|RainbowMap|RainbowBottomNav|'
    r'RainbowAppBar|RAINBOW_WEBHOOK_SECRET|RAINBOW_[A-Z_]+|X-Rainbow-Auth')

DART_COMMENT = re.compile(r'///[^\n]*|//[^\n]*|/\*.*?\*/', re.S)


def strip_comments(text: str) -> str:
    """Blank the comments, keeping every newline.

    This used to be `' ' * len(match)`, which eats the newlines inside a
    `/* … */` block and shifts every line number after it. The finding for
    `ussd-provenance.ts` pointed at line 96; the string is on line 158. A gate
    that names the wrong line sends somebody to read the wrong code.
    """
    return DART_COMMENT.sub(
        lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)

label = re.search(r'android:label="([^"]+)"', MANIFEST.read_text(encoding='utf-8'))
if not label:
    print(f'{MANIFEST.relative_to(REPO)} declares no android:label, so nothing '
          'names this app.')
    sys.exit(1)
NAME = label.group(1)

failures: list[str] = []
scanned = 0

# The repository's own front door, which people read too. `README.md` opened
# with "# Operation Rainbow" for the whole rebrand, because this check looked
# only at strings a person sees INSIDE the app.
sources = [REPO / 'README.md']
sources += [p for p in (REPO / 'lib').rglob('*.dart')]
console = REPO / 'hq-dashboard-next' / 'src'
if console.is_dir():
    sources += [p for p in console.rglob('*.ts')] + [p for p in console.rglob('*.tsx')]

# The Edge Functions, which compose the one string EVERY citizen reads: the
# sign-in code's SMS. This was not scanned, and the message named the app from
# two rebrands ago for every code ever sent. `lib/` and the console's `src/`
# are where a person reads the app; they are not where the app WRITES to a
# person, and this is.
functions = REPO / 'supabase' / 'functions'
if functions.is_dir():
    sources += [p for p in functions.rglob('*.ts')]

# Which roots were actually read. A check that quietly stops reading one of
# them still prints a clean sweep, which is how the sign-in SMS went two
# rebrands without anybody noticing: the gate said "everywhere a person can
# read it" over a scan that never opened the file the SMS is written in.
roots = {'lib': REPO / 'lib',
         'the console': console,
         'the Edge Functions': functions}
read_from = {label: 0 for label in roots}

for path in sorted(sources):
    # A test that asserts the OLD name is the defect, not an exemption — three
    # of them were pinning it. But a test file naming it in a description is
    # noise, so tests are scanned for ASSERTIONS only, below.
    if '.test.' in path.name or path.name.endswith('_test.dart'):
        continue
    scanned += 1
    for label, root in roots.items():
        if root.is_dir() and root in path.parents:
            read_from[label] += 1
    text = strip_comments(path.read_text(encoding='utf-8'))
    hunts = [(former, re.compile(re.escape(former))) for former in FORMER_NAMES]
    hunts.append(('Rainbow', BARE_NAME))
    for former, pattern in hunts:
        for match in pattern.finditer(text):
            window = text[max(0, match.start() - 30):match.end() + 30]
            if EXEMPT.search(window):
                continue
            line = text[:match.start()].count('\n') + 1
            failures.append(
                f'{path.relative_to(REPO)}:{line} reads {former!r}, and this '
                f'app is called {NAME!r} (android:label). A person sees this '
                'string: on a screen, in a notification, or in an SMS they '
                'were sent. Use the current name, or move the old one into a '
                'comment if it is being explained.')

for label, root in roots.items():
    if root.is_dir() and read_from[label] == 0:
        failures.append(
            f'nothing under {root.relative_to(REPO)} was read, so this check '
            f'cannot say anything about {label}. It reported a clean sweep '
            'over exactly that gap once already.')

# Tests must not pin a former name.
for path in sorted(list((REPO / 'test').rglob('*.dart'))
                   + ([p for p in console.rglob('*.test.ts')] if console.is_dir() else [])
                   + ([p for p in console.rglob('*.test.tsx')] if console.is_dir() else [])):
    text = strip_comments(path.read_text(encoding='utf-8'))
    for former in FORMER_NAMES:
        for match in re.finditer(
                rf'(?:expect|find\.text|toBe|toContain|equals|contains|'
                rf'startsWith|endsWith|matches)\s*\(\s*'
                rf'[\'"][^\'"\n]*{re.escape(former)}', text):
            line = text[:match.start()].count('\n') + 1
            failures.append(
                f'{path.relative_to(REPO)}:{line} ASSERTS the former name '
                f'{former!r}. A test that pins the old brand keeps the rename '
                f'from ever being finished — three of these passed while the '
                'home screen still said it.')

if failures:
    print(f'A person would read a name this app no longer has '
          f'(it is {NAME!r}):\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_one_brand_name.py for why this matters.')
    sys.exit(1)

print(f'One name, used everywhere a person can read it: {NAME!r}')
print(f'  * {scanned} source files carry no former name')
for label, count in read_from.items():
    print(f'      {count:>4} in {label}')
print(f'  * no test pins one, and {len(FORMER_NAMES)} former spellings plus the '
      'bare word are watched for')
