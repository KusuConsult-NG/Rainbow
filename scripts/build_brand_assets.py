#!/usr/bin/env python3
"""Every app icon and logo asset, generated from the one master logo.

    python3 scripts/build_brand_assets.py

## Why this exists

The Plateau Eye rebrand did not use the Plateau Eye logo. It drew a new one in
code: the Plateau State silhouette became a lumpy polygon, the navy-and-gold
ring became two gold circles, and the wordmark was moved inside the ring. Every
export — five Android mipmaps, five adaptive foregrounds, twenty-one iOS icons,
three Flutter assets, three console assets — was made from that redraw, so the
app shipped a picture of a logo rather than the logo.

Assets made by hand drift. These are generated, so `Plateau_Eye_Logo.png` is
the single source and regenerating is one command.

## What it makes

THE WHOLE LOCKUP, everywhere. Wordmark, ring, state map and strapline — the
logo as drawn, not a crop of it. An earlier version of this script cropped the
emblem out for the icons, on the reasoning that a strapline is unreadable at
48px; that was not the call to make unilaterally, and the instruction is that
the master is the only logo.

The white page the logo was drawn on is removed where the asset is drawn over
one of the app's own screens, so it takes the screen's colour instead of
sitting in a white square on warm white. Only white CONNECTED TO THE BORDER
goes: the white disc inside the ring is part of the mark and stays.

  * Android adaptive foreground (108-432px): the lockup on TRANSPARENCY, so
    the background layer supplies the colour and the launcher's circular mask
    has something to mask.
  * Android legacy mipmap (48-192px) and iOS (21 sizes): the lockup on WHITE,
    the page it is drawn on, so the tile reads as the logo. iOS carries no
    alpha channel — Apple rejects an icon that has one (ITMS-90717).
  * `app_icon.png` / `app_icon_large.png`: transparent. The splash and login
    draw these at 180x180 on `AppColors.background` (#FAFAF7), so a white
    square would show its own edge against the screen.
  * `logo.png`: the master, untouched.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
MASTER = REPO / 'Plateau_Eye_Logo.png'

NAVY = (0x0B, 0x23, 0x4B)       # Oxford Navy, the icon background
GOLD = (0xB9, 0x91, 0x23)       # Warm Gold, the inner ring — and the locator


def trimmed(master: Image.Image) -> Image.Image:
    """The lockup, cropped to its ink, with the page behind it removed.

    Only white reachable from the border is cleared, by a flood fill inward.
    A blanket "white becomes transparent" would also punch out the disc inside
    the ring, which is part of the mark: the green state map would then sit on
    whatever colour the screen happens to be.
    """
    rgba = np.asarray(master.convert('RGBA')).copy()
    h, w, _ = rgba.shape
    near_white = (rgba[:, :, 0] > 242) & (rgba[:, :, 1] > 242) & (rgba[:, :, 2] > 242)

    # Flood from every border pixel that is near-white.
    outside = np.zeros((h, w), bool)
    stack = [(0, x) for x in range(w) if near_white[0, x]]
    stack += [(h - 1, x) for x in range(w) if near_white[h - 1, x]]
    stack += [(y, 0) for y in range(h) if near_white[y, 0]]
    stack += [(y, w - 1) for y in range(h) if near_white[y, w - 1]]
    for y, x in stack:
        outside[y, x] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near_white[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                stack.append((ny, nx))

    rgba[..., 3] = np.where(outside, 0, 255)
    cut = Image.fromarray(rgba, 'RGBA')
    box = cut.getbbox()
    cut = cut.crop(box)
    # Square it, so every export scales without distorting the lockup.
    side = max(cut.size)
    square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    square.paste(cut, ((side - cut.size[0]) // 2, (side - cut.size[1]) // 2))
    return square


def on(colour, mark: Image.Image, size: int, scale: float = 1.0,
       alpha: bool = True) -> Image.Image:
    """`mark` centred on `colour` (or transparency) at `size`."""
    canvas = Image.new('RGBA', (size, size),
                       (*colour, 255) if colour else (0, 0, 0, 0))
    side = max(1, int(size * scale))
    canvas.paste(mark.resize((side, side), Image.LANCZOS),
                 ((size - side) // 2, (size - side) // 2),
                 mark.resize((side, side), Image.LANCZOS))
    return canvas if alpha else canvas.convert('RGB')


WRITTEN: list[Path] = []


def write(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, 'PNG', optimize=True)
    WRITTEN.append(path)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_manifest() -> Path:
    """Record what was generated, from what, by what.

    `check_app_launch_resources.py` used to verify these assets by RE-RUNNING
    this script and diffing the bytes. That needs Pillow and numpy, which the
    CI runner does not have — so the check failed there with
    `ModuleNotFoundError` while passing locally, which is the worst of both:
    a gate that is red for a reason that has nothing to do with what it
    guards. Pinning the versions would not have fixed it either, since PNG
    encoding is not guaranteed stable across Pillow releases.

    A manifest needs nothing but hashlib. It catches what the check is
    actually for — an asset redrawn or hand-edited instead of derived — and,
    because it records the hashes of this script and of the master logo too, a
    change to either without regenerating is caught as well.
    """
    manifest = REPO / 'assets' / 'brand_manifest.json'
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({
        'generator': 'scripts/build_brand_assets.py',
        'generator_sha256': sha256(Path(__file__).resolve()),
        'master': MASTER.name,
        'master_sha256': sha256(MASTER),
        'assets': {
            str(path.relative_to(REPO)): sha256(path)
            for path in sorted(set(WRITTEN))
        },
    }, indent=2, sort_keys=True) + '\n')
    return manifest


if not MASTER.is_file():
    raise SystemExit(f'{MASTER.name} is missing — it is the source every asset '
                     'here is built from.')

master = Image.open(MASTER)
mark = trimmed(master)
made = 0

# ── Android: adaptive foreground, transparent ───────────────────────────────
RES = REPO / 'android' / 'app' / 'src' / 'main' / 'res'
for folder, px in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216),
                   ('xxhdpi', 324), ('xxxhdpi', 432)]:
    write(on(None, mark, px, 1.0),
          RES / f'drawable-{folder}' / 'ic_launcher_foreground.png')
    made += 1

# ── Android: legacy launcher icon, emblem on navy ──────────────────────────
for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                   ('xxhdpi', 144), ('xxxhdpi', 192)]:
    write(on((255, 255, 255), mark, px, 0.94),
          RES / f'mipmap-{folder}' / 'ic_launcher.png')
    made += 1

# ── iOS: every size, on navy, no alpha ─────────────────────────────────────
IOS = REPO / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
if IOS.is_dir():
    for icon in sorted(IOS.glob('*.png')):
        px = Image.open(icon).size[0]
        write(on((255, 255, 255), mark, px, 0.94, alpha=False), icon)
        made += 1

# ── Flutter assets: the mark on transparency, the lockup whole ─────────────
for name in ('app_icon.png', 'app_icon_large.png'):
    write(on(None, mark, 1024, 0.96), REPO / 'assets' / 'images' / name)
    made += 1
write(master.convert('RGBA'), REPO / 'assets' / 'images' / 'logo.png')
made += 1

# ── The console ────────────────────────────────────────────────────────────
PUB = REPO / 'hq-dashboard-next' / 'public'
if PUB.is_dir():
    for name in ('app_icon.png', 'app_icon_large.png'):
        write(on(None, mark, 1024, 0.96), PUB / name)
        made += 1
    write(master.convert('RGBA'), PUB / 'logo.png')
    made += 1

manifest = write_manifest()

print(f'{made} assets generated from {MASTER.name}')
print(f'  * {manifest.relative_to(REPO)} records each one\'s hash, and the '
      'hashes of this script and the master, so drift is checkable without '
      'Pillow')
print(f'  * lockup trimmed to {mark.size[0]}x{mark.size[1]}, page removed by '
      'flood fill from the border')
print('  * the whole lockup every time: transparent for the app screens, on '
      'white for the launcher tiles')
print('  * iOS icons carry no alpha channel')
