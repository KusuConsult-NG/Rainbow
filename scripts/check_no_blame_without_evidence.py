#!/usr/bin/env python3
"""The app may not tell somebody their phone is the problem without evidence.

    python3 scripts/check_no_blame_without_evidence.py

## What went wrong

A citizen asked for a sign-in code on a handset showing four bars of 4G and
was told:

    NO CONNECTION. THE CODE CANNOT BE SENT WITHOUT ONE.

Nothing had asked the handset anything. What had actually failed was resolving
the backend's own hostname:

    SocketException: Failed host lookup: '<project>.supabase.co'
    (OS Error: No address associated with hostname, errno = 7)

`describeOtpSendFailure` classified that under one condition with socket and
timeout errors and returned a single message blaming the phone:

    if (text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('failed host lookup') ||   // <- lumped in here
        text.contains('network')) {
      return 'NO CONNECTION. THE CODE CANNOT BE SENT WITHOUT ONE.';
    }

That is the fault the same method exists to avoid two branches above, where a
disabled SMS provider is reported as `IT IS NOT YOUR PHONE`. Sign-in is phone
plus one-time code, with no password and no email path, so this message is the
whole of what a person has to go on — and the one it sent them to fix was not
broken. The person pulling that lever may be reporting a kidnapping.

A name that will not resolve and a connection that is not there are different
faults with different remedies. One is the person's to fix; the other is HQ's,
and telling them apart needs the handset to be asked.

## What this checks

  1. Every declarative claim about the handset's own connection sits within
     three lines of a `hasNetwork` comparison. `NO CONNECTION` says it has
     none; `PHONE IS ONLINE BUT` says it has one. Either without the check is
     a guess, and a guess in this direction sends somebody away to fix their
     phone during an emergency. The conditional wording — `IF THIS PHONE IS
     ONLINE, REPORT IT TO HQ` — needs no evidence and is deliberately allowed:
     it is the honest message for when nobody asked.
  2. No single condition classifies `failed host lookup` together with
     `socket`, `timeout` or `network`. That is the exact shape of the defect:
     one branch, one message, two unrelated faults.
  3. Every call to a failure classifier that takes `hasNetwork` passes it. The
     parameter defaults to null, which is safe — it produces the conditional
     wording — but a call site that forgets it silently loses the distinction
     this whole check exists to keep.

Comments are blanked first, so this file's own prose, and the comment in
`auth_service.dart` recording the defect, can quote the message verbatim.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / 'lib'

failures: list[str] = []


def live(path: Path) -> str:
    src = path.read_text()
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group().count('\n'), src,
                 flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n')
    )


# A claim about the person's own connection, stated as fact. Each needs the
# handset to have been asked; the conditional "IF THIS PHONE IS ONLINE" does
# not and is not listed.
CLAIMS = {
    'NO CONNECTION': 'says the handset has no connection',
    'PHONE IS ONLINE BUT': 'says the handset has one',
}

# How far above a claim the evidence may sit. The guard is either the `if` one
# line up or the ternary condition on the line before the string.
WINDOW = 3

IF_CONDITION = re.compile(r'\bif\s*\((.*?)\)\s*\{', re.S)
RESOLVE = 'failed host lookup'
REACHABILITY = ('socket', 'timeout', 'network')

# A classifier that takes the handset's answer, and therefore has to be given
# it. Found from the declaration rather than listed, so a third one added
# later is covered without touching this gate.
TAKES_NETWORK = re.compile(
    r'\b(\w+)\s*\(\s*Object\s+\w+\s*,\s*\{\s*bool\?\s*hasNetwork\s*\}\s*\)')

dart_files = sorted(LIB.rglob('*.dart'))
classifiers: dict[str, Path] = {}

for path in dart_files:
    code = live(path)
    lines = code.split('\n')
    where = path.relative_to(REPO)

    for name in TAKES_NETWORK.findall(code):
        classifiers[name] = path

    # 1. A claim about the handset needs the handset's answer beside it.
    for number, line in enumerate(lines, start=1):
        for claim, meaning in CLAIMS.items():
            if claim not in line:
                continue
            window = '\n'.join(lines[max(0, number - WINDOW):number])
            if 'hasNetwork' in window:
                continue
            failures.append(
                f'{where}:{number} {meaning} with no `hasNetwork` check in '
                f'the {WINDOW} lines above it. On a handset showing four bars '
                'this is what sends somebody away to fix a phone that is not '
                'broken. Either guard it on what the handset said, or use the '
                'conditional wording that claims nothing.')

    # 2. A name that will not resolve is not a missing connection.
    for match in IF_CONDITION.finditer(code):
        condition = match.group(1).lower()
        if RESOLVE not in condition:
            continue
        also = [word for word in REACHABILITY if word in condition]
        if not also:
            continue
        number = code[:match.start()].count('\n') + 1
        failures.append(
            f'{where}:{number} classifies `{RESOLVE}` in the same condition '
            f'as {", ".join(f"`{word}`" for word in also)}, so both faults '
            'get one message. A hostname that will not resolve is HQ\'s to '
            'fix and a missing connection is the person\'s; one branch cannot '
            'say both.')

# 3. Whoever calls a classifier has to hand it the handset's answer.
for name, declared_in in sorted(classifiers.items()):
    for path in dart_files:
        code = live(path)
        for match in re.finditer(rf'(?<![\w.]){re.escape(name)}\s*\(', code):
            number = code[:match.start()].count('\n') + 1
            tail = code[match.start():]
            depth, end = 0, len(tail)
            for index, character in enumerate(tail):
                if character == '(':
                    depth += 1
                elif character == ')':
                    depth -= 1
                    if depth == 0:
                        end = index
                        break
            arguments = tail[:end]
            if arguments.lstrip().startswith(f'{name}(Object') or \
                    'hasNetwork' in arguments:
                continue
            failures.append(
                f'{path.relative_to(REPO)}:{number} calls `{name}` without '
                '`hasNetwork:`. It defaults to null, which is honest but '
                'blind — the person is told the service address will not '
                'resolve when the app could have found out whether their '
                f'phone was online. Declared in '
                f'{declared_in.relative_to(REPO)}.')

if failures:
    print('A message blames the person\'s phone without having asked it:\n')
    for message in failures:
        print(f'  * {message}\n')
    sys.exit(1)

print('OK: no message claims anything about a handset without evidence.')
print(f'  * {len(dart_files)} Dart files; '
      f'{len(CLAIMS)} declarative claims, each under a `hasNetwork` guard')
print(f'  * `{RESOLVE}` is classified apart from '
      f'{", ".join(REACHABILITY)}')
print(f'  * {len(classifiers)} classifier(s) taking `hasNetwork`, '
      'every call site passing it')
