#!/usr/bin/env python3
"""The APK job must pin a JDK new enough for AGP 9's lint.

    python3 scripts/check_the_apk_build_pins_its_jdk.py

## What went wrong

`flutter build apk --release` compiled every plugin, reached
`:image_picker_android:lintVitalAnalyzeRelease`, and died there:

    Unexpected failure during lint analysis of ExifDataCopier.java
    Message: 'java.lang.Object java.util.List.removeLast()'
    NoSuchMethodError: JavaDocParser.parseDataItem(JavaDocParser.kt:117)

`List.removeLast()` is a Java 21 method — it arrived with
`SequencedCollection`. The IntelliJ parser bundled inside AGP 9.3.1's lint is
compiled against it, so lint cannot run at all on a JDK older than 21. Nothing
in this app's code was wrong, and no change to it would have helped.

The job never said which JDK it wanted, so it got the runner image's default,
which on `ubuntu-24.04` is 17. Android Studio bundles JBR 21 and hands Gradle
that, so a developer building the same commit on a laptop would never see it —
the failure belonged entirely to the unpinned JDK in CI.

An unpinned JDK is also a build that changes under you: GitHub re-images its
runners, and the day the default moves the build's behaviour moves with it,
with nothing in the diff to explain why.

## What this checks

The `android-apk` job sets up a JDK of at least 21 with `actions/setup-java`,
and does it BEFORE `subosito/flutter-action` — Flutter resolves the JDK from
`JAVA_HOME`, so a setup-java step placed after it configures a toolchain
nothing has asked for yet.

Whole-line comments are dropped before anything is matched, because the step
above this one in the workflow carries a paragraph quoting the error, the
version number and the action's name. A step deleted with its explanation left
behind would otherwise still read as present.

## What it does not check

That the build passes, or that JDK 21 is the right floor forever. If a later
AGP needs 25, this gate goes on passing and the build tells you.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CI = REPO / '.github' / 'workflows' / 'ci.yml'
JOB = 'android-apk'
FLOOR = 21

if not CI.exists():
    print(f'{CI.relative_to(REPO)} does not exist, so nothing builds an APK.')
    sys.exit(1)


def uncommented(text: str) -> str:
    """Drop whole-line comments, so prose about a step is not the step."""
    return '\n'.join(
        line for line in text.split('\n') if not line.lstrip().startswith('#'))


ci = uncommented(CI.read_text())

# The job's own block: from `  android-apk:` to the next key at the same
# indent. Jobs are two spaces in under `jobs:`.
match = re.search(
    rf'^  {re.escape(JOB)}:\n(?P<body>(?:(?:    .*)?\n)*)', ci, re.MULTILINE)
if not match:
    print(f'ci.yml has no `{JOB}:` job, so nothing builds an APK.')
    print('If the job was renamed, rename it here too — this gate is blind to')
    print('a job it cannot find, and a blind gate reads as a passing one.')
    sys.exit(1)

body = match.group('body')

setup_java = re.search(r'uses:\s*actions/setup-java@', body)
if not setup_java:
    print(f'The `{JOB}` job does not use actions/setup-java.')
    print()
    print('It therefore builds on whatever JDK the runner image happens to')
    print(f'ship. `ubuntu-24.04` ships 17, and AGP 9 lint needs {FLOOR}:')
    print("  NoSuchMethodError: 'java.lang.Object java.util.List.removeLast()'")
    sys.exit(1)

version = re.search(r'''java-version:\s*['"]?(\d+)''', body)
if not version:
    print(f'The `{JOB}` job sets up a JDK but names no java-version.')
    sys.exit(1)

got = int(version.group(1))
if got < FLOOR:
    print(f'The `{JOB}` job pins JDK {got}; AGP 9 lint needs at least {FLOOR}.')
    print()
    print('On an older JDK the release build compiles every plugin and then')
    print('dies in lintVitalAnalyzeRelease, because the IntelliJ parser inside')
    print('lint calls java.util.List.removeLast(), which is Java 21.')
    sys.exit(1)

flutter = re.search(r'uses:\s*subosito/flutter-action@', body)
if not flutter:
    print(f'The `{JOB}` job does not use subosito/flutter-action.')
    print('This gate checks the JDK is set up before Flutter is, and it can no')
    print('longer tell. Point it at whatever installs Flutter now.')
    sys.exit(1)

if setup_java.start() > flutter.start():
    print(f'The `{JOB}` job sets up its JDK AFTER Flutter.')
    print()
    print('Flutter resolves the JDK from JAVA_HOME when it runs Gradle, so the')
    print('setup-java step has to come first to be the one that is used.')
    sys.exit(1)

print(f'OK: the {JOB} job pins JDK {got} (>= {FLOOR}) before Flutter is set up.')
