#!/usr/bin/env python3
"""One rule for "three presses in three seconds", written twice.

    python3 scripts/check_the_two_sos_tap_rules_agree.py

## What is being pinned

Volume Down ×3 raises a Silent SOS. The rule that decides what counts exists in
two languages, because the two run in different places:

  * `lib/core/sos/triple_tap.dart` — presses the app itself sees, while it is
    on screen. Well tested.
  * `android/.../VolumePressCounter.kt` — presses the accessibility service
    sees while the phone is LOCKED and the app is not on screen. Until this
    gate, asserted by nothing at all: this repository has no Android unit
    tests, no gradle wrapper and no SDK in CI, so the Kotlin half was read and
    believed.

They agree today because one person wrote both. Nothing kept them agreeing.
Drift here is silent and only shows up on a locked phone in an emergency: a
window shortened in one place and not the other makes the control harder to
fire exactly when somebody's hands are not steady, and a count lowered makes a
pocket send a responder to nowhere.

The preference key is pinned for the same reason. Dart writes
`volume_sos_enabled` through shared_preferences, which on Android stores it in
the `FlutterSharedPreferences` file under a `flutter.` prefix; the service
reads that file directly, because it runs with no Flutter engine. Two spellings
of one key, in two languages, and if they ever disagree the switch in Settings
silently does nothing on a locked phone — the exact complaint that started this.

## What this checks

1. The window and the count match across Dart and Kotlin.
2. The preference key matches, prefix included.
3. VolumePressCounter stays in a file that imports nothing, so it can be
   compiled and run with kotlinc alone — no SDK, no Gradle, no emulator.
4. Its behaviour test still exists and still covers the cases that matter.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DART_RULE = REPO / 'lib/core/sos/triple_tap.dart'
DART_PREF = REPO / 'lib/core/sos/volume_sos.dart'
KOTLIN_RULE = (REPO / 'android/app/src/main/kotlin/com/RainbowEwer/RainbowEwer'
               / 'VolumePressCounter.kt')
KOTLIN_BRIDGE = (REPO / 'android/app/src/main/kotlin/com/RainbowEwer/RainbowEwer'
                 / 'VolumeSosBridge.kt')
KOTLIN_TEST = (REPO / 'android/app/src/test/kotlin/com/RainbowEwer/RainbowEwer'
               / 'VolumePressCounterTest.kt')

faults: list[str] = []
proved: list[str] = []

for path in (DART_RULE, DART_PREF, KOTLIN_RULE, KOTLIN_BRIDGE, KOTLIN_TEST):
    if not path.is_file():
        print(f'FAIL: {path.relative_to(REPO)} is missing.')
        sys.exit(1)

dart_rule = DART_RULE.read_text(encoding='utf-8')
dart_pref = DART_PREF.read_text(encoding='utf-8')
kotlin_rule = KOTLIN_RULE.read_text(encoding='utf-8')
kotlin_bridge = KOTLIN_BRIDGE.read_text(encoding='utf-8')
kotlin_test = KOTLIN_TEST.read_text(encoding='utf-8')


def one(pattern: str, text: str, what: str) -> str | None:
    found = re.findall(pattern, text)
    if len(found) != 1:
        faults.append(f'Could not read {what} ({len(found)} matches). This '
                      'gate compares two literals; if either moved, it has to '
                      'be taught where they went rather than quietly passing.')
        return None
    return found[0]


# 1. The window and the count.
dart_seconds = one(r'const Duration sosTapWindow = Duration\(seconds: (\d+)\);',
                   dart_rule, 'sosTapWindow in triple_tap.dart')
dart_taps = one(r'const int sosTapsRequired = (\d+);',
                dart_rule, 'sosTapsRequired in triple_tap.dart')
kotlin_ms = one(r'windowMs: Long = (\d+)', kotlin_rule,
                'windowMs in VolumePressCounter.kt')
kotlin_needed = one(r'needed: Int = (\d+)', kotlin_rule,
                    'needed in VolumePressCounter.kt')

if None not in (dart_seconds, kotlin_ms):
    if int(dart_seconds) * 1000 != int(kotlin_ms):
        faults.append(
            f'The window disagrees: Dart waits {dart_seconds}s '
            f'({int(dart_seconds) * 1000}ms), Kotlin waits {kotlin_ms}ms. The '
            'same three presses would send from inside the app and not from a '
            'locked phone, or the other way round.')
    else:
        proved.append(f'both halves use a {dart_seconds}-second window')

if None not in (dart_taps, kotlin_needed):
    if int(dart_taps) != int(kotlin_needed):
        faults.append(
            f'The count disagrees: Dart needs {dart_taps} presses, Kotlin '
            f'needs {kotlin_needed}. Fewer presses on a locked phone means '
            'volume changes in a pocket raise silent alerts.')
    else:
        proved.append(f'both halves need {dart_taps} presses')

# 2. The preference key, prefix included.
dart_key = one(r"const String volumeSosPreferenceKey = '([^']+)';",
               dart_pref, 'volumeSosPreferenceKey in volume_sos.dart')
kotlin_key = one(r'ENABLED_KEY = "([^"]+)"', kotlin_bridge,
                 'ENABLED_KEY in VolumeSosBridge.kt')
if None not in (dart_key, kotlin_key):
    if kotlin_key != f'flutter.{dart_key}':
        faults.append(
            f'The preference key disagrees: Dart writes "{dart_key}" (stored '
            f'as "flutter.{dart_key}") and the service reads "{kotlin_key}". '
            'The switch in Settings would do nothing on a locked phone, and '
            'nothing anywhere would say why.')
    else:
        proved.append(f'the service reads the key Dart writes '
                      f'("{kotlin_key}")')

# 3. The counter must stay compilable on its own.
imports = [l for l in kotlin_rule.splitlines() if l.startswith('import ')]
if imports:
    faults.append(
        'VolumePressCounter.kt imports '
        f'{", ".join(i.split()[1] for i in imports)}. It is in its own file '
        'precisely so it needs no Android toolchain: with an import it can '
        'only be built with the SDK, which CI does not have, and its test '
        'stops running.')
elif 'class VolumePressCounter' in kotlin_bridge:
    faults.append(
        'VolumePressCounter is defined in VolumeSosBridge.kt again, which '
        'imports android.* and io.flutter.*. That is what made it untestable.')
else:
    proved.append('the counter imports nothing, so kotlinc alone can run it')

# 4. The behaviour test still covers what matters.
REQUIRED = {
    'two presses send nothing': 'a pocket must not raise an SOS',
    'the third press inside the window sends': 'the control must work',
    'a fourth press does not send again': 'one set must not send twice',
    'clock that jumps backwards': 'a wedged counter fails silently',
}
missing = [why for probe, why in REQUIRED.items() if probe not in kotlin_test]
if missing:
    faults.append(
        'VolumePressCounterTest.kt no longer covers: ' + '; '.join(missing)
        + '. Each was mutation-tested when it was written — breaking the '
        'counter in that way failed that check and no other.')
else:
    proved.append('the behaviour test still covers the four cases that matter')

if faults:
    print('FAIL: the two halves of Volume Down x3 do not agree.\n')
    for fault in faults:
        print(f'  - {fault}\n')
    sys.exit(1)

print('OK: the app and the locked-phone service use one rule.')
for item in proved:
    print(f'  * {item}')
