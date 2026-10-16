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
EMERALD = (0x0F, 0x6C, 0x32)    # the state silhouette — the launcher locator


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


def emblem(master: Image.Image) -> Image.Image:
    """The ring and the map, without the wordmark above or the line below.

    THE LAUNCHER ICON IS NOT THE LOCKUP. Android masks an adaptive icon to a
    circle or a squircle and then the launcher scales it to ~40px: the whole
    lockup put through that gives a clipped "PLATEAU EY" across the top and a
    grey smear underneath where "COMMUNITY REPORTING & VIGILANCE" used to be.
    On the handset it read as a broken image, which is what it was.

    So the launcher, the adaptive foreground and the iOS icons take the
    emblem; everything a person reads at a readable size — the splash, the
    in-app mark, the console — keeps the whole lockup.

    The crop is MEASURED, not typed. The gold inner ring is the only gold in
    the artwork, so its bounding box finds the emblem's centre; the outer navy
    stroke is then walked out along the middle row, and the square is padded
    by a little so the mask does not shave it.
    """
    rgb = master.convert('RGB')
    px = rgb.load()
    w, h = rgb.size

    def near(c, t, tol=40):
        return all(abs(a - b) <= tol for a, b in zip(c, t))

    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if near(px[x, y], GOLD):
                x0, y0 = min(x0, x), min(y0, y)
                x1, y1 = max(x1, x), max(y1, y)
    if x1 < 0:
        raise SystemExit('no gold ring found in the master — the artwork '
                         'changed and the emblem can no longer be located.')
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2

    radius = (x1 - x0) // 2
    for x in range(cx, w):
        if near(px[x, cy], NAVY, 60):
            radius = x - cx
    radius += 14

    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    return trimmed_box(master, box)


def trimmed_box(master: Image.Image, box: tuple[int, int, int, int]):
    """`trimmed`, but on a crop: the page cleared from the border inward."""
    cropped = master.convert('RGBA').crop(box)
    arr = np.array(cropped)
    lum = arr[:, :, :3].min(axis=2)
    page = lum > 230
    reach = np.zeros_like(page)
    reach[0, :] = page[0, :]
    reach[-1, :] = page[-1, :]
    reach[:, 0] = page[:, 0]
    reach[:, -1] = page[:, -1]
    for _ in range(max(cropped.size)):
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= page
        if (grown == reach).all():
            break
        reach = grown
    arr[:, :, 3] = np.where(reach, 0, arr[:, :, 3])
    return Image.fromarray(arr)


