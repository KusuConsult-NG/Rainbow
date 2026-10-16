#!/usr/bin/env python3
"""Every colour in the product comes from the logo, or from a ramp built on it.

    python3 scripts/check_brand_colours.py

## What went wrong

The palette file was right and almost nothing used it.

`lib/core/theme/app_colors.dart` declared Oxford Navy, Highland Emerald and
Warm Gold — the three ink colours of `Plateau_Eye_Logo.png`, exactly. Then:

  * the SOS button on the citizen home screen was a gradient from `#FF1744`
    to `#880E4F`: a crimson that ends in magenta;
  * the voice-report button beside it ran indigo `#3F51B5` to cyan `#00BCD4`,
    the only cyan in the product;
  * all twelve report categories carried a hue of their own — Fire orange,
    Police brutality cobalt, Child abuse purple, Cattle rustling brown, Flood
    sky, Public property teal — so the list a citizen scrolls was a paint
    chart, and none of those twelve were in the mark;
  * the responder dashboard was Tailwind slate (`#0F172A`, `#94A3B8`,
    `#E2E8F0`), left over from an older console;
  * the console carried 57 distinct colours, 35 of them off-brand, including
    `#E31E24` in 37 places — the red of the brand this product was called
    BEFORE. `incident-dossier.ts` returned it with the comment
    "AppColors.danger", and its own test asserted it as "the app's palette
    spelled out". `AppColors.danger` was `#D32F2F`. It was never that red.

Every one of those was written straight into a widget or a component, where
changing the palette could not reach it. `check_palette_parity.py` compared
the two token files and passed the whole time, because none of this was in a
token file.

## What this checks

  1. The three anchors — navy, emerald, gold — are the logo's own ink, as
     `build_brand_assets.py` counted it off `Plateau_Eye_Logo.png` and wrote
     into `assets/brand_manifest.json`. Not a hex somebody typed.
  2. `lib/core/theme/app_colors.dart`, `hq-dashboard-next/src/lib/brand.ts`
     and the console's `globals.css` all agree on those three.
  3. No colour literal anywhere in `lib/` except the palette file, and no
     Material named colour beyond white, black and transparent.
  4. Every colour in the console's TypeScript is a member of the ramp.
  5. Text on each brand fill clears 4.5:1, computed here rather than assumed.

Comments are blanked before any of this, so a file may quote the defect it
documents — several of them do.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DART = REPO / 'lib' / 'core' / 'theme' / 'app_colors.dart'
TS = REPO / 'hq-dashboard-next' / 'src' / 'lib' / 'brand.ts'
CSS = REPO / 'hq-dashboard-next' / 'src' / 'app' / 'globals.css'
MANIFEST = REPO / 'assets' / 'brand_manifest.json'
CONSOLE_SRC = REPO / 'hq-dashboard-next' / 'src'

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def live(path: Path) -> str:
    """The file's code, with comments blanked.

    This check's own documentation names every colour it forbids, and so do
    several of the files it reads. A sweep that cannot tell code from prose
    rewrote one of those comments into nonsense while this was being written,
    which is the second reason for this function.
    """
    src = path.read_text()
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group().count('\n'), src, flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '*', '/*')) else line
        for line in src.split('\n')
    )


def luminance(hex_colour: str) -> float:
    def channel(value: int) -> float:
        srgb = value / 255
        return srgb / 12.92 if srgb <= 0.04045 else ((srgb + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    lo, hi = sorted((la, lb))
    return (hi + 0.05) / (lo + 0.05)


for path in (DART, TS, CSS, MANIFEST):
    if not path.is_file():
        sys.exit(f'{path.relative_to(REPO)} is missing — this check cannot say '
                 'anything about a palette that is not there.')

# ── 1. The anchors are the logo's own ink ────────────────────────────────────
manifest = json.loads(MANIFEST.read_text())
ink = manifest.get('ink')
if not ink or set(ink) != {'navy', 'emerald', 'gold'}:
    sys.exit('assets/brand_manifest.json carries no `ink` block naming navy, '
             'emerald and gold. Run `python3 scripts/build_brand_assets.py`, '
             'which counts them off Plateau_Eye_Logo.png — the palette is not '
             'allowed to be three hexes somebody typed.')

dart = live(DART)
ts = live(TS)
css = live(CSS)


def dart_colour(member: str) -> str | None:
    m = re.search(rf'\b{member}\s*=\s*Color\(0xFF([0-9A-Fa-f]{{6}})\)', dart)
    return f'#{m.group(1).upper()}' if m else None


def ts_colour(key: str) -> str | None:
    m = re.search(rf"\b{key}:\s*'#([0-9A-Fa-f]{{6}})'", ts)
    return f'#{m.group(1).upper()}' if m else None


def css_token(token: str) -> str | None:
    root = re.search(r':root\s*\{(.*?)\n\}', css, re.S)
    if not root:
        return None
    m = re.search(rf'{re.escape(token)}:\s*#([0-9A-Fa-f]{{6}})', root.group(1))
    return f'#{m.group(1).upper()}' if m else None


# ── 2. All three declarations agree with it ──────────────────────────────────
ANCHORS = [
    ('navy', 'primary', 'navy', '--primary'),
    ('emerald', 'emerald', 'emerald', '--success'),
    ('gold', 'gold', 'gold', '--accent'),
]
for role, dart_member, ts_key, token in ANCHORS:
    want = ink[role].upper()
    for where, got in (
        (f'{DART.relative_to(REPO)} AppColors.{dart_member}', dart_colour(dart_member)),
        (f'{TS.relative_to(REPO)} BRAND.{ts_key}', ts_colour(ts_key)),
        (f'{CSS.relative_to(REPO)} {token}', css_token(token)),
    ):
        if got is None:
            fail(f'{where} is not declared, so nothing holds it to the mark.')
        elif got != want:
            fail(f'{where} is {got}; the {role} in Plateau_Eye_Logo.png is '
                 f'{want}. The palette has drifted from the logo it is '
                 'supposed to be.')

# ── 3. Nothing in lib/ names a colour but the palette file ───────────────────
for path in sorted((REPO / 'lib').rglob('*.dart')):
    if path == DART:
        continue
    code = live(path)
    for match in re.finditer(r'Color\(0x[0-9A-Fa-f]{8}\)', code):
        line = code[:match.start()].count('\n') + 1
        fail(f'{path.relative_to(REPO)}:{line} writes a colour literal, '
             f'`{match.group()}`. Every colour belongs in AppColors, where '
             'changing the brand can reach it — this is how a crimson SOS '
             'button and twelve category pastels survived a rebrand.')
    for match in re.finditer(r'(?<!App)\bColors\.([a-zA-Z]+)', code):
        if match.group(1) in ('white', 'black', 'transparent'):
            continue
        line = code[:match.start()].count('\n') + 1
        fail(f'{path.relative_to(REPO)}:{line} uses `{match.group()}`, a '
             'Material palette colour. Material\'s palette is not this '
             'product\'s palette; use an AppColors member.')

# ── 4. The console stays inside the ramp ─────────────────────────────────────
ramp = {f'#{c.upper()}' for c in re.findall(r'Color\(0x[0-9A-Fa-f]{2}([0-9A-Fa-f]{6})\)', dart)}
ramp |= {f'#{c.upper()}' for c in re.findall(r'#([0-9A-Fa-f]{6})', css)}
if len(ramp) < 10:
    sys.exit('fewer than ten colours found in app_colors.dart and globals.css '
             '— the format changed and this check would pass over anything.')

# The console's own module may restate the palette. It may not invent.
for match in re.finditer(r"(\w+):\s*'(#[0-9A-Fa-f]{6})'", ts):
    key, colour = match.group(1), match.group(2).upper()
    if colour not in ramp:
        line = ts[:match.start()].count('\n') + 1
        fail(f'{TS.relative_to(REPO)}:{line}: BRAND.{key} is {colour}, which '
             'the Flutter palette does not declare. The console restates the '
             'app\'s palette; a colour that exists only here is a second '
             'palette, which is how the two drifted apart before.')

for path in sorted(CONSOLE_SRC.rglob('*.ts')) + sorted(CONSOLE_SRC.rglob('*.tsx')):
    if path == TS:
        continue
    code = live(path)
    # `not.toContain('#0F172A')` names a colour the code must NOT have. That
    # is a check against drift, not drift.
    forbidden = {m.group(1).upper() for m in
                 re.finditer(r"not\.toContain\(\s*'#([0-9A-Fa-f]{6})'", code)}
    for match in re.finditer(r'#([0-9A-Fa-f]{6})\b', code):
        colour = f'#{match.group(1).upper()}'
        if colour in ramp or match.group(1).upper() in forbidden:
            continue
        line = code[:match.start()].count('\n') + 1
        fail(f'{path.relative_to(REPO)}:{line} uses {colour}, which is in '
             'neither brand.ts nor globals.css. The console carried 57 '
             'colours this way, including the previous brand\'s red in 37 '
             'places.')

# ── 5. Text on a brand fill is legible, measured not assumed ─────────────────
PAIRS = [
    ('danger', 'onPrimary', 4.5),
    ('dangerDeep', 'onPrimary', 4.5),
    ('warning', 'surface', 4.5),
    ('primary', 'onPrimary', 4.5),
    ('emerald', 'onPrimary', 4.5),
    ('emeraldDeep', 'emeraldTint', 4.5),
    ('danger', 'dangerTint', 4.5),
    ('warning', 'goldTint', 4.5),
    ('primary', 'navyTint', 4.5),
    ('onPrimarySoft', 'primaryDark', 4.5),
    ('onPrimaryMuted', 'primaryDark', 4.5),
]
measured = 0
for fg_name, bg_name, minimum in PAIRS:
    fg, bg = dart_colour(fg_name), dart_colour(bg_name)
    if not fg or not bg:
        fail(f'AppColors.{fg_name} or AppColors.{bg_name} is gone, so the '
             'contrast between them cannot be checked.')
        continue
    ratio = contrast(fg, bg)
    measured += 1
    if ratio < minimum:
        fail(f'AppColors.{fg_name} on AppColors.{bg_name} is {ratio:.1f}:1, '
             f'under the {minimum}:1 ordinary text needs. This app is read on '
             'a cheap handset, outdoors, during an emergency.')

if failures:
    print('The product has colours that are not the brand:\n')
    for message in failures[:40]:
        print(f'  * {message}\n')
    if len(failures) > 40:
        print(f'  … and {len(failures) - 40} more\n')
    sys.exit(1)

print('OK: every colour traces back to the logo.')
print(f'  * navy {ink["navy"]}, emerald {ink["emerald"]}, gold {ink["gold"]} '
      '— counted off Plateau_Eye_Logo.png, not typed')
print('  * the Flutter palette, brand.ts and globals.css all agree with it')
print('  * no colour literal in lib/ outside app_colors.dart')
print(f'  * every colour in the console is one of the {len(ramp)} the '
      'Flutter palette and globals.css declare')
print(f'  * {measured} text-on-fill pairs measured, all at or above 4.5:1')
