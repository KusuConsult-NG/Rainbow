#!/usr/bin/env python3
"""`AsyncValue.value` rethrows. Nothing in a build may call it unguarded.

    python3 scripts/check_async_reads_cannot_rethrow.py

## What went wrong

Reported from a real handset, after the blank-page fix made it legible:

    Plateau Eye could not start
    Failed while drawing the screen.
    RealtimeSubscribeException(status: channelError, details:
    WebSocketChannelException: SocketException: Failed host lookup:
    '<project>.supabase.co' (OS Error: No address associated with hostname,
    errno = 7))

The cause is one getter, and its name is the trap:

    T? get value {
      if (!hasValue) {
        throwErrorWithCombinedStackTrace(error, stackTrace);
      }
      return _value;
    }
                        — riverpod-2.6.1/lib/src/common.dart:493-498

`AsyncValue.value` is nullable and looks like a safe read. On an `AsyncError`
it RETHROWS the error it is holding. `valueOrNull` is the one that returns
null.

`SystemAlertListener.build` did `ref.watch(userProfileProvider).value`, and
that widget wraps EVERY screen through `MaterialApp.builder`.
`userProfileProvider` is a realtime stream on `profiles`, subscribed only once
somebody is SIGNED IN. So: a signed-in handset that could not reach the
backend rethrew out of the build of the widget wrapping the whole app, and the
app died at launch. In a release build a build-time throw paints a featureless
pale rectangle — the blank page that started all of this.

It never showed up signed out, because `userProfileProvider` returns
`Stream.value(null)` with no user and therefore never errors. Every automated
pass that boots the app signed out — which was all of them — saw nothing.

This app carries an offline queue, an encrypted SMS fallback and a Bluetooth
mesh so that losing the network is survivable. Losing it must not be the thing
that kills the UI.

## What this checks

  1. No `ref.watch(...).value` or `ref.read(...).value` anywhere in `lib/`.
     That is the shape that rethrows silently; `.valueOrNull` is the read.
  2. A `.value!` on an async result is allowed only under a `hasValue` guard —
     `AsyncError.value` throws before the `!` is ever reached, so the guard is
     what makes it safe, and it has to be visible beside it.

Comments are blanked first, so a file may quote the defect it documents.
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


WATCH_VALUE = re.compile(
    r'ref\s*\.\s*(?:watch|read)\s*\([^;]*?\)\s*\.\s*value\b(?!OrNull)')
BANG_VALUE = re.compile(r'(\w+)\s*\.\s*value\s*!')

for path in sorted(LIB.rglob('*.dart')):
    code = live(path)
    lines = code.split('\n')

    for match in WATCH_VALUE.finditer(code):
        line = code[:match.start()].count('\n') + 1
        failures.append(
            f'{path.relative_to(REPO)}:{line} reads `.value` straight off a '
            'provider. `AsyncValue.value` RETHROWS on an error state '
            '(riverpod/lib/src/common.dart:493) — in a `build` that is a '
            'pale rectangle on a release handset. Use `.valueOrNull`.')

    for match in BANG_VALUE.finditer(code):
        line = code[:match.start()].count('\n') + 1
        window = '\n'.join(lines[max(0, line - 7):line])
        if 'hasValue' in window:
            continue
        failures.append(
            f'{path.relative_to(REPO)}:{line} uses `{match.group(1)}.value!` '
            'with no `hasValue` guard in the six lines above it. '
            '`AsyncValue.value` throws before the `!` is reached, so the '
            'guard is the only thing making this safe and it has to be '
            'visible beside it.')

if failures:
    print('An async read that can rethrow into a build:\n')
    for message in failures:
        print(f'  * {message}\n')
    sys.exit(1)

checked = sum(1 for _ in LIB.rglob('*.dart'))
print('OK: no async read can rethrow into a build.')
print(f'  * {checked} Dart files; no `.value` taken straight off a provider')
print('  * every `.value!` sits under a visible `hasValue` guard')
