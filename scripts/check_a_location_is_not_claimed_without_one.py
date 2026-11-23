#!/usr/bin/env python3
"""The emergency screen must not claim a location it has not got.

    python3 scripts/check_a_location_is_not_claimed_without_one.py

## What went wrong

A citizen pressed SOS on a real handset in Jos and the emergency screen showed
them this:

    LOCATION BROADCASTING
    Alert transmitted · Command HQ triaging...

    LATITUDE   ---        LONGITUDE  ---

Both at once, over a blank grey map. The phone had no GPS fix at all. The alert
reached HQ carrying `latitude: null, longitude: null`
(`lib/providers/emergency_provider.dart` passes `currentPos?.latitude`), and the
screen told the person their position was going out.

It happened because the banner was driven by the ALERT'S STATUS and nothing
else. `_buildStatusCard` read the `alerts` row, and a status of `PENDING` fell
through to an `else` branch that said `eme_broadcasting` — "LOCATION
BROADCASTING" — without ever looking at the position. The readout beside it
read the position directly, so the two halves of one screen disagreed, and the
half a frightened person reads first was the lie.

Three more strings on the same screen promised the same thing unconditionally:

  * `eme_sending_desc`       "Sending your alert AND LOCATION to HQ..."
  * `eme_broadcasting_triaging` shown under ALERT RECEIVED
  * `eme_not_confirmed_desc` "...YOUR LOCATION IS STILL BEING RECORDED."

This is the C-5 family again, inverted. C-5 was a screen inventing coordinates
it did not have; `check_no_invented_coordinates.py` was written to stop that.
This screen invented the TRANSMISSION rather than the coordinates — it had no
number to make up, so it made up the act of sending one — and no gate was
watching that side.

The second half of the fault was that there was no way out. `streamLocation()`
emitted one null when permission was refused and then `return`ed, closing the
stream for the life of the process. A permission granted afterwards — in
Android's settings, or from this screen — reached nothing, so `---` was
permanent until the app was restarted, and the screen offered no prompt at all.

## What this checks

1. `_buildStatusCard` is given the location and derives `hasFix` from it.
2. Every string on that screen that promises a location is behind `hasFix`,
   and has a truthful `_no_fix` counterpart for all three languages.
3. The screen carries a warning, in the build tree, for when there is no fix,
   and a control that asks for location from there.
4. The location stream keeps looking instead of giving up at the first
   refusal, and its Dart test proves it.
5. A widget test builds the real screen, delivers a PENDING alert row with no
   fix, and reads what the screen shows — with a control case proving the
   assertion is capable of failing.
6. CI drives the built app in a real browser with geolocation REFUSED, which
   no other pass does.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCREEN = REPO / 'lib/features/emergency/emergency_active_screen.dart'
SERVICE = REPO / 'lib/services/location_service.dart'
STRINGS = REPO / 'lib/shared/localization/translations.dart'
SERVICE_TEST = REPO / 'test/location_service_test.dart'
SCREEN_TEST = REPO / 'test/emergency_screen_tells_the_truth_about_location_test.dart'
E2E = REPO / 'scripts/local_e2e/mobile_no_location.js'
WORKFLOW = REPO / '.github/workflows/ci.yml'

# Each string that promises a location, and the truthful one that must exist
# for the case where there is none.
CLAIMS = {
    'eme_broadcasting': 'eme_active_no_fix',
    'eme_broadcasting_triaging': 'eme_triaging_no_fix',
    'eme_sending_desc': 'eme_sending_desc_no_fix',
    'eme_not_confirmed_desc': 'eme_not_confirmed_desc_no_fix',
}
LANGUAGES = ('english', 'hausa', 'pidgin')

faults: list[str] = []
proved: list[str] = []

for path in (SCREEN, SERVICE, STRINGS, SERVICE_TEST, SCREEN_TEST, E2E,
             WORKFLOW):
    if not path.is_file():
        print(f'FAIL: {path.relative_to(REPO)} is missing.')
        sys.exit(1)

screen = SCREEN.read_text(encoding='utf-8')
service = SERVICE.read_text(encoding='utf-8')
strings = STRINGS.read_text(encoding='utf-8')
service_test = SERVICE_TEST.read_text(encoding='utf-8')
screen_test = SCREEN_TEST.read_text(encoding='utf-8')
workflow = WORKFLOW.read_text(encoding='utf-8')

# 1. The status card must be given the position.
if not re.search(r'Widget _buildStatusCard\(\s*AsyncValue<Position\?>', screen):
    faults.append(
        '_buildStatusCard() does not take the location. It was driven by the '
        "alert's status alone, which is how it came to read LOCATION "
        'BROADCASTING over a row of dashes.')
elif not re.search(r'final hasFix = locAsync\.valueOrNull != null;', screen):
    faults.append(
        '_buildStatusCard() takes the location but derives no `hasFix` from '
        'it, so nothing in the card can be conditional on having a position.')
else:
    proved.append('the status card is given the position and derives hasFix')

# 2. Every claiming string is behind hasFix, and has a truthful counterpart.
for claim, truthful in CLAIMS.items():
    for match in re.finditer(r"_t\(\s*(?:[^)]*?)'" + re.escape(claim) + r"'", screen):
        window = screen[max(0, match.start() - 60):match.end()]
        if 'hasFix' not in window:
            line = screen[:match.start()].count('\n') + 1
            faults.append(
                f"emergency_active_screen.dart:{line} shows '{claim}' without "
                'checking hasFix, so it promises a location the phone may not '
                'have.')
    if f"'{truthful}'" not in screen:
        faults.append(
            f"The screen never uses '{truthful}', so there is nothing "
            f"truthful to show in place of '{claim}' when there is no fix.")
    block = re.search(r"'" + re.escape(truthful) + r"'\s*:\s*\{(.*?)\n    \}",
                      strings, re.S)
    if block is None:
        faults.append(
            f"translations.dart defines no '{truthful}'. A screen cannot tell "
            'the truth in a language it has no words for.')
        continue
    missing = [lang for lang in LANGUAGES
               if f'AppLanguage.{lang}:' not in block.group(1)]
    if missing:
        faults.append(
            f"'{truthful}' is missing {', '.join(missing)}. Plateau Eye is "
            'used in three languages and this is the sentence that stops a '
            'person trusting a position that was never sent.')

if not any('hasFix' in f or 'truthful' in f or 'no fix' in f for f in faults):
    proved.append('every string that promises a location is behind hasFix, '
                  'in all three languages')

# 3. The warning, and a way to act on it, must be on the screen and in the
#    tree. A widget built by a method nothing calls warns nobody.
if "ValueKey('emergency_no_location_warning')" not in screen:
    faults.append(
        'The screen has no keyed no-location warning. Truthful banner text is '
        'not enough on its own: the person needs to be told plainly that HQ '
        'has their alert but not their position.')
elif not re.search(r'_buildNoLocationCard\(locAsync\),', screen):
    faults.append(
        '_buildNoLocationCard() is defined but never placed in the build '
        'tree, so the warning it draws reaches nobody.')
elif "ValueKey('emergency_turn_on_location')" not in screen:
    faults.append(
        'The no-location warning offers no way to turn location on. '
        'requestPermission() returns false WITHOUT asking when the onboarding '
        'disclosure was never accepted, so a person in this state is never '
        'prompted and has nothing to press.')
elif 'requestPermission(force: true)' not in screen:
    faults.append(
        'The screen asks for location without `force: true`, which returns '
        'false without showing a prompt whenever the onboarding disclosure '
        'was not accepted — the very case this card exists for.')
else:
    proved.append('the screen warns when it has no fix, and can ask for one')

# 4. The stream must keep looking, and be provably able to.
if 'while (!cancelled)' not in service:
    faults.append(
        'streamLocation() no longer keeps looking. It used to emit one null '
        'and return, closing the stream for the life of the process, so a '
        'permission granted afterwards changed nothing and the screen read '
        '`---` until the app was restarted.')
elif 'Future<bool> hasPermissionNow()' not in service:
    faults.append(
        'streamLocation() has no silent permission check, so each look would '
        'risk putting the system dialog in front of somebody again.')
elif 'keeps looking' not in service_test:
    faults.append(
        'test/location_service_test.dart does not prove that a permission '
        'granted later reaches the app. That is the whole repair; without a '
        'test it will be refactored away.')
else:
    proved.append('the location stream keeps looking, and a test proves it')

# 5. The screen's behaviour must be tested, not just its shape.
#
# THIS GATE IS NOT ENOUGH ON ITS OWN, and that is not a guess. The first
# widget test written for this screen asserted that LOCATION BROADCASTING was
# absent — and PASSED when the original bug was mutated back in. The branch
# that prints it only runs when the `alerts` row arrives, the test gave the
# screen no alert id, so the StreamBuilder got Stream.empty() and the branch
# never ran at all. The assertion could not fail. Hence `alertRowStreamProvider`:
# a seam that lets a test deliver a PENDING row and reach the branch.
if 'alertRowStreamProvider' not in screen:
    faults.append(
        'The alert row stream is not behind a provider, so no test can deliver '
        'a PENDING row and reach the branch that printed LOCATION '
        'BROADCASTING. A widget test for it would pass whether or not the bug '
        'was there — one did.')
elif 'alertRowStreamProvider.overrideWith' not in screen_test:
    faults.append(
        'No test overrides alertRowStreamProvider, so nothing drives the '
        'PENDING branch this gate exists for.')
elif "hqStatus: 'PENDING'" not in screen_test:
    faults.append(
        'No test drives a PENDING alert, which is the exact state the citizen '
        'in Jos was in when the screen told them their location was '
        'broadcasting.')
elif "eme_broadcasting')), findsOneWidget" not in screen_test:
    faults.append(
        'Nothing proves the test can SEE the LOCATION BROADCASTING string '
        'when it is legitimately shown. Without that control, an absence '
        'assertion is indistinguishable from a finder that never matches.')
else:
    proved.append('a widget test drives the real PENDING branch, with a '
                  'control proving the assertion can fail')

# 6. And the real screen, in a real browser, with the permission really
#    refused. mobile_interact.js GRANTS geolocation before it touches SOS —
#    deliberately, and correctly for that pass — so every other automated run
#    over this screen has had a position. That is why nothing caught this.
if 'node scripts/local_e2e/mobile_no_location.js' not in workflow:
    faults.append(
        'The no-location browser pass is not run by CI. Every other pass over '
        'this screen grants geolocation, so without this one the state the '
        'citizen in Jos was actually in is never exercised.')
else:
    proved.append('CI drives the real screen in a browser with geolocation '
                  'refused')

if faults:
    print('FAIL: a location may be claimed on a phone that has not got one.\n')
    for fault in faults:
        print(f'  - {fault}\n')
    sys.exit(1)

print('OK: the emergency screen claims a location only when it has one.')
for item in proved:
    print(f'  * {item}')
