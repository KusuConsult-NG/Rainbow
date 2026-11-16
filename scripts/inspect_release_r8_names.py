#!/usr/bin/env python3
"""Check that R8 kept every class Android looks up by name in a release build.

    flutter build apk --release
    python3 scripts/inspect_release_r8_names.py

Why this exists. Release builds set `isMinifyEnabled = true`, so R8 renames
and removes classes it cannot see being used. Android itself starts every
activity, service, receiver and provider in the merged manifest by its CLASS
NAME, and WorkManager stores a worker's class name and instantiates it later
by that name. A class renamed or stripped there compiles, installs, and fails
only on a phone, at the moment it is needed: a background SOS that never runs,
a Guardian notification whose Stop button does nothing.

`android/app/proguard-rules.pro` is a hand-kept list of six plugins, and the
audit (E2E_AUDIT_REPORT.md, "Two things found on the way") noted that
workmanager, just_audio and sentry_flutter are not on it. Whether that matters
depends on the rules each library ships for itself, which no one can tell by
reading the list. This reads what R8 actually did instead.

What it checks, from the last release build's own output:
  * every component the merged release manifest names exists in the APK
    under that exact name (R8's mapping.txt maps it to itself);
  * every subclass of androidx.work.ListenableWorker that survived R8 kept its
    name, because WorkManager persists the name and looks it up later.

What it cannot check: reflection that is not in the manifest and not a
worker, and anything only a running phone shows. Those are the phone tests.

Exit 0 when every name survived, 1 when one did not, 2 when there is no
release build to read.

Named inspect_*, not check_*: CI builds the web app, not the APK, so this
cannot run on a push, and check_every_gate_runs.py holds every check_*.py to
running there. Run it by hand after any release build, and before shipping
one.
"""
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BUILD = REPO / 'build' / 'app'
ANDROID = '{http://schemas.android.com/apk/res/android}'
COMPONENTS = ('activity', 'activity-alias', 'service', 'receiver', 'provider')


def find_one(pattern: str) -> Path | None:
    hits = sorted(BUILD.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return hits[0] if hits else None


def manifest_classes(manifest: Path) -> dict[str, str]:
    """Component class -> its kind, from the merged release manifest."""
    root = ET.parse(manifest).getroot()
    package = root.get('package', '')
    app = root.find('application')
    found: dict[str, str] = {}
    if app is None:
        return found
    for kind in COMPONENTS:
        for el in app.findall(kind):
            # An activity-alias names its target, not a class of its own.
            name = el.get(ANDROID + ('targetActivity' if kind == 'activity-alias' else 'name'))
            if not name:
                continue
            if name.startswith('.'):
                name = package + name
            found[name] = kind
    application = app.get(ANDROID + 'name')
    if application:
        found[package + application if application.startswith('.') else application] = 'application'
    return found


def read_mapping(mapping: Path) -> tuple[dict[str, str], dict[str, str]]:
    """(original -> new name for every class R8 kept, new name -> original)."""
    kept: dict[str, str] = {}
    for line in mapping.read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.match(r'^(\S+) -> (\S+):$', line)
        if m:
            kept[m.group(1)] = m.group(2)
    return kept, {v: k for k, v in kept.items()}


def worker_classes(mapping: Path) -> list[str]:
    """Kept classes whose name says they are WorkManager workers.

    mapping.txt does not record superclasses, so this goes by name: a class
    whose name ends in Worker or Work, outside androidx, Kotlin and Java.
    mapping.txt lists every kept class by its ORIGINAL name on the left, so a
    worker R8 renamed is still found here, by the name it had, and reported.
    A worker R8 removed entirely is not listed at all; WorkManager would fail
    to find it too, but this check cannot tell it from a class never used."""
    kept, _ = read_mapping(mapping)
    return [c for c in kept if re.search(r'(Worker|Work)$', c.split('.')[-1])
            and not c.startswith(('androidx.', 'kotlin', 'java'))]


def main() -> int:
    manifest = find_one('intermediates/merged_manifests/release/**/AndroidManifest.xml') \
        or find_one('intermediates/merged_manifest/release/**/AndroidManifest.xml')
    mapping = find_one('outputs/mapping/release/mapping.txt')
    if manifest is None or mapping is None:
        print('No release build to read. Run `flutter build apk --release` first.')
        print(f'  merged manifest: {manifest or "missing"}')
        print(f'  mapping.txt:     {mapping or "missing"}')
        return 2

    kept, _ = read_mapping(mapping)
    problems: list[str] = []
    checked = 0

    for cls, kind in sorted(manifest_classes(manifest).items()):
        checked += 1
        new = kept.get(cls)
        if new is None:
            problems.append(f'{kind} {cls}: not in the APK (R8 removed it, or it was never compiled in)')
        elif new != cls:
            problems.append(f'{kind} {cls}: renamed to {new}; Android will not find it')

    workers = worker_classes(mapping)
    for cls in workers:
        checked += 1
        if kept[cls] != cls:
            problems.append(f'worker {cls}: renamed to {kept[cls]}; WorkManager will not find it')

    print(f'Read {manifest.relative_to(REPO)}')
    print(f'and  {mapping.relative_to(REPO)}')
    print(f'{checked} classes Android or WorkManager look up by name '
          f'({len(workers)} worker(s): {", ".join(workers) or "none"}).')
    if problems:
        print('\nNOT KEPT under their own names:')
        for p in problems:
            print(f'  - {p}')
        print('\nAdd a -keep rule for each to android/app/proguard-rules.pro.')
        return 1
    print('All kept under their own names.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
