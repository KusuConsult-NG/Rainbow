#!/usr/bin/env python3
"""A reinstall must not hand the new install the old install's session.

Why this gate exists
--------------------
A tester wiped the app, installed a fresh APK, and was dropped straight onto
the home screen — no splash, no sign-in, no phone number, no OTP.  The router
was not at fault: `computeRedirect` sends an unauthenticated user to
`/login` from anywhere, and `test/router_redirect_test.dart` has pinned that
since T-39.  The user was not unauthenticated.  `supabase_flutter` persists
the session in SharedPreferences, and `android:allowBackup` was unset in
`AndroidManifest.xml` — which Android reads as **true**.  So the platform was
free to back those preferences up and restore them into the next install.

For an app that holds a duress PIN and a responder's identity, "the previous
owner's session is restored from the cloud" is not a nuisance, it is the whole
threat model inverted.  The two rules files exist so that flipping
`allowBackup` back to true cannot quietly re-open it, and this gate exists so
that neither the attribute nor the files can be dropped again by a merge, a
Flutter template upgrade, or somebody chasing a different bug.

What it proves
--------------
1. `<application>` sets `android:allowBackup="false"`.
2. It names both rules files — `fullBackupContent` (Android 11 and below) and
   `dataExtractionRules` (Android 12+).
3. Both files exist where the manifest says, and parse.
4. Every storage domain is excluded in both: in `<full-backup-content>`, and
   in BOTH `<cloud-backup>` and `<device-transfer>`.  A rules file that
   excludes the cloud but not device-to-device transfer leaves the session
   walking onto the next handset.

Exit 0 and say what was proved; exit 1 and name the hole.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
ANDROID = '{http://schemas.android.com/apk/res/android}'

# Every domain Android can carry across an install.  `sharedpref` is the one
# that holds the Supabase session; the rest are listed because a future
# feature writing a file or a database must not reopen the hole either.
DOMAINS = {'root', 'file', 'database', 'sharedpref', 'external'}

faults: list[str] = []
proved: list[str] = []


def resource_path(value: str) -> Path | None:
    """`@xml/backup_rules` -> android/app/src/main/res/xml/backup_rules.xml"""
    m = re.fullmatch(r'@(\w+)/(\w+)', value or '')
    if not m:
        return None
    return MANIFEST.parent / 'res' / m.group(1) / f'{m.group(2)}.xml'


def excluded_domains(parent: ET.Element) -> set[str]:
    return {
        e.get(f'{ANDROID}domain')
        for e in parent.findall('exclude')
        if e.get(f'{ANDROID}domain') or e.get('domain')
    } | {
        e.get('domain')
        for e in parent.findall('exclude')
        if e.get('domain')
    } - {None}


def check_all_domains(label: str, parent: ET.Element) -> None:
    missing = DOMAINS - excluded_domains(parent)
    if missing:
        faults.append(
            f'{label} does not exclude {", ".join(sorted(missing))} — '
            f'that data can cross a reinstall'
        )
    else:
        proved.append(f'{label} excludes all {len(DOMAINS)} storage domains')


try:
    app = ET.parse(MANIFEST).getroot().find('application')
except ET.ParseError as e:
    print(f'FAIL: {MANIFEST.relative_to(ROOT)} does not parse: {e}')
    sys.exit(1)

if app is None:
    print(f'FAIL: {MANIFEST.relative_to(ROOT)} has no <application> element')
    sys.exit(1)

# 1. allowBackup
allow = app.get(f'{ANDROID}allowBackup')
if allow is None:
    faults.append(
        'android:allowBackup is unset in <application>. Android reads an '
        'absent allowBackup as TRUE, so the session in SharedPreferences can '
        'be restored into a fresh install. Set it to "false".'
    )
elif allow != 'false':
    faults.append(f'android:allowBackup is "{allow}", must be "false"')
else:
    proved.append('android:allowBackup="false"')

# 2 + 3 + 4. the two rules files
for attr, root_tag, sections in (
    ('fullBackupContent', 'full-backup-content', [None]),
    ('dataExtractionRules', 'data-extraction-rules',
     ['cloud-backup', 'device-transfer']),
):
    value = app.get(f'{ANDROID}{attr}')
    if not value:
        faults.append(
            f'android:{attr} is unset, so nothing constrains what '
            f'{"Android 11 and below back up" if attr == "fullBackupContent" else "Android 12+ copies to the cloud or the next handset"} '
            f'if allowBackup is ever set back to true'
        )
        continue
    path = resource_path(value)
    if path is None:
        faults.append(f'android:{attr}="{value}" is not a resource reference')
        continue
    if not path.exists():
        faults.append(
            f'android:{attr}="{value}" points at '
            f'{path.relative_to(ROOT)}, which does not exist — the build '
            f'will fail, or worse, the rules silently will not apply'
        )
        continue
    try:
        rules = ET.parse(path).getroot()
    except ET.ParseError as e:
        faults.append(f'{path.relative_to(ROOT)} does not parse: {e}')
        continue
    if rules.tag != root_tag:
        faults.append(
            f'{path.relative_to(ROOT)} has root <{rules.tag}>, '
            f'expected <{root_tag}>'
        )
        continue
    rel = path.relative_to(ROOT)
    for section in sections:
        if section is None:
            check_all_domains(f'{rel}', rules)
            continue
        node = rules.find(section)
        if node is None:
            faults.append(
                f'{rel} has no <{section}> section — '
                f'{"cloud backup" if section == "cloud-backup" else "device-to-device transfer"} '
                f'is then unconstrained'
            )
        else:
            check_all_domains(f'{rel} <{section}>', node)

if faults:
    print('FAIL: a reinstall could restore the previous session.')
    for f in faults:
        print(f'  - {f}')
    sys.exit(1)

print('OK: a reinstall starts at the sign-in screen.')
for p in proved:
    print(f'  * {p}')
