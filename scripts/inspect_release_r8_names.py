#!/usr/bin/env python3
"""Check that R8 kept every class Android looks up by name in a release build.

    flutter build apk --release
    python3 scripts/inspect_release_r8_names.py
    python3 scripts/inspect_release_r8_names.py --manifest M.xml --mapping mapping.txt

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
  * every WorkManager worker that survived R8 kept its name, because
    WorkManager persists the name and looks it up later. A worker is known by
    the (Context, WorkerParameters) constructor WorkManager calls.

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

# WorkManager's abstract base classes. They carry the worker constructor, but
# nothing is ever scheduled as one of them, so R8 may rename them freely (and
# does: ListenableWorker became P1.w in the 2026-11-16 build). mapping.txt
# cannot say a class is abstract, so they are named here.
ABSTRACT_WORKERS = {
    'androidx.work.ListenableWorker',
    'androidx.work.Worker',
    'androidx.work.CoroutineWorker',
    'androidx.work.RxWorker',
    'androidx.work.rxjava3.RxWorker',
}


def find_one(pattern: str) -> Path | None:
    hits = sorted(BUILD.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return hits[0] if hits else None


def manifest_classes(manifest: Path) -> dict[str, tuple[str, bool]]:
    """Component class -> (its kind, whether it is enabled), from the merged
    release manifest. Android's own classes (android.*, java.*) are left out:
    they live in the phone, never in the APK."""
    root = ET.parse(manifest).getroot()
    package = root.get('package', '')
    app = root.find('application')
    found: dict[str, tuple[str, bool]] = {}
    if app is None:
        return found

    def add(name: str, kind: str, enabled: bool) -> None:
        if name.startswith('.'):
            name = package + name
        if not name.startswith(('android.', 'java.', 'javax.')):
            found[name] = (kind, enabled)

    for kind in COMPONENTS:
        for el in app.findall(kind):
            # An activity-alias names its target, not a class of its own.
            name = el.get(ANDROID + ('targetActivity' if kind == 'activity-alias' else 'name'))
            if name:
                add(name, kind, el.get(ANDROID + 'enabled') != 'false')
    application = app.get(ANDROID + 'name')
    if application:
        add(application, 'application', True)
    return found


def read_mapping(mapping: Path) -> tuple[dict[str, str], list[str]]:
    """(original -> new name for every class R8 kept, the kept WorkManager
    workers by original name).

    mapping.txt does not record superclasses, so a worker is recognised by
    the constructor WorkManager calls reflectively,
    `<init>(android.content.Context,androidx.work.WorkerParameters)`, which
    mapping.txt lists under its class. Going by name instead wrongly took
    sqflite's DatabaseWorker, a HandlerThread wrapper, for one."""
    kept: dict[str, str] = {}
    workers: list[str] = []
    current = None
    for line in mapping.read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.match(r'^(\S+) -> (\S+):$', line)
        if m:
            current = m.group(1)
            kept[current] = m.group(2)
        elif (current and '<init>(android.content.Context,androidx.work.WorkerParameters)' in line
              and current not in workers and current not in ABSTRACT_WORKERS):
            workers.append(current)
    return kept, workers


def main(argv: list[str]) -> int:
    args = dict(zip(argv[::2], argv[1::2]))
    manifest = Path(args['--manifest']) if '--manifest' in args else (
        find_one('intermediates/merged_manifests/release/**/AndroidManifest.xml')
        or find_one('intermediates/merged_manifest/release/**/AndroidManifest.xml'))
    mapping = Path(args['--mapping']) if '--mapping' in args else \
        find_one('outputs/mapping/release/mapping.txt')
    if manifest is None or mapping is None or not manifest.exists() or not mapping.exists():
        print('No release build to read. Run `flutter build apk --release` first.')
        print(f'  merged manifest: {manifest or "missing"}')
        print(f'  mapping.txt:     {mapping or "missing"}')
        return 2

    kept, workers = read_mapping(mapping)
    problems: list[str] = []
    notes: list[str] = []
    components = manifest_classes(manifest)

    for cls, (kind, enabled) in sorted(components.items()):
        new = kept.get(cls)
        if new is None and not enabled:
            # Declared disabled, with no class behind it: Play services'
            # ModuleDependencies is a metadata entry of exactly this kind.
            # A component enabled at run time (WorkManager's receivers are)
            # does have a class, and is held to the rule below.
            notes.append(f'{kind} {cls}: not in the APK, and declared disabled')
        elif new is None:
            problems.append(f'{kind} {cls}: not in the APK (R8 removed it, or it was never compiled in)')
        elif new != cls:
            problems.append(f'{kind} {cls}: renamed to {new}; Android will not find it')

    for cls in workers:
        if kept[cls] != cls:
            problems.append(f'worker {cls}: renamed to {kept[cls]}; WorkManager will not find it')

    print(f'Read {manifest}')
    print(f'and  {mapping}')
    print(f'{len(components)} manifest components and {len(workers)} WorkManager worker(s), '
          'all looked up by name:')
    for w in workers:
        print(f'  worker {w}')
    for n in notes:
        print(f'  note: {n}')
    if problems:
        print('\nNOT KEPT under their own names:')
        for p in problems:
            print(f'  - {p}')
        print('\nAdd a -keep rule for each to android/app/proguard-rules.pro.')
        return 1
    print('All kept under their own names.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
