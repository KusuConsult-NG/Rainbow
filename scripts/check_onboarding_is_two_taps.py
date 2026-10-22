#!/usr/bin/env python3
"""Setup is two steps, one permission prompt, and asks for no identity.

    python3 scripts/check_onboarding_is_two_taps.py

## The scope this holds the code to

> i just want users to signup using their phone number and use the app to send
> alert … users are supposed to use the app anonymously. they need the mobile
> number for signup and they grant access to location at the point of setup …
> Users shouldn't go through a lot before using the app. it should just be
> simple taps … This means that profile is optional as well

So: phone number in, one permission prompt, two PINs, done. No name, no NIN,
no next of kin, nothing a person can be identified by beyond the number a
responder needs in order to call them back.

## What it was

Four prompts in sequence — a disclosure modal, `Permission.location.request()`,
`Permission.locationAlways.request()` behind a 3-second timeout, then three
more `.request()` calls — and then a THREE-step wizard whose second step
demanded a name, an NIN, a gender and an LGA before anybody could reach the
SOS button. `onboarding_profile_screen.dart` was what called
`setOnboarded(true)`, so that form was not optional: it was the gate.

Two things were broken beyond the tapping. The 3-second timeout raced the OS —
`locationAlways` shows no dialog on Android 11+, it opens Settings, so the
timeout fired on a prompt that was never coming and the next `.request()` went
out while one was still in flight, which Android denies without asking. And a
declined location ended setup in an unskippable "You cannot proceed" dialog:
the person most likely to refuse a location prompt with somebody watching is
exactly the person a duress alarm exists for.

## What this checks

1. The permissions screen makes ONE batched `[...].request()` and no bare
   sequential `Permission.x.request()` calls.
2. It never requests `locationAlways` — the source of the race.
3. No `.timeout(` anywhere near a permission request.
4. It leads to the PIN screen, and to neither the profile nor the contacts
   screen.
5. The PIN screen is what calls `setOnboarded(true)`.
6. Neither the profile nor the contacts screen calls `setOnboarded` — if
   either does, it is a gate again whatever the router says.
7. `emergencyPins` is declared OUTSIDE the navigation shell, so no tabs or
   drawer render mid-setup.
8. The step indicator says 2, not 3.

Exit 0 and say what was proved; exit 1 and name what regressed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PERMS = REPO / 'lib/features/onboarding/onboarding_permissions_screen.dart'
PROFILE = REPO / 'lib/features/onboarding/onboarding_profile_screen.dart'
CONTACTS = REPO / 'lib/features/onboarding/onboarding_contacts_screen.dart'
PINS = REPO / 'lib/features/settings/emergency_pin_screen.dart'
ROUTER = REPO / 'lib/core/router/app_router.dart'

faults: list[str] = []
proved: list[str] = []


def live(path: Path) -> str:
    """The file with comments blanked, newlines kept, so line numbers hold."""
    if not path.exists():
        faults.append(f'{path.relative_to(REPO)} is missing')
        return ''
    src = re.sub(r'/\*.*?\*/',
                 lambda m: re.sub(r'[^\n]', ' ', m.group(0)),
                 path.read_text(), flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n'))


perms, profile, contacts, pins, router = (
    live(p) for p in (PERMS, PROFILE, CONTACTS, PINS, ROUTER))
if faults:
    print('FAIL: setup cannot be checked.')
    for f in faults:
        print(f'  - {f}')
    sys.exit(1)

# ── 1 + 2 + 3. one prompt ───────────────────────────────────────────────────
batched = re.search(r'\]\s*\.request\(\)', perms)
if batched:
    proved.append('one batched [...].request() for every permission')
else:
    faults.append(
        'the permissions screen makes no batched `[...].request()`. One call '
        'is what lets the OS present a single flow; separate calls are four '
        'dialogs, and a second request made while one is open is denied '
        'without being shown.')

sequential = [
    m.group(0) for m in re.finditer(r'Permission\.\w+\.request\(\)', perms)
]
if sequential:
    faults.append(
        f'the permissions screen still calls {", ".join(sorted(set(sequential)))} '
        f'one at a time. That is the prompt-per-permission flow this replaced.')
else:
    proved.append('no permission is requested on its own')

if 'locationAlways' in perms:
    faults.append(
        'the permissions screen still touches `locationAlways`. On Android '
        '11+ it opens Settings rather than a dialog, which is what the '
        '3-second timeout was racing. Background tracking runs in a '
        'foreground service and needs only foreground location.')
else:
    proved.append('locationAlways is not requested during setup')

if re.search(r'\.request\(\)\s*\.timeout\(|\.timeout\(\s*\n?\s*const Duration', perms):
    faults.append(
        'a permission request in the permissions screen is wrapped in '
        '`.timeout(`. A timeout on an OS prompt races the user, not the code.')
else:
    proved.append('no permission request is raced by a timeout')

# ── 4. where setup leads ────────────────────────────────────────────────────
for route, why in (
    ('onboardingProfile', 'a name, an NIN, a gender and an LGA'),
    ('onboardingContacts', 'next-of-kin details'),
):
    if re.search(rf'context\.go\(\s*AppRoutes\.{route}', perms):
        faults.append(
            f'the permissions screen still sends people to `{route}`, which '
            f'asks for {why}. That is not in this app\'s scope and it is not '
            f'a step anybody should have to pass to reach the SOS button.')
if not re.search(r'context\.go\(\s*AppRoutes\.emergencyPins', perms):
    faults.append(
        'the permissions screen does not lead to `emergencyPins`. The PINs '
        'are the second and last step of setup.')
else:
    proved.append('permissions leads straight to the PINs')

if '_skipIfAlreadyGranted' not in perms:
    faults.append(
        'the permissions screen has no `_skipIfAlreadyGranted`, so a returning '
        'user is shown an explainer for a decision the OS already remembers.')
else:
    proved.append('a returning user never sees the permissions screen twice')

# ── 5 + 6. what completes setup ─────────────────────────────────────────────
if not re.search(r'setOnboarded\(true\)', pins):
    faults.append(
        f'{PINS.relative_to(REPO)} does not call `setOnboarded(true)`. It is '
        'the last step of setup, so if it does not mark it, nothing does and '
        'the wizard reappears on the next launch.')
else:
    proved.append('the PIN screen is what completes setup')

for path, text in ((PROFILE, profile), (CONTACTS, contacts)):
    if 'setOnboarded' in text:
        faults.append(
            f'{path.relative_to(REPO)} calls `setOnboarded`. That makes it a '
            f'gate again whatever the router says — which is exactly how a '
            f'name and an NIN became compulsory.')
if not any('setOnboarded' in t for t in (profile, contacts)):
    proved.append('neither the profile nor the contacts screen gates setup')

# ── 7. the PIN route is outside the shell ───────────────────────────────────
shell = router.find('ShellRoute(')
pin_route = router.find('path: AppRoutes.emergencyPins')
if shell == -1:
    faults.append('no ShellRoute in the router, so this cannot be checked')
elif pin_route == -1:
    faults.append('the router declares no emergencyPins route')
elif pin_route > shell:
    faults.append(
        'the `emergencyPins` route is declared inside `ShellRoute`, so the '
        'bottom navigation and the drawer paint over the last step of setup. '
        'Tapping one of those destinations leaves a person with no PINs and '
        'hasOnboarded false — back to the start.')
else:
    proved.append('the PIN route sits outside the navigation shell')

# ── 8. the step count ───────────────────────────────────────────────────────
step = re.search(r"'STEP \$step / (\d+)'", perms)
if step is None:
    faults.append('the permissions screen shows no step indicator')
elif step.group(1) != '2':
    faults.append(
        f'the step indicator reads "/ {step.group(1)}". Setup is two steps: '
        f'permissions, then PINs.')
else:
    proved.append('the indicator says 2 steps, which is how many there are')

if faults:
    print('FAIL: setup is not two taps any more.\n')
    for f in faults:
        print(f'  - {f}\n')
    sys.exit(1)

print('OK: setup is one permission prompt and two PINs.')
for item in proved:
    print(f'  * {item}')
