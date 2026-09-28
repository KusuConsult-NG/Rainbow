#!/usr/bin/env python3
"""The app and the console must state the same palette.

The console and the mobile app are one product. They did not look like it: the
app is white and red (`lib/core/theme/app_colors.dart`), the console was white
and cobalt blue with slate neutrals. Nothing was broken — each screen was
internally consistent — which is exactly why it lasted, and why an officer who
reported on the handset and then opened the command console arrived somewhere
that looked like a different product.

The fix was to restate the console's tokens as the app's colours. The risk is
that they drift again: two files, two languages, no compiler between them. So
this reads the hexes out of both and fails if a pair disagrees.

It checks the LIGHT theme only, on purpose. The app has no dark theme; the
console's dark theme is the same language after dark and has no counterpart to
compare against. Two values are exempt and named below, because they are
DELIBERATE departures rather than drift.

    python3 scripts/check_palette_parity.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DART = ROOT / 'lib' / 'core' / 'theme' / 'app_colors.dart'
CSS = ROOT / 'hq-dashboard-next' / 'src' / 'app' / 'globals.css'

# console token  ->  the AppColors member it must equal
PAIRS = {
    '--bg-primary': 'background',
    '--bg-secondary': 'surface',
    '--primary': 'primary',
    '--primary-dark': 'primaryDark',
    '--accent': 'secondary',
    '--warning': 'warning',
    '--success': 'success',
    '--info': 'info',
    '--duress': 'danger',
    '--text-primary': 'textPrimary',
    '--text-secondary': 'onSurface',
    '--text-muted': 'textSecondary',
    '--border': 'outline',
    '--border-subtle': 'outlineVariant',
    '--input-bg': 'surfaceLight',
}

# Departures that are recorded in globals.css and must NOT be "fixed" silently.
EXEMPT = {
    # AppColors.textDim is #9E9E9E, about 2.8:1 on white — below the 4.5:1 that
    # ordinary text needs. The console is read at night, on cheap monitors,
    # during incidents. Same neutral grey, legible lightness.
    '--text-dim': ('textDim', '#757575', '#9E9E9E'),
}


def dart_colours() -> dict[str, str]:
    text = DART.read_text()
    found: dict[str, str] = {}
    for name, value in re.findall(
        r'static const Color (\w+)\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)', text
    ):
        found[name] = f'#{value[2:].upper()}'  # drop the alpha byte
    return found


def css_light_tokens() -> dict[str, str]:
    text = CSS.read_text()
    match = re.search(r':root\s*\{(.*?)\n\}', text, re.S)
    if not match:
        raise SystemExit('could not find the :root token block in globals.css')
    block = match.group(1)
    return {
        name: value.upper()
        for name, value in re.findall(r'(--[\w-]+):\s*(#[0-9A-Fa-f]{6})\s*;', block)
    }


def main() -> int:
    app = dart_colours()
    console = css_light_tokens()
    problems: list[str] = []

    for token, member in PAIRS.items():
        if member not in app:
            problems.append(
                f'{DART.name} no longer defines AppColors.{member}, which '
                f'{token} is meant to mirror'
            )
            continue
        if token not in console:
            problems.append(
                f'globals.css :root no longer defines {token} as a plain hex '
                f'(it must mirror AppColors.{member} = {app[member]})'
            )
            continue
        if console[token] != app[member]:
            problems.append(
                f'{token} is {console[token]} but AppColors.{member} is '
                f'{app[member]} — the console and the app disagree about the '
                f'same colour'
            )

    for token, (member, expected_css, expected_dart) in EXEMPT.items():
        if console.get(token) != expected_css:
            problems.append(
                f'{token} is {console.get(token)}, expected the recorded '
                f'departure {expected_css}. If this is intended, update '
                f'EXEMPT here and the note in globals.css.'
            )
        if app.get(member) != expected_dart:
            problems.append(
                f'AppColors.{member} is now {app.get(member)}, not '
                f'{expected_dart}. The departure recorded for {token} was '
                f'about the old value — re-check whether it still applies '
                f'(if the app fixed its contrast, the console should simply '
                f'match it again).'
            )

    if problems:
        print('The app and the console disagree about the palette:\n')
        for p in problems:
            print(f'  - {p}')
        print(
            '\nBoth files state the same palette in two languages. Change one, '
            'change the other:\n'
            f'  {DART.relative_to(ROOT)}\n'
            f'  {CSS.relative_to(ROOT)}'
        )
        return 1

    print(
        f'palette parity: {len(PAIRS)} colours match between the app and the '
        f'console, {len(EXEMPT)} recorded departure(s)'
    )
    return 0


if __name__ == '__main__':
    sys.exit(main())
