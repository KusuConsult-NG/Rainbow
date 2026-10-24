#!/usr/bin/env python3
"""The app must reach a usable screen with no network.

    python3 scripts/check_the_app_opens_without_a_network.py

## What went wrong

The app did not start without a network. Not "worked in a reduced way" — did
not get past the splash.

A signed-in handset restores its session from local storage, needing no
network. `AuthNotifier.resolveRole()` then set `isLoading = true` and issued a
PostgREST fetch of `profiles` with **no timeout**. `computeRedirect()` opens
with `if (isLoading) return null;`, so the router is pinned to the splash for
as long as that fetch is in flight — and with no network it is in flight for
however long the operating system takes to abandon a TCP connection to an
unreachable host, which on Android is minutes.

The only guard was a single `Future.delayed(Duration(seconds: 5))` armed in the
notifier's constructor. `resolveRole` is a SECOND entry into loading, and by
the time it runs that timer has fired and is gone. A guard that runs once
protects only the first case.

When the fetch finally failed, the handler set `resolutionError`, and
`computeRedirect` reads a resolution error as terminal and returns
`AppRoutes.login` — offering the one action that requires a network as the way
out of having none.

Everything else in this product is built for that case: the offline alert
queue, the Bluetooth mesh, the encrypted SMS fallback, the USSD path. All of it
sat behind a screen the user could not reach.

## What this checks

1. The profile fetch on the resolution path is bounded. It is the step that
   holds the router.
2. The loading watchdog is armed in `resolveRole` as well as in the
   constructor, because that is the entry that hung.
3. The failure path consults this handset's own record before declaring the
   role unknown — otherwise a bounded timeout just reaches the login screen
   faster.
4. Every sign-out path forgets that record. There are two, and a shared handset
   in a command post must not open as the previous holder.
5. The record is scoped to the account it was written for.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROVIDER = REPO / 'lib/providers/auth_provider.dart'
CACHE = REPO / 'lib/core/auth/last_known_role.dart'
ROUTER = REPO / 'lib/core/router/app_router.dart'
SIGN_OUTS = (PROVIDER, REPO / 'lib/services/auth_service.dart')

faults: list[str] = []
proved: list[str] = []


def live(path: Path) -> str:
    """Comments blanked, newlines kept so line numbers stay true."""
    src = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)),
                 path.read_text(encoding='utf-8'), flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n'))


for path in (PROVIDER, CACHE, ROUTER):
    if not path.is_file():
        faults.append(f'{path.relative_to(REPO)} is missing')
if faults:
    print('FAIL: the app may not open without a network.\n')
    for f in faults:
        print(f'  - {f}\n')
    sys.exit(1)

provider = live(PROVIDER)
cache = live(CACHE)
router = live(ROUTER)

# ── 0. the premise: the router really is held by isLoading ─────────────────
#
# Checked rather than assumed, because every assertion below is about that one
# fact. If the router stops holding on isLoading, these checks are guarding
# something that no longer matters and should be rewritten, not left passing.
if not re.search(r'if\s*\(isLoading\)\s*return null;', router):
    faults.append(
        'computeRedirect no longer holds on `isLoading`. Every check in this '
        'file exists because it did — if that changed, this gate is measuring '
        'the wrong thing and needs rewriting rather than passing.')
else:
    proved.append('the router is still held by isLoading, which is why the '
                  'rest of this matters')

# ── 1. the step that holds the router is bounded ───────────────────────────
resolve = re.search(r'Future<void> resolveRole\(User user\) async \{(.*?)\n  \}',
                    provider, re.S)
if resolve is None:
    faults.append('there is no `resolveRole` to check')
else:
    body = resolve.group(1)
    # Every awaited PostgREST call in here. `.maybeSingle()`, `.select()` and
    # `.single()` are the shapes this file uses.
    for m in re.finditer(r'await SupabaseConfig\.client(.*?);', body, re.S):
        call = m.group(1)
        if '.timeout(' not in call:
            line = provider.count('\n', 0, resolve.start(1) + m.start()) + 1
            faults.append(
                f'{PROVIDER.relative_to(REPO)}:{line} awaits the backend with '
                f'no `.timeout(...)`, on the path that holds the router on the '
                f'splash. With no network that is not a slow start, it is no '
                f'start: the OS waits out a TCP connection to an unreachable '
                f'host before the app draws anything usable.')
    if not re.search(r'static const Duration resolveTimeout', provider):
        faults.append(
            'AuthNotifier declares no `resolveTimeout`, so the bound is a '
            'literal at each call site and nothing can assert it is short.')
    if not faults:
        proved.append('every backend await in resolveRole is bounded by '
                      'resolveTimeout')

    # ── 2. the watchdog covers this entry, not just the first ──────────────
    if '_armLoadingWatchdog()' not in body:
        faults.append(
            '`resolveRole` does not arm the loading watchdog. It is a SECOND '
            'entry into `isLoading = true`, and the one in the constructor has '
            'already fired by then — which is exactly why nothing was watching '
            'the step that hung.')
    else:
        proved.append('the watchdog is re-armed on every entry into loading')

    # ── 3. a failure consults what this handset already knows ──────────────
    after_catch = body[body.index('catch'):] if 'catch' in body else ''
    if 'readLastKnownRole' not in after_catch:
        faults.append(
            '`resolveRole`\'s failure path does not read this handset\'s own '
            'record. A bounded timeout without it only reaches the login '
            'screen faster, and offline a login screen cannot succeed.')
    else:
        unknown = after_catch.find('UserRole.unknown')
        remembered = after_catch.find('readLastKnownRole')
        if unknown != -1 and unknown < remembered:
            faults.append(
                'the failure path declares the role unknown BEFORE consulting '
                'the stored one, so the router sees an unresolved role and '
                'sends the user to login regardless.')
        else:
            proved.append('a failed resolution opens as who this handset last '
                          'resolved, when it knows')

# ── 4. every sign-out forgets it ───────────────────────────────────────────
for path in SIGN_OUTS:
    code = live(path)
    for m in re.finditer(r'auth\.signOut\(\)', code):
        # The clearing call has to be in the same function, ahead of it.
        start = code.rfind('\n  Future<', 0, m.start())
        window = code[max(0, start):m.start()]
        if 'clearLastKnownRole' not in window:
            line = code.count('\n', 0, m.start()) + 1
            faults.append(
                f'{path.relative_to(REPO)}:{line} signs out without clearing '
                f'the stored role first. A handset in a command post is '
                f'shared, and the next person to open it would get the '
                f'previous holder\'s board and jurisdiction. Before the call, '
                f'not after: signOut() reaches the network and throws when it '
                f'cannot.')
if not any('signs out without clearing' in f for f in faults):
    proved.append(f'both sign-out paths forget the record first')

# ── 5. the record belongs to one account ───────────────────────────────────
if not re.search(r'identity\.userId != userId', cache):
    faults.append(
        '`readLastKnownRole` does not check that the stored record belongs to '
        'the account asking for it, so a shared handset can open as whoever '
        'used it last.')
else:
    proved.append('the record is only ever returned to the account it was '
                  'written for')

if faults:
    print('FAIL: the app may not open without a network.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-100.')
    sys.exit(1)

print('OK: the app reaches a usable screen with no network.')
for item in proved:
    print(f'  * {item}')