def silhouette(master: Image.Image) -> Image.Image:
    """The state on its own — no ring, no disc, no wordmark.

    Reported from a handset: "the app icon on my phone looks very ugly with
    the black circle." The circle is the emblem's outer navy stroke. At 40px
    behind the launcher's own circular mask it stops reading as a ring around
    a map and reads as a dark blob, and the mask's edge and the ring's edge
    fight each other — two concentric circles a few pixels apart.

    The launcher already draws a tile. It does not need the logo to draw one
    as well, so the icon takes the state alone and lets the mask be the shape.
    Everything read at a size where a ring is legible — the splash, the in-app
    mark, the console — keeps the whole lockup, ring and all.

    MEASURED, not typed, for the same reason the emblem crop is: the green of
    the state is the only green in the artwork, so the green itself is the
    shape. The alpha channel is that mask, grown two pixels to carry the
    anti-aliased rim with it; everything else in the artwork goes.

    The alpha is built from the GREEN rather than by clearing white from the
    crop's border, which is what the first attempt did. The ring curves into
    the corners of a square drawn round the map, so two gold wedges sat in the
    bottom corners of every launcher tile: not white, so the flood fill left
    them, and the whole point of the crop was to have no ring in it.

    The tolerance is TIGHT on purpose. At 60 the box grew to 581x826 and took
    in the wordmark, because an anti-aliased navy edge against white passes
    through colours like (33, 54, 91) that are within 60 of the emerald on
    every channel. The box is stable at 340x376 from tolerance 24 through 36,
    so 36 sits in the middle of that plateau rather than at the edge of it.
    """
    arr = np.asarray(master.convert('RGB')).astype(int)
    mask = np.abs(arr - np.array(EMERALD)).max(axis=2) <= 36
    if not mask.any():
        raise SystemExit('no green state found in the master — the artwork '
                         'changed and the silhouette can no longer be found.')

    for _ in range(2):
        grown = mask.copy()
        grown[1:, :] |= mask[:-1, :]
        grown[:-1, :] |= mask[1:, :]
        grown[:, 1:] |= mask[:, :-1]
        grown[:, :-1] |= mask[:, 1:]
        mask = grown

    rgba = np.asarray(master.convert('RGBA')).copy()
    rgba[:, :, 3] = np.where(mask, 255, 0)
    cut = Image.fromarray(rgba, 'RGBA')
    cut = cut.crop(cut.getbbox())

    side = max(cut.size)
    square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    square.paste(cut, ((side - cut.size[0]) // 2,
                       (side - cut.size[1]) // 2), cut)
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


def sample_ink(master: Image.Image) -> dict[str, str]:
    """The three ink colours of the mark, counted off the master itself.

    The palette is not allowed to be a thing somebody typed. These are the
    three most common non-white, non-grey colours in Plateau_Eye_Logo.png —
    the ring and wordmark, the state silhouette, the inner ring — and
    `check_brand_colours.py` holds every declaration of the palette to them.
    Recording them here rather than re-sampling in the check keeps that check
    free of Pillow, which the CI runner does not have.
    """
    rgb = master.convert('RGB')
    counts: dict[tuple[int, int, int], int] = {}
    for pixel in rgb.getdata():
        r, g, b = pixel
        if r + g + b > 600:                      # the page
            continue
        if max(pixel) - min(pixel) < 24:         # a grey or an edge pixel
            continue
        counts[pixel] = counts.get(pixel, 0) + 1
    top = sorted(counts.items(), key=lambda kv: -kv[1])[:3]
    named = {}
    for (r, g, b), _ in top:
        role = ('emerald' if g > r and g > b
                else 'gold' if r > 120 and g > 100
                else 'navy')
        named[role] = f'#{r:02X}{g:02X}{b:02X}'
    return dict(sorted(named.items()))


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
        'ink': sample_ink(Image.open(MASTER)),
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
mark = trimmed(master)          # the whole lockup, for anything read at size
badge = emblem(master)          # ring and map, for anywhere a ring still reads
state = silhouette(master)      # the map alone, for the launcher tile

# The map sits inside the ring, so its crop must be the smaller of the two.
# If a tolerance ever widens enough to swallow the wordmark again, this is
# what says so — the icons would otherwise just quietly go wrong.
if state.size[0] >= badge.size[0]:
    raise SystemExit(
        f'the state silhouette came out {state.size[0]}px against an emblem '
        f'of {badge.size[0]}px. The map is inside the ring, so its crop '
        'cannot be the larger one — the green locator has taken in '
        'something that is not the state.')

made = 0

# ── Android: adaptive foreground, transparent ───────────────────────────────
RES = REPO / 'android' / 'app' / 'src' / 'main' / 'res'
for folder, px in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216),
                   ('xxhdpi', 324), ('xxxhdpi', 432)]:
    # 0.76 is measured, not chosen: with the 16% inset the adaptive XML
    # applies, it is the LARGEST scale that puts no ink at all outside the
    # 66dp guaranteed-visible circle. 0.80 leaves 44 pixels outside it and
    # 0.92 leaves 1152 — which is the map's top-left shoulder clipped off by
    # the launcher's own mask. Every mask shape contains that circle, so
    # nothing here is cropped on any launcher.
    write(on(None, state, px, 0.76),
          RES / f'drawable-{folder}' / 'ic_launcher_foreground.png')
    made += 1

# ── Android: legacy launcher icon, the state on white ──────────────────────
for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                   ('xxhdpi', 144), ('xxxhdpi', 192)]:
    write(on((255, 255, 255), state, px, 0.78),
          RES / f'mipmap-{folder}' / 'ic_launcher.png')
    made += 1

# ── iOS: every size, on navy, no alpha ─────────────────────────────────────
IOS = REPO / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
if IOS.is_dir():
    for icon in sorted(IOS.glob('*.png')):
        px = Image.open(icon).size[0]
        write(on((255, 255, 255), state, px, 0.78, alpha=False), icon)
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
print(f'  * state silhouette cropped to {state.size[0]}x{state.size[1]} for '
      'the launcher and the iOS icons — no ring, because the launcher mask '
      'already draws one and two circles a few pixels apart read as a blob')
print(f'  * emblem available at {badge.size[0]}x{badge.size[1]} for anywhere '
      'a ring is still legible')
print('  * the whole lockup for the splash, the in-app mark and the console')
print('  * iOS icons carry no alpha channel')
