#!/usr/bin/env python3
"""Nothing on a top bar may be the same colour as the top bar.

    python3 scripts/check_nothing_is_painted_invisible.py

## What went wrong

Reported from a handset, first run after installing:

> the colors of the menu on the top left where the SOS button is are hidden.
> all the features on the top are swallowed by the deep-blue color

The home screen's app bar is `AppColors.primary` — Oxford Navy, `#0B234B`. On
it, the home screen painted:

    Icon(Icons.menu_rounded, color: AppColors.onBackground)   #1A1A1A on navy
    color: AppColors.primary.withValues(alpha: 0.08)          navy on navy
    color: AppColors.primary.withValues(alpha: 0.15)          navy on navy
    color: AppColors.primary          (the language label)     navy on navy
    color: AppColors.primary          (the chevron)            navy on navy
    Icon(Icons.notifications, color: AppColors.textSecondary)  #616161 on navy

The whole language switcher was invisible and the menu button nearly so:
1.00:1, 1.12:1, 2.50:1.

It was not always wrong. `primary` used to be `#E31E24`, a bright red, and
dark grey on red is poor but legible. The Plateau Eye rebrand made the app bar
navy and nothing re-checked what was being painted on it — `onBackground` is
the colour for content on the WARM WHITE screen, and it kept its name while
the surface under it changed.

`check_brand_colours.py` did not catch this. It holds every declared colour to
the logo and checks the contrast of the PAIRS THE PALETTE DECLARES. It has no
opinion about which colour a widget actually paints on which surface, and that
is where this lived.

## What this checks

Two kinds of top bar, because this app has both:

1. Every `AppBar(...)` in `lib/` — three screens. The surface is the bar's own
   `backgroundColor:` if it sets one, otherwise `appBarTheme`'s.
2. Every class that `implements PreferredSizeWidget` — `RainbowAppBar`, which
   fourteen screens use and which is not an `AppBar` at all but a `Container`.
   The first version of this check counted "3 AppBar(...) blocks" and said
   "everything on every app bar can be seen", having never read the widget
   that paints the top of fourteen of the seventeen screens. The surface is
   the root widget's own fill.

Every `color: AppColors.X` inside is composited over that surface — alpha
included, because a translucent foreground over its own hue is the most
invisible of the lot — and must clear a floor:

  * **content** (an icon, a label — anything that is not a surface) `3.0:1`,
    the WCAG floor for icons and large text.
  * **decoration** (a `BoxDecoration` fill, a `Border`/`BorderSide`) `1.05:1`.
    A deliberate wash sits at 1.09:1 and a hairline at 1.26:1; both are
    correct, and holding them to 3:1 would mean they were not washes. What
    1.05 still catches is the thing this check exists for: a border or a fill
    painted in *exactly* its own background's colour, which is 1.00:1.

3:1 rather than 4.5:1 for content on purpose: this is a check against
INVISIBLE, not a general accessibility audit, and the failures it exists for
sit at 1.00. Content inside a chip is measured against the BAR, not the chip's
own fill — a 12% wash barely moves the surface, and measuring against the bar
is the conservative direction.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / 'lib'
CONTENT_FLOOR = 3.0
DECORATION_FLOOR = 1.05

failures: list[str] = []
skipped: list[str] = []
measured: list[str] = []


def live(path: Path) -> str:
    """The file with comments and string bodies blanked, newlines preserved.

    String bodies go too: this check counts brackets to work out what encloses
    a colour, and a bracket inside a label would throw that count off.
    """
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group().count('\n'),
                 path.read_text(), flags=re.S)
    src = '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n'))
    return re.sub(r"'''.*?'''|\"\"\".*?\"\"\"|'[^'\n]*'|\"[^\"\n]*\"",
                  lambda m: re.sub(r'[^\n]', ' ', m.group()), src, flags=re.S)


# ── the palette, read rather than typed ─────────────────────────────────────
PALETTE: dict[str, tuple[int, int, int]] = {}
for match in re.finditer(
        r'static const Color (\w+)\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)',
        live(LIB / 'core' / 'theme' / 'app_colors.dart')):
    value = int(match.group(2), 16)
    PALETTE[match.group(1)] = ((value >> 16) & 0xFF, (value >> 8) & 0xFF,
                               value & 0xFF)

if not PALETTE:
    print('could not read lib/core/theme/app_colors.dart — no colours found.')
    sys.exit(1)


def luminance(rgb: tuple[int, int, int]) -> float:
    def channel(v: int) -> float:
        s = v / 255
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def over(fg: tuple[int, int, int], alpha: float,
         bg: tuple[int, int, int]) -> tuple[int, int, int]:
    return tuple(round(f * alpha + b * (1 - alpha)) for f, b in zip(fg, bg))


def block_at(code: str, open_paren: int) -> str:
    """`code` from `open_paren` to the `)` that closes it."""
    depth = 0
    for index in range(open_paren, len(code)):
        if code[index] == '(':
            depth += 1
        elif code[index] == ')':
            depth -= 1
            if depth == 0:
                return code[open_paren:index]
    return code[open_paren:]


NAME_BEFORE_PAREN = re.compile(r'[A-Za-z_][A-Za-z0-9_.]*$')


def open_calls(text: str, pos: int) -> list[str]:
    """The names of the calls whose brackets are still open at `pos`.

    Replaces a `rfind('BoxDecoration(')` heuristic that got three colours
    wrong in a row — it could not tell a fill from the border beside it, nor a
    popup item from the bar it hangs off.
    """
    stack: list[str] = []
    for index in range(pos):
        character = text[index]
        if character in '([{':
            name = ''
            if character == '(':
                found = NAME_BEFORE_PAREN.search(text[:index])
                if found:
                    name = found.group()
            stack.append(name)
        elif character in ')]}' and stack:
            stack.pop()
    return stack


DECORATIVE = ('BoxDecoration', 'Border', 'Border.all', 'BorderSide',
              'BorderDirectional', 'UnderlineInputBorder', 'OutlineInputBorder')


def is_decoration(calls: list[str]) -> bool:
    return any(name.split('.')[-1].startswith('Border')
               or name.endswith('BoxDecoration') for name in calls)


COLOUR = re.compile(
    r'color:\s*AppColors\.(\w+)(?:\.withValues\(alpha:\s*([0-9.]+)\))?')


def drop_popups(block: str) -> str:
    """Blank every `itemBuilder:` argument.

    A popup's items are lexically inside the `AppBar( ... )` and render on the
    menu surface, not on the bar. Measuring them here flagged two correct
    colours.
    """
    while True:
        at = block.find('itemBuilder:')
        if at == -1:
            return block
        depth, cut = 0, len(block)
        for index in range(at, len(block)):
            character = block[index]
            if character in '([{':
                depth += 1
            elif character in ')]}':
                depth -= 1
                if depth < 0:
                    cut = index
                    break
        block = block[:at] + ' ' * (cut - at) + block[cut:]


def inspect(path: Path, code: str, start: int, block: str, bg_name: str,
            label: str, surface_at: int | None = None) -> None:
    """Measure every colour in `block` against `AppColors.[bg_name]`."""
    bg = PALETTE[bg_name]
    block = drop_popups(block)
    for colour in COLOUR.finditer(block):
        if surface_at is not None and colour.start() == surface_at:
            continue  # that one IS the surface
        name, alpha = colour.group(1), colour.group(2)
        if name not in PALETTE:
            continue
        fg = PALETTE[name]
        if alpha is not None:
            fg = over(fg, float(alpha), bg)
        decoration = is_decoration(open_calls(block, colour.start()))
        floor = DECORATION_FLOOR if decoration else CONTENT_FLOOR
        ratio = contrast(fg, bg)
        if ratio >= floor:
            continue
        line = code[:start + colour.start()].count('\n') + 1
        shown = f'AppColors.{name}'
        if alpha is not None:
            shown += f' at {alpha} alpha'
        failures.append(
            f'{path.relative_to(REPO)}:{line} paints {shown} as '
            f'{"decoration" if decoration else "content"} on {label}, whose '
            f'background is AppColors.{bg_name} — contrast {ratio:.2f}:1, '
            f'against a floor of {floor}. '
            'A citizen cannot press what they cannot see.')


# ── the theme's app bar background ──────────────────────────────────────────
theme = live(LIB / 'core' / 'theme' / 'app_theme.dart')
bar = re.search(r'appBarTheme:\s*AppBarTheme\((.*?)\n      \),', theme, re.S)
default_name = None
if bar:
    found = re.search(r'backgroundColor:\s*AppColors\.(\w+)', bar.group(1))
    if found:
        default_name = found.group(1)

if default_name is None or default_name not in PALETTE:
    print('Something on a top bar is invisible:\n')
    print('  * could not read appBarTheme.backgroundColor from '
          'app_theme.dart, so this check cannot know what every AppBar is '
          'painted on. Name it with an AppColors constant.\n')
    sys.exit(1)

# ── 1. every AppBar(...) ────────────────────────────────────────────────────
app_bars = 0
for path in sorted(LIB.rglob('*.dart')):
    code = live(path)
    for match in re.finditer(r'(?<![A-Za-z0-9_])AppBar\(', code):
        block = block_at(code, match.end() - 1)
        # A background this check cannot name is one it must not guess at.
        # `Colors.transparent` is the common case and it means the SCAFFOLD
        # shows through, so the theme's app bar colour is exactly the wrong
        # thing to measure against — the first version of this check reported
        # emergency_pin_screen.dart for that reason, and the screen was right.
        own = re.search(r'backgroundColor:\s*([^,\n]+)', block)
        if own:
            named = re.match(r'AppColors\.(\w+)', own.group(1).strip())
            if not named:
                skipped.append(
                    f'{path.relative_to(REPO)}: an AppBar whose background is '
                    f'{own.group(1).strip()}')
                continue
            bg_name = named.group(1)
        else:
            bg_name = default_name
        if bg_name not in PALETTE:
            skipped.append(f'{path.relative_to(REPO)}: an AppBar whose '
                           f'background is AppColors.{bg_name}, '
                           f'which is not in the palette')
            continue
        app_bars += 1
        inspect(path, code, match.start(), block, bg_name, 'an AppBar')
measured.append(f'{app_bars} AppBar(...) blocks, default background '
                f'AppColors.{default_name}')

# ── 2. every custom top bar: a class that implements PreferredSizeWidget ────
custom = 0
for path in sorted(LIB.rglob('*.dart')):
    code = live(path)
    for match in re.finditer(
            r'class\s+(\w+)[^{]*implements\s+[^{]*PreferredSizeWidget[^{]*\{',
            code):
        name = match.group(1)
        body = block_at(code.replace('{', '(').replace('}', ')'),
                        match.end() - 1)
        body = code[match.end() - 1:match.end() - 1 + len(body)]
        # The bar's own surface is the fill of the widget `build` returns.
        root = re.search(r'\breturn\s+([A-Za-z_][\w.]*)\(', body)
        if root is None:
            skipped.append(f'{path.relative_to(REPO)}: {name}, whose build() '
                           f'has no single returned widget')
            continue
        rooted = block_at(body, root.end() - 1)
        surface = None
        for colour in COLOUR.finditer(rooted):
            calls = open_calls(rooted, colour.start())
            if is_decoration(calls) and len(calls) <= 2:
                surface = colour
                break
        if surface is None or surface.group(1) not in PALETTE:
            skipped.append(
                f'{path.relative_to(REPO)}: {name}, a PreferredSizeWidget '
                f'whose root {root.group(1)} declares no AppColors fill, so '
                f'this check cannot know what its contents sit on')
            continue
        custom += 1
        inspect(path, code, match.end() - 1 + (root.end() - 1), rooted,
                surface.group(1), f'{name} (used as a top bar)',
                surface_at=surface.start())
        measured.append(f'{name} in {path.relative_to(REPO)}, surface '
                        f'AppColors.{surface.group(1)}')

if custom == 0:
    failures.append(
        'no PreferredSizeWidget was measured. Fourteen screens take their top '
        'bar from one, and the first version of this check read none of them '
        'while reporting "everything on every app bar can be seen". If the '
        'shared bar has been renamed or no longer implements '
        'PreferredSizeWidget, teach this check how to find it.')

if failures:
    print('Something on a top bar is invisible:\n')
    for message in failures:
        print(f'  * {message}\n')
    sys.exit(1)

print('OK: everything on every top bar can be seen.')
for note in skipped:
    print(f'  ~ not measured — {note}')
for note in measured:
    print(f'  * {note}')
print(f'  * every colour in them composited over its surface, alpha '
      f'included: content at {CONTENT_FLOOR}:1, decoration at '
      f'{DECORATION_FLOOR}:1')
