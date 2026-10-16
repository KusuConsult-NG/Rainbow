#!/usr/bin/env python3
"""The resources the app needs to START, and to be accepted by a store.

    python3 scripts/check_app_launch_resources.py

## What went wrong

The Plateau Eye rebrand gave the Android splash a centred logo:

    <item>
        <bitmap android:gravity="center" android:src="@mipmap/ic_launcher" />
    </item>

`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` is an
`<adaptive-icon>`. From API 26 — every Android in use — `@mipmap/ic_launcher`
resolves to **that XML**, not to a PNG. `<bitmap>` requires a bitmap. This file
is the window background of `LaunchTheme`, so the system inflates it before any
Flutter code runs: the app installed, its icon appeared, and tapping it did
nothing at all.

Nothing in the repository could have caught it:

  * aapt2 compiles the reference happily. The resource EXISTS; the type
    mismatch only exists at runtime, so `flutter build apk` succeeded.
  * 734 Flutter tests passed. A widget test renders Dart. It never inflates an
    Android resource, never reads AndroidManifest.xml and never sees a theme.
  * 25 CI gates passed. Every one of them reads Dart, TypeScript or SQL.

So the whole verification estate was green while the app could not start. The
report was "all gates green, you can build the APK now", and the APK was dead.
Flutter's own template ships that `<bitmap>` block commented out, pointing at a
`@mipmap/launch_image` it does not create — the comment is the warning, and
uncommenting it is where this went.

## What this checks

**Android.** Every `<bitmap>` in `res/` names a src that really is a raster,
and is not shadowed by an `anydpi` XML variant — the exact trap above. Every
`@drawable/`, `@mipmap/` and `@color/` reference anywhere in `res/` resolves to
something that exists. And `LaunchTheme`'s windowBackground exists, because
that one is the difference between an app that starts and an app that does not.

**iOS.** No icon in `AppIcon.appiconset` carries an alpha channel. Apple
refuses the build outright (ITMS-90717) and the rebrand's 1024×1024 was RGBA,
so the icons were ready for a submission that would have bounced.

## What it does not check

That the artwork is right, or that the app runs. It cannot: there is no Android
SDK in this container, so nothing here can inflate a resource or boot an
emulator. This encodes the RULES those steps would have enforced.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RES = REPO / 'android' / 'app' / 'src' / 'main' / 'res'
IOS_ICONS = (REPO / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset')

RASTER = {'.png', '.jpg', '.jpeg', '.webp', '.gif'}
REFERENCE = re.compile(r'@(drawable|mipmap|color)/([a-z0-9_]+)')
BITMAP = re.compile(r'<bitmap\b[^>]*?android:src="@(drawable|mipmap)/([a-z0-9_]+)"',
                    re.S)
XML_COMMENT = re.compile(r'<!--.*?-->', re.S)


def live(path: Path) -> str:
    """The file with XML comments blanked, line structure kept.

    Flutter's template ships the <bitmap> block COMMENTED OUT, and the fixed
    `launch_background.xml` quotes the broken line in a comment to explain it.
    A check that reads comments would fail on both — the first is the template
    behaving correctly, the second is the documentation of this very defect.
    """
    text = path.read_text(encoding='utf-8')
    return XML_COMMENT.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)

failures: list[str] = []


def buckets(kind: str, name: str) -> list[Path]:
    """Every file any density bucket provides for `@kind/name`."""
    found = []
    for folder in sorted(RES.glob(f'{kind}*')):
        if not folder.is_dir():
            continue
        for path in folder.iterdir():
            stem = path.name.split('.')[0]
            if stem == name:
                found.append(path)
    return found


def colors() -> set[str]:
    names: set[str] = set()
    for values in sorted(RES.glob('values*')):
        for xml in values.glob('*.xml'):
            names |= set(re.findall(r'<color\s+name="([a-z0-9_]+)"',
                                    live(xml)))
    return names


if not RES.is_dir():
    print(f'{RES} does not exist — has the Android project moved?')
    sys.exit(1)

declared_colors = colors()

# ── 1. A <bitmap> must name a raster, unshadowed by an anydpi XML ────────────
for xml in sorted(RES.rglob('*.xml')):
    text = live(xml)
    for kind, name in BITMAP.findall(text):
        files = buckets(kind, name)
        rasters = [f for f in files if f.suffix.lower() in RASTER]
        shadows = [f for f in files
                   if f.suffix.lower() == '.xml' and 'anydpi' in f.parent.name]
        where = xml.relative_to(REPO)
        if not rasters:
            failures.append(
                f'{where} has <bitmap android:src="@{kind}/{name}"> and '
                f'@{kind}/{name} is not a raster anywhere in res/. <bitmap> '
                'requires a PNG, JPG or WEBP; the window background throws on '
                'inflate and the app dies before Flutter starts.')
        elif shadows:
            names = ', '.join(str(f.relative_to(RES)) for f in shadows)
            failures.append(
                f'{where} has <bitmap android:src="@{kind}/{name}">, but '
                f'{names} shadows it from API 26 onward. On every Android in '
                f'use @{kind}/{name} resolves to that XML, not to the PNG, and '
                '<bitmap> cannot inflate an <adaptive-icon> — the app '
                'installs and will not start. Point it at a raster that has no '
                'anydpi variant, such as @drawable/ic_launcher_foreground.')

# ── 2. Every reference in res/ resolves ─────────────────────────────────────
for xml in sorted(RES.rglob('*.xml')):
    text = live(xml)
    for kind, name in set(REFERENCE.findall(text)):
        if kind == 'color':
            if name not in declared_colors:
                failures.append(
                    f'{xml.relative_to(REPO)} references @color/{name}, which '
                    'no values/*.xml declares.')
        elif not buckets(kind, name):
            failures.append(
                f'{xml.relative_to(REPO)} references @{kind}/{name}, and no '
                f'{kind}* bucket provides it.')

# ── 3. LaunchTheme's window background exists ───────────────────────────────
for values in sorted(RES.glob('values*')):
    styles = values / 'styles.xml'
    if not styles.is_file():
        continue
    text = live(styles)
    block = re.search(r'<style\s+name="LaunchTheme".*?</style>', text, re.S)
    if not block:
        failures.append(f'{styles.relative_to(REPO)} declares no LaunchTheme.')
        continue
    bg = re.search(r'android:windowBackground">@(drawable|color|mipmap)/'
                   r'([a-z0-9_]+)<', block.group(0))
    if not bg:
        continue
    kind, name = bg.group(1), bg.group(2)
    if kind == 'color':
        if name not in declared_colors:
            failures.append(f'{styles.relative_to(REPO)}: LaunchTheme\'s '
                            f'windowBackground @color/{name} is not declared.')
    elif not buckets(kind, name):
        failures.append(f'{styles.relative_to(REPO)}: LaunchTheme\'s '
                        f'windowBackground @{kind}/{name} does not exist, so '
                        'the activity cannot start.')

# ── 4. No iOS icon carries an alpha channel ─────────────────────────────────
alpha: list[str] = []
if IOS_ICONS.is_dir():
    try:
        from PIL import Image
        for icon in sorted(IOS_ICONS.glob('*.png')):
            with Image.open(icon) as im:
                if im.mode in ('RGBA', 'LA', 'P') or 'transparency' in im.info:
                    alpha.append(f'{icon.name} ({im.mode})')
    except ImportError:
        alpha = []
        print('note: Pillow is not installed, so the iOS alpha check was '
              'skipped', file=sys.stderr)
if alpha:
    failures.append(
        'these iOS app icons carry an alpha channel, which Apple rejects on '
        f'upload (ITMS-90717): {", ".join(alpha[:5])}'
        f'{" …" if len(alpha) > 5 else ""}. Flatten them onto the brand '
        'background; an app icon is never transparent in use.')

if failures:
    print('A launch resource that does not resolve, or an icon a store '
          'refuses:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_app_launch_resources.py for why this matters.')
    sys.exit(1)

bitmaps = sum(len(BITMAP.findall(live(x))) for x in RES.rglob('*.xml'))
icons = len(list(IOS_ICONS.glob('*.png'))) if IOS_ICONS.is_dir() else 0
print('The app can find everything it needs to start:')
print(f'  * {bitmaps} <bitmap> src(s) name a raster with no anydpi XML '
      'shadowing them')
print(f'  * every @drawable/@mipmap/@color reference in res/ resolves, '
      f'LaunchTheme included')
print(f'  * {icons} iOS app icons, none carrying an alpha channel')

# ── 5. Every generated asset still matches the master logo ──────────────────
#
# The rebrand's icons were a redraw, not the logo: the state silhouette became
# a lumpy polygon and the ring lost its navy. `scripts/build_brand_assets.py`
# makes all 37 from `Plateau_Eye_Logo.png`, so regenerating must be a no-op.
# If it is not, someone edited an export by hand and the logo is drifting
# again.
import hashlib
import subprocess
import tempfile

GENERATED = [
    'assets/images/app_icon_large.png',
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    'android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png',
]
builder = REPO / 'scripts' / 'build_brand_assets.py'
if builder.is_file() and (REPO / 'Plateau_Eye_Logo.png').is_file():
    before = {f: hashlib.sha256((REPO / f).read_bytes()).hexdigest()
              for f in GENERATED if (REPO / f).is_file()}
    run = subprocess.run([sys.executable, str(builder)],
                         capture_output=True, text=True, cwd=REPO)
    if run.returncode != 0:
        print('scripts/build_brand_assets.py no longer runs:\n'
              f'{run.stderr.strip()[:400]}')
        sys.exit(1)
    drifted = [f for f, h in before.items()
               if hashlib.sha256((REPO / f).read_bytes()).hexdigest() != h]
    if drifted:
        print('Brand assets have drifted from the master logo:\n')
        for f in drifted:
            print(f'  * {f} is not what build_brand_assets.py produces from '
                  'Plateau_Eye_Logo.png. Regenerate rather than editing an '
                  'export: the last time these were drawn by hand instead of '
                  'derived, the app shipped a picture of the logo with the '
                  'wrong state outline.\n')
        sys.exit(1)
    print(f'  * {len(before)} sampled brand assets match what '
          'build_brand_assets.py derives from the master logo')
